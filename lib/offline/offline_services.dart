import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import '../notification_service.dart';
import 'local_record_cleanup.dart';
import 'offline_models.dart';
import 'offline_store.dart';
import 'session_controller.dart';
import 'sync_backend.dart';

class OfflineServices with WidgetsBindingObserver {
  OfflineServices(this.store, this.session, this.backend);
  static OfflineServices? current;
  final OfflineStore store;
  final SessionController session;
  final SyncBackend backend;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _foreground = true;
  bool _disposed = false;
  final Set<String> _submitting = {};
  bool get hasAccess => session.canAccess;

  /// Ignore failures from subscriptions belonging to a previous login.
  Future<void> reportReadError(Object error, String? owner, int? epoch) async {
    if (owner != session.uid || epoch != session.accessEpoch) return;
    if (isAccessRejection(error)) {
      await session.block(
        'Access was rejected by the server. Please log in online again.',
      );
    } else if (isNetworkFailure(error)) {
      session.networkLost();
    }
  }

  static Future<OfflineServices> initialize() async {
    final store = await OfflineStore.open();
    final firestore = FirebaseFirestore.instance;
    try {
      await clearLegacyFirestoreRecords(
        store: store,
        clearPersistence: firestore.clearPersistence,
      );
    } catch (_) {
      await store.close();
      rethrow;
    }
    final session = SessionController(
      store,
      FirebaseSessionBackend(FirebaseAuth.instance, firestore),
    );
    final services = OfflineServices(
      store,
      session,
      FirestoreSyncBackend(firestore, () => session.uid),
    );
    current = services;
    NotificationService.instance.canNavigateToTasks = () => session.canAccess;
    WidgetsBinding.instance.addObserver(services);
    services._connectivity = Connectivity().onConnectivityChanged.listen((
      types,
    ) {
      if (types.contains(ConnectivityResult.none)) {
        session.networkLost();
      } else if (services._foreground) {
        unawaited(session.refresh());
      }
    });
    return services;
  }

  Future<void> start() async {
    try {
      await session.start();
    } catch (_) {
      session.ready = true;
      await session.block(
        'Saved access could not be loaded. Please log in online again.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_disposed) unawaited(session.refresh());
  }

  /// Returns a summary-update warning after a confirmed server save.
  /// Submissions live only in memory and are never queued or auto-retried.
  Future<String?> submitOnline(
    OperationKind kind,
    Map<String, dynamic> payload, {
    DateTime? observedAt,
    bool Function()? isCurrent,
  }) async {
    if (!session.online) {
      throw const SyncConflict('Internet connection is required.');
    }
    if (!session.canAccess || session.uid == null || _disposed) {
      throw const SyncConflict(
        'Connect and log in to renew access before recording.',
      );
    }
    final owner = session.uid!;
    final epoch = session.accessEpoch;
    bool sameSession() =>
        !_disposed &&
        session.canAccess &&
        session.uid == owner &&
        session.accessEpoch == epoch &&
        isCurrent?.call() != false;
    bool canSubmit() => sameSession() && session.online;
    final key =
        '$owner:$epoch:${kind.name}:${kind == OperationKind.task ? payload['taskId'] : ''}';
    if (!_submitting.add(key)) {
      throw const SyncConflict('This submission is already saving.');
    }
    try {
      final at = (observedAt ?? DateTime.now()).toUtc();
      final values = Map<String, dynamic>.from(payload);
      // A connectivity hint or cached grant alone cannot authorize a save.
      final connected = await session.refresh();
      if (!sameSession()) {
        throw const SyncConflict(
          'The submission session changed. Please try again.',
        );
      }
      if (!connected || !session.online) {
        throw const SyncConflict('Internet connection is required.');
      }
      final random = Random.secure();
      final id = base64Url
          .encode(List<int>.generate(20, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final profile = session.approval!.profile;
      await backend.upload(
        RecordSubmission(
          id: id,
          uid: owner,
          kind: kind,
          observedAt: at,
          payload: {
            ...values,
            'createdByName': profile['fullName'] ?? '',
            'createdByEmail': profile['email'] ?? '',
          },
        ),
        canSubmit: canSubmit,
      );
      if (!sameSession()) return null;
      try {
        if (kind == OperationKind.mortality) {
          await backend.recalculate(
            values['cycleId'] as String,
            values['cycleStart'] as int,
            canSubmit: canSubmit,
          );
        } else if (kind == OperationKind.ulang) {
          await backend.recalculateLatest(canSubmit: canSubmit);
        }
      } catch (_) {
        return 'The record was saved, but the growth summary could not update. Do not submit this record again.';
      }
      return null;
    } catch (error) {
      if (sameSession()) {
        if (isNetworkFailure(error)) session.networkLost();
        if (!session.online && error is SyncConflict) {
          throw const SyncConflict('Internet connection is required.');
        }
      }
      rethrow;
    } finally {
      _submitting.remove(key);
    }
  }

  Future<void> logout() => session.logout();

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _connectivity?.cancel();
    session.dispose();
    await store.close();
    if (identical(current, this)) {
      current = null;
      NotificationService.instance.canNavigateToTasks = null;
    }
  }
}
