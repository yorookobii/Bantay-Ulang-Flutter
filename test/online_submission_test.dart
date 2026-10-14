import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/offline_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  late TestSessionBackend auth;
  late SessionController session;
  late TestSyncBackend remote;
  late OfflineServices services;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    auth = TestSessionBackend();
    session = SessionController(store, auth);
    remote = TestSyncBackend();
    services = OfflineServices(store, session, remote);
    OfflineServices.current = services;
    await session.acceptLogin('farmer-a', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
  });
  tearDown(() async {
    await services.dispose();
    await auth.events.close();
  });
  Map<String, dynamic> payload(OperationKind kind) => switch (kind) {
    OperationKind.ulang => {'size': '5', 'weight': '12'},
    OperationKind.plant => {
      'plantName': 'Mint',
      'height': '8',
      'stage': 'Seedling',
      'condition': 'Malusog',
    },
    OperationKind.mortality => {
      'cycleId': 'cycle',
      'cycleStart': 1,
      'weekNumber': 1,
      'deathCount': 3,
    },
    OperationKind.task => {'taskId': 'task'},
  };
  Future<void> expectNoQueue() async {
    final tables = await store.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((r) => r['name']), isNot(contains('operations')));
    expect(tables.map((r) => r['name']), isNot(contains('recalculations')));
  }

  for (final kind in OperationKind.values) {
    test(
      '${kind.name}: offline submissions fail without storing or uploading',
      () async {
        session.networkLost();
        await expectLater(
          services.submitOnline(kind, payload(kind)),
          throwsA(isA<SyncConflict>()),
        );
        expect(remote.calls, 0);
        expect(session.canAccess, isTrue);
        await expectNoQueue();
      },
    );
    test(
      '${kind.name}: stale connectivity requires a successful server check',
      () async {
        auth.connected = false;
        await expectLater(
          services.submitOnline(kind, payload(kind)),
          throwsA(isA<SyncConflict>()),
        );
        expect(auth.checks, 1);
        expect(remote.calls, 0);
        expect(session.canAccess, isTrue);
        await expectNoQueue();
      },
    );
    test(
      '${kind.name}: successful save preserves owner, values and observation time',
      () async {
        final at = DateTime.utc(2026, 10, 11, 8);
        expect(
          await services.submitOnline(kind, payload(kind), observedAt: at),
          isNull,
        );
        final entry = remote.accepted.values.single;
        expect(entry.uid, 'farmer-a');
        expect(entry.kind, kind);
        expect(entry.observedAt, at);
        expect(entry.payload, containsPair('createdByName', 'Test Farmer'));
        for (final value in payload(kind).entries) {
          expect(entry.payload[value.key], value.value);
        }
        await expectNoQueue();
      },
    );
    test(
      '${kind.name}: duplicate taps do not start another submission',
      () async {
        auth.gate = Completer<void>();
        final first = services.submitOnline(kind, payload(kind));
        await expectLater(
          services.submitOnline(kind, payload(kind)),
          throwsA(isA<SyncConflict>()),
        );
        auth.gate!.complete();
        await first;
        expect(auth.checks, 1);
        expect(remote.calls, 1);
      },
    );
    test(
      '${kind.name}: connection loss during submission never retries on reconnect',
      () async {
        remote.gate = Completer<void>();
        final saving = services.submitOnline(kind, payload(kind));
        final outcome = expectLater(saving, throwsA(isA<SyncConflict>()));
        while (remote.calls == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        session.networkLost();
        remote.gate!.complete();
        await outcome;
        expect(remote.accepted, isEmpty);
        await session.refresh();
        services.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(remote.calls, 1);
        await expectNoQueue();
      },
    );
  }
  for (final transition in [
    'logout',
    'account change',
    'access loss',
    'dispose form',
    'disconnect',
  ]) {
    test('$transition during the server check cannot upload', () async {
      auth.gate = Completer<void>();
      var formCurrent = true;
      final saving = services.submitOnline(
        OperationKind.ulang,
        payload(OperationKind.ulang),
        isCurrent: () => formCurrent,
      );
      final outcome = expectLater(saving, throwsA(isA<SyncConflict>()));
      if (transition == 'logout' || transition == 'account change') {
        await session.logout();
        if (transition == 'account change') {
          auth.uid = 'farmer-b';
          await session.acceptLogin('farmer-b', {
            'role': 'user',
            'status': 'active',
          }, emailVerified: true);
        }
      } else if (transition == 'access loss') {
        await session.block('Suspended');
      } else if (transition == 'dispose form') {
        formCurrent = false;
      } else {
        auth.connected = false;
        session.networkLost();
      }
      auth.gate!.complete();
      await outcome;
      expect(remote.calls, 0);
    });
  }
  test(
    'write rejection releases the save guard without automatic retry',
    () async {
      remote.failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await expectLater(
        services.submitOnline(
          OperationKind.plant,
          payload(OperationKind.plant),
        ),
        throwsA(isA<FirebaseException>()),
      );
      await session.refresh();
      expect(remote.calls, 1);
      expect(remote.accepted, isEmpty);
      remote.failure = null;
      await services.submitOnline(
        OperationKind.plant,
        payload(OperationKind.plant),
      );
      expect(remote.calls, 2);
    },
  );
  test(
    'lost server acknowledgment never creates a queue or automatically resubmits',
    () async {
      remote.loseAcknowledgment = true;
      await expectLater(
        services.submitOnline(
          OperationKind.ulang,
          payload(OperationKind.ulang),
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(remote.accepted, hasLength(1));
      await session.refresh();
      services.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remote.calls, 1);
      await expectNoQueue();
    },
  );

  for (final kind in [OperationKind.ulang, OperationKind.mortality]) {
    test(
      '${kind.name}: summary failure reports a confirmed record and never resubmits',
      () async {
        remote.recalculationFailure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
        final warning = await services.submitOnline(kind, payload(kind));
        expect(warning, contains('record was saved'));
        expect(remote.accepted, hasLength(1));
        expect(remote.recalculations, 1);
        await session.refresh();
        services.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(remote.calls, 1);
        expect(remote.recalculations, 1);
        await expectNoQueue();
      },
    );
  }
}
