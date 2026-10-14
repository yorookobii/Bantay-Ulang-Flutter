import 'dart:async';
import 'dart:io';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/offline_fakes.dart';

void main() {
  late OfflineStore store;
  late TestSessionBackend auth;
  late SessionController session;
  var now = DateTime.utc(2026, 10, 10);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    now = DateTime.utc(2026, 10, 10);
    store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    auth = TestSessionBackend();
    session = SessionController(store, auth, clock: () => now);
  });
  tearDown(() async {
    session.dispose();
    await auth.events.close();
    await store.close();
  });
  Future<void> grant() => session.acceptLogin('farmer-a', {
    'role': 'user',
    'status': 'active',
  }, emailVerified: true);

  test('startup removes leftover queues from a version 2 database', () async {
    final directory = await Directory.systemTemp.createTemp('bantay-v2-cleanup-');
    final dbPath = '${directory.path}/cleanup.db';
    var reopened = await OfflineStore.open(
      databasePath: dbPath,
      factory: databaseFactoryFfi,
    );
    try {
      await reopened.saveApproval(OfflineApproval(
        uid: 'farmer-a',
        checkedAt: now,
        profile: {'role': 'user', 'status': 'active'},
      ));
      await reopened.confirmCache('farmer-a', 'mortality_records', now);
      await reopened.db.execute('CREATE TABLE operations (id TEXT, kind TEXT)');
      await reopened.db.insert('operations', {
        'id': 'stale-mortality', 'kind': 'mortality',
      });
      await reopened.db.execute('CREATE TABLE recalculations (cycleId TEXT)');
      await reopened.db.insert('recalculations', {'cycleId': 'old-cycle'});
      await reopened.close();
      reopened = await OfflineStore.open(
        databasePath: dbPath,
        factory: databaseFactoryFfi,
      );
      final tables = await reopened.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(tables.map((row) => row['name']), isNot(contains('operations')));
      expect(tables.map((row) => row['name']), isNot(contains('recalculations')));
      expect(await reopened.approval('farmer-a'), isNotNull);
      expect(
        (await reopened.lastConfirmed('farmer-a', 'mortality_records'))!.toUtc(),
        now,
      );
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });

  test('logout signs out even when deleting the saved grant fails', () async {
    await grant();
    await store.db.execute(
      "CREATE TRIGGER fail_access_delete BEFORE DELETE ON approvals BEGIN SELECT RAISE(FAIL, 'disk failure'); END",
    );
    await session.logout();
    expect(auth.uid, isNull);
    expect(session.canAccess, isFalse);
  });

  test(
    'approval expires at seven days and rejects clock rollback or another UID',
    () async {
      await grant();
      final approval = (await store.approval('farmer-a'))!;
      expect(
        approval.permits(
          'farmer-a',
          now.add(const Duration(days: 6, hours: 23)),
        ),
        isTrue,
      );
      expect(
        approval.permits('farmer-a', now.add(const Duration(days: 7))),
        isFalse,
      );
      expect(approval.permits('farmer-b', now), isFalse);
      expect(
        approval.permits('farmer-a', now.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    },
  );
  test('a persisted Firebase user without a grant cannot resume', () async {
    await session.start();
    expect(session.canAccess, isFalse);
    expect(auth.checks, 0);
  });
  test(
    'approved session reopens offline and retains its original check time',
    () async {
      await grant();
      final checkedAt = session.approval!.checkedAt;
      auth.connected = false;
      await session.start();
      expect(session.canAccess, isTrue);
      expect(session.online, isFalse);
      expect(session.approval!.checkedAt, checkedAt);
    },
  );
  test('expired access renews only after an online check', () async {
    await grant();
    now = now.add(const Duration(days: 7));
    auth.connected = false;
    await session.refresh();
    expect(session.canAccess, isFalse);
    auth.connected = true;
    await session.refresh();
    expect(session.canAccess, isTrue);
  });
  test(
    'revoked approval clears the grant and never falls back to cache',
    () async {
      await grant();
      auth.approved = false;
      await session.refresh();
      expect(session.canAccess, isFalse);
      expect(await store.approval('farmer-a'), isNull);
    },
  );
  test('signup or resend cannot reuse an earlier approved session', () async {
    await grant();
    await session.beginAuthAttempt();
    await session.refresh();
    session.endAuthAttempt();
    expect(session.canAccess, isFalse);
    expect(await store.approval('farmer-a'), isNull);
  });
  test('logout during an online check cannot resurrect access', () async {
    await grant();
    auth.gate = Completer<void>();
    final check = session.refresh();
    await session.logout();
    auth.gate!.complete();
    await check;
    expect(session.canAccess, isFalse);
    expect(await store.approval('farmer-a'), isNull);
  });
  test('only verified active farm users can receive a grant', () async {
    await expectLater(
      session.acceptLogin('farmer-a', {
        'role': 'admin',
        'status': 'active',
      }, emailVerified: true),
      throwsA(isA<SyncConflict>()),
    );
    await expectLater(
      session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'pending',
      }, emailVerified: true),
      throwsA(isA<SyncConflict>()),
    );
    await expectLater(
      session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: false),
      throwsA(isA<SyncConflict>()),
    );
  });

  test(
    'version 1 upgrade discards every account queue and preserves viewing metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bantay-upgrade-',
      );
      final dbPath = '${directory.path}/upgrade.db';
      final old = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE operations (id TEXT PRIMARY KEY, uid TEXT, status TEXT)',
            );
            await db.execute(
              'CREATE INDEX operation_owner_status ON operations(uid,status)',
            );
            await db.execute(
              'CREATE TABLE recalculations (uid TEXT, cycleId TEXT, cycleStart INTEGER)',
            );
            await db.execute(
              'CREATE TABLE approvals (uid TEXT PRIMARY KEY, checkedAt INTEGER NOT NULL, profile TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE cache_stamps (uid TEXT, source TEXT, confirmedAt INTEGER, PRIMARY KEY(uid,source))',
            );
          },
        ),
      );
      for (final owner in ['farmer-a', 'farmer-b']) {
        for (final status in [
          'pending',
          'syncing',
          'synced',
          'needsAttention',
        ]) {
          await old.insert('operations', {
            'id': '$owner-$status',
            'uid': owner,
            'status': status,
          });
        }
        await old.insert('recalculations', {
          'uid': owner,
          'cycleId': 'cycle',
          'cycleStart': 1,
        });
        await old.insert(
          'approvals',
          OfflineApproval(
            uid: owner,
            checkedAt: now,
            profile: {'role': 'user', 'status': 'active'},
          ).toRow(),
        );
        await old.insert('cache_stamps', {
          'uid': owner,
          'source': 'logs',
          'confirmedAt': now.millisecondsSinceEpoch,
        });
      }
      await old.close();
      var upgraded = await OfflineStore.open(
        databasePath: dbPath,
        factory: databaseFactoryFfi,
      );
      try {
        expect(await upgraded.db.getVersion(), 2);
        final tables = await upgraded.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        expect(tables.map((row) => row['name']), isNot(contains('operations')));
        expect(
          tables.map((row) => row['name']),
          isNot(contains('recalculations')),
        );
        for (final owner in ['farmer-a', 'farmer-b']) {
          expect((await upgraded.approval(owner))!.permits(owner, now), isTrue);
          expect(
            (await upgraded.lastConfirmed(
              owner,
              'logs',
            ))!.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          );
        }
        await upgraded.close();
        upgraded = await OfflineStore.open(
          databasePath: dbPath,
          factory: databaseFactoryFfi,
        );
        expect(await upgraded.approval('farmer-a'), isNotNull);
        expect(await upgraded.lastConfirmed('farmer-b', 'logs'), isNotNull);
      } finally {
        await upgraded.close();
        await databaseFactoryFfi.deleteDatabase(dbPath);
        await directory.delete();
      }
    },
  );

  test('fresh databases contain only offline viewing metadata', () async {
    final tables = await store.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(['approvals', 'cache_stamps']),
    );
    expect(tables.map((row) => row['name']), isNot(contains('operations')));
    expect(tables.map((row) => row['name']), isNot(contains('recalculations')));
  });
}
