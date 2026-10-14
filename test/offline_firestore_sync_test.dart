import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/sync_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/offline_fakes.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreSyncBackend backend;
  final cycleStart = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
  RecordSubmission death({String id = 'death-a', int week = 2}) =>
      exampleOperation(
        id: id,
        kind: OperationKind.mortality,
        payload: {
          'cycleId': 'cycle',
          'cycleStart': cycleStart,
          'weekNumber': week,
          'deathCount': 3,
        },
      );
  setUp(() async {
    db = FakeFirebaseFirestore();
    backend = FirestoreSyncBackend(db, () => 'farmer-a');
    await db.doc('users/farmer-a').set({'role': 'user', 'status': 'active'});
    await db.doc('growth_indicators/cycle').set({
      'cycleStart': Timestamp.fromMillisecondsSinceEpoch(cycleStart),
      'timestamp': Timestamp.fromMillisecondsSinceEpoch(cycleStart),
      'initialStock': 100,
    });
  });
  test(
    'ulang pair preserves observation time and retries do not alter createdAt',
    () async {
      final op = exampleOperation();
      await backend.upload(op);
      final before = (await db.doc('logs/op-1').get()).data()!;
      await backend.upload(op);
      expect((await db.collection('logs').get()).docs, hasLength(1));
      expect(
        (await db.collection('ulang_growth_records').get()).docs,
        hasLength(1),
      );
      final after = (await db.doc('logs/op-1').get()).data()!;
      expect(after['createdAt'], before['createdAt']);
      expect(
        (after['observedAt'] as Timestamp).toDate().toUtc(),
        op.observedAt,
      );
      expect(
        (await db.doc('ulang_growth_records/op-1').get()).data()!['weight'],
        12.0,
      );
    },
  );
  test('plant entry retains the existing wire fields and types', () async {
    await backend.upload(
      exampleOperation(
        kind: OperationKind.plant,
        payload: {
          'plantName': 'Mint',
          'height': '8',
          'stage': 'Seedling',
          'condition': 'Malusog',
        },
      ),
    );
    final data = (await db.doc('logs/op-1').get()).data()!;
    expect(data['height'], '8');
    expect(data['type'], 'plant');
    expect(data['createdBy'], 'farmer-a');
  });
  test(
    'second mobile mortality submission for the same week is rejected',
    () async {
      await backend.upload(death());
      await expectLater(
        backend.upload(death(id: 'death-other-device')),
        throwsA(isA<SyncConflict>()),
      );
      expect(
        (await db.collection('mortality_records').get()).docs,
        hasLength(1),
      );
      expect((await db.collection('logs').get()).docs, hasLength(1));
      await backend.upload(death());
      expect(
        (await db.collection('mortality_records').get()).docs,
        hasLength(1),
      );
    },
  );
  test('legacy random-ID weekly mortality records are recognized', () async {
    await db.doc('mortality_records/old-web-entry').set({
      'weekNumber': 2,
      'deathCount': 1,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 9)),
    });
    await expectLater(backend.upload(death()), throwsA(isA<SyncConflict>()));
    expect((await db.collection('logs').get()).docs, isEmpty);
  });

  test('a previous week does not block the current week', () async {
    await backend.upload(death(id: 'last-week', week: 1));
    await backend.upload(death());
    expect((await db.collection('mortality_records').get()).docs, hasLength(2));
    expect((await db.collection('logs').get()).docs, hasLength(2));
  });

  test('deleting a legacy weekly record permits a replacement', () async {
    final previous = db.doc('mortality_records/old-web-entry');
    await previous.set({
      'weekNumber': 2,
      'deathCount': 1,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 9)),
    });
    await previous.delete();
    await backend.upload(death());
    expect((await db.collection('mortality_records').get()).docs, hasLength(1));
    expect((await db.collection('logs').get()).docs, hasLength(1));
  });
  test(
    'a changed cycle blocks a new record but reconciles a prior successful upload',
    () async {
      await backend.upload(death());
      await db.doc('growth_indicators/new-cycle').set({
        'timestamp': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
        'cycleStart': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
      });
      await backend.upload(death());
      await expectLater(
        backend.upload(death(id: 'new-entry', week: 3)),
        throwsA(isA<SyncConflict>()),
      );
      expect((await db.collection('logs').get()).docs, hasLength(1));
    },
  );
  test('task completion rechecks assignment and status', () async {
    final task = exampleOperation(
      kind: OperationKind.task,
      payload: {'taskId': 'task-1'},
    );
    await db.doc('tasks/task-1').set({
      'assignedTo': 'farmer-a',
      'status': 'pending',
    });
    await backend.upload(task);
    await backend.upload(task);
    expect((await db.doc('tasks/task-1').get()).data()!['status'], 'done');
    await db.doc('tasks/task-1').update({
      'assignedTo': 'farmer-b',
      'status': 'pending',
    });
    await expectLater(backend.upload(task), throwsA(isA<SyncConflict>()));
    expect((await db.doc('tasks/task-1').get()).data()!['status'], 'pending');
    await db.doc('tasks/task-1').delete();
    await expectLater(backend.upload(task), throwsA(isA<SyncConflict>()));
  });
  test(
    'approval revoked before upload creates neither half of a record pair',
    () async {
      await db.doc('users/farmer-a').update({'status': 'suspended'});
      await expectLater(
        backend.upload(exampleOperation()),
        throwsA(isA<FirebaseException>()),
      );
      expect((await db.collection('logs').get()).docs, isEmpty);
      expect((await db.collection('ulang_growth_records').get()).docs, isEmpty);
    },
  );
  test(
    'growth summary uses confirmed deaths from the original cycle',
    () async {
      await backend.upload(death());
      await backend.recalculate('cycle', cycleStart);
      expect(
        (await db.doc('growth_indicators/cycle').get()).data()!['survivalRate'],
        97.0,
      );
    },
  );
  test('foreign UID never writes even with a valid draft shape', () async {
    await expectLater(
      backend.upload(exampleOperation(uid: 'farmer-b')),
      throwsA(isA<SyncConflict>()),
    );
    expect((await db.collection('logs').get()).docs, isEmpty);
  });
}
