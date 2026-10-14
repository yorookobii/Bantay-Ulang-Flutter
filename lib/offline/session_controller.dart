import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'offline_models.dart';
import 'offline_store.dart';

abstract interface class SessionBackend {
  String? get uid;
  Stream<String?> get changes;
  Future<Map<String, dynamic>> check();
  Future<void> signOut();
}

class FirebaseSessionBackend implements SessionBackend {
  FirebaseSessionBackend(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  @override
  String? get uid => auth.currentUser?.uid;
  @override
  Stream<String?> get changes => auth.authStateChanges().map((u) => u?.uid);
  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<Map<String, dynamic>> check() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SyncConflict('Please log in online to continue.');
    }
    await user.reload();
    await user.getIdToken(true);
    if (auth.currentUser?.emailVerified != true) {
      throw const SyncConflict('Please verify your email before continuing.');
    }
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    final data = doc.data();
    if (data == null || data['role'] != 'user' || data['status'] != 'active') {
      throw const SyncConflict(
        'Your account is not approved for access. Please contact an admin.',
      );
    }
    return data;
  }
}

bool isNetworkFailure(Object error) =>
    error is TimeoutException ||
    error is FirebaseException &&
        const {
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        }.contains(error.code);

bool isAccessRejection(Object error) =>
    error is FirebaseException &&
    const {
      'permission-denied',
      'unauthenticated',
      'user-disabled',
      'user-not-found',
    }.contains(error.code);

class SessionController extends ChangeNotifier {
  SessionController(this.store, this.backend, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final OfflineStore store;
  final SessionBackend backend;
  final DateTime Function() clock;
  OfflineApproval? approval;
  bool ready = false;
  bool online = false;
  bool authAttempt = false;
  String? message;
  int _generation = 0;
  int _accessEpoch = 0;
  int get accessEpoch => _accessEpoch;
  Future<bool>? _refresh;
  Timer? _expiry;
  StreamSubscription<String?>? _authSub;
  String? get uid => backend.uid;
  bool get canAccess => !authAttempt && approval?.permits(uid, clock()) == true;

  Future<void> start() async {
    final currentUid = uid;
    if (currentUid != null) approval = await store.approval(currentUid);
    _authSub = backend.changes.listen((newUid) {
      if (approval != null && newUid != approval!.uid) {
        unawaited(block('Please log in online to continue.'));
      }
    });
    await refresh();
    ready = true;
    notifyListeners();
  }

  Future<void> beginAuthAttempt() async {
    authAttempt = true;
    await block(null);
  }

  void endAuthAttempt() {
    authAttempt = false;
    notifyListeners();
  }

  Future<void> acceptLogin(
    String owner,
    Map<String, dynamic> data, {
    required bool emailVerified,
  }) async {
    if (owner != uid ||
        !emailVerified ||
        data['role'] != 'user' ||
        data['status'] != 'active') {
      throw const SyncConflict(
        'The account must be verified and approved online.',
      );
    }
    final version = ++_generation;
    final saved = OfflineApproval(
      uid: owner,
      checkedAt: clock().toUtc(),
      profile: {
        for (final key in ['fullName', 'email', 'farmId', 'role', 'status'])
          if (data[key] is String) key: data[key],
      },
    );
    await store.saveApproval(saved);
    if (version != _generation || uid != owner) {
      await store.clearApproval(owner);
      return;
    }
    if (approval?.uid != owner) _accessEpoch++;
    approval = saved;
    authAttempt = false;
    online = true;
    ready = true;
    message = null;
    _scheduleExpiry();
    notifyListeners();
  }

  Future<bool> refresh() {
    if (_refresh != null) return _refresh!;
    final future = _check();
    _refresh = future;
    return future.whenComplete(() {
      if (identical(_refresh, future)) _refresh = null;
    });
  }

  Future<bool> _check() async {
    final owner = uid;
    final version = _generation;
    // A persisted Firebase user alone must not turn a signup/resend into a login.
    if (authAttempt || owner == null || approval?.uid != owner) {
      online = false;
      return false;
    }
    try {
      final data = await backend.check().timeout(const Duration(seconds: 12));
      if (_generation != version || uid != owner || authAttempt) return false;
      await acceptLogin(owner, data, emailVerified: true);
      return online;
    } catch (error) {
      if (_generation != version || uid != owner) return false;
      online = false;
      if (isNetworkFailure(error)) {
        message = canAccess
            ? null
            : 'Connect to the internet to renew your seven-day offline access.';
        _scheduleExpiry();
        notifyListeners();
      } else {
        await block(
          error is SyncConflict
              ? error.message
              : 'Account access could not be verified. Please log in online again.',
        );
      }
      return false;
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    if (approval == null) return;
    final remaining = approval!.checkedAt
        .add(OfflineApproval.lifetime)
        .difference(clock());
    if (remaining <= Duration.zero || clock().isBefore(approval!.checkedAt)) {
      return;
    }
    _expiry = Timer(remaining, () {
      online = false;
      message =
          'Connect to the internet to renew your seven-day offline access.';
      notifyListeners();
    });
  }

  void networkLost() {
    online = false;
    notifyListeners();
  }

  Future<void> block(String? reason) async {
    ++_generation;
    ++_accessEpoch;
    final owner = approval?.uid ?? uid;
    approval = null;
    online = false;
    message = reason;
    _expiry?.cancel();
    notifyListeners();
    if (owner != null) {
      try {
        await store.clearApproval(owner);
      } catch (_) {
        // A grant that cannot be erased must not reopen via persisted Auth.
        message =
            'Local access could not be cleared. Please log in online again.';
        try {
          await backend.signOut();
        } catch (_) {
          message =
              'Access is blocked, but sign-out could not finish. Please reopen the app while connected.';
        }
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    try {
      await block(null);
    } finally {
      authAttempt = false;
      await backend.signOut();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
