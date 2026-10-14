import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/offline/sync_backend.dart';

class TestSessionBackend implements SessionBackend {
  @override
  String? uid = 'farmer-a';
  bool connected = true;
  bool approved = true;
  int checks = 0;
  Completer<void>? gate;
  final events = StreamController<String?>.broadcast();
  @override
  Stream<String?> get changes => events.stream;
  @override
  Future<Map<String, dynamic>> check() async {
    checks++;
    if (gate != null) await gate!.future;
    if (!connected) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (!approved) throw const SyncConflict('Account suspended.');
    return {
      'fullName': 'Test Farmer',
      'email': 'test@example.com',
      'role': 'user',
      'status': 'active',
    };
  }

  @override
  Future<void> signOut() async {
    uid = null;
    events.add(null);
  }
}

class TestSyncBackend implements SyncBackend {
  final Map<String, RecordSubmission> accepted = {};
  int calls = 0;
  int recalculations = 0;
  Object? failure;
  Object? recalculationFailure;
  bool loseAcknowledgment = false;
  Completer<void>? gate;
  @override
  Future<void> upload(RecordSubmission op, {bool Function()? canSubmit}) async {
    calls++;
    if (gate != null) await gate!.future;
    if (canSubmit?.call() == false) {
      throw const SyncConflict('Session changed.');
    }
    if (failure != null) throw failure!;
    accepted.putIfAbsent(op.id, () => op);
    if (loseAcknowledgment) {
      loseAcknowledgment = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
  }

  @override
  Future<void> recalculate(
    String cycleId,
    int cycleStart, {
    bool Function()? canSubmit,
  }) async {
    recalculations++;
    if (recalculationFailure != null) throw recalculationFailure!;
  }

  @override
  Future<void> recalculateLatest({bool Function()? canSubmit}) =>
      recalculate('latest', 0, canSubmit: canSubmit);
}

RecordSubmission exampleOperation({
  String id = 'op-1',
  String uid = 'farmer-a',
  OperationKind kind = OperationKind.ulang,
  Map<String, dynamic>? payload,
}) => RecordSubmission(
  id: id,
  uid: uid,
  kind: kind,
  observedAt: DateTime.utc(2026, 10, 9, 8),
  payload:
      payload ??
      {
        'size': '5',
        'weight': '12',
        'createdByName': 'Test Farmer',
        'createdByEmail': 'test@example.com',
      },
);
