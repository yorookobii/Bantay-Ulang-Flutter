import 'dart:async';
import 'package:demo_1_langto/offline/local_record_cleanup.dart';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const completedKey = 'legacy_firestore_records_cleared_v1';
  late OfflineStore store;
  late SharedPreferences prefs;
  final now = DateTime.utc(2026, 10, 14);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    for (final owner in ['farmer-a', 'farmer-b']) {
      await store.saveApproval(
        OfflineApproval(
          uid: owner,
          checkedAt: now,
          profile: {'role': 'user', 'status': 'active'},
        ),
      );
      await store.confirmCache(owner, 'mortality_records', now);
      await store.confirmCache(owner, 'logs', now);
    }
  });
  tearDown(() => store.close());

  test(
    'cleanup waits for Firestore and retains approvals for every account',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final clearing = clearLegacyFirestoreRecords(
        store: store,
        preferences: prefs,
        clearPersistence: () {
          calls++;
          return gate.future;
        },
      );
      expect(calls, 1);
      expect(prefs.getBool(completedKey), isNull);
      expect(
        await store.lastConfirmed('farmer-a', 'mortality_records'),
        isNotNull,
      );
      gate.complete();
      await clearing;
      expect(prefs.getBool(completedKey), isTrue);
      for (final owner in ['farmer-a', 'farmer-b']) {
        expect(await store.lastConfirmed(owner, 'mortality_records'), isNull);
        expect(await store.lastConfirmed(owner, 'logs'), isNull);
        expect((await store.approval(owner))!.permits(owner, now), isTrue);
      }
    },
  );

  test('later startups retain newly downloaded offline data', () async {
    var calls = 0;
    Future<void> clear() async {
      calls++;
    }

    await clearLegacyFirestoreRecords(
      store: store,
      preferences: prefs,
      clearPersistence: clear,
    );
    await store.confirmCache('farmer-a', 'mortality_records', now);
    await clearLegacyFirestoreRecords(
      store: store,
      preferences: prefs,
      clearPersistence: clear,
    );
    expect(calls, 1);
    expect(
      await store.lastConfirmed('farmer-a', 'mortality_records'),
      isNotNull,
    );
  });

  test(
    'a failed Firestore reset blocks startup and remains retryable',
    () async {
      await expectLater(
        clearLegacyFirestoreRecords(
          store: store,
          preferences: prefs,
          clearPersistence: () async {
            throw StateError('Firestore is running');
          },
        ),
        throwsA(isA<LocalRecordCleanupFailure>()),
      );
      expect(prefs.getBool(completedKey), isNull);
      expect(
        await store.lastConfirmed('farmer-a', 'mortality_records'),
        isNotNull,
      );
      await clearLegacyFirestoreRecords(
        store: store,
        preferences: prefs,
        clearPersistence: () async {},
      );
      expect(prefs.getBool(completedKey), isTrue);
    },
  );

  test('metadata cleanup failure never marks the reset complete', () async {
    await store.db.execute(
      "CREATE TRIGGER fail_cache_delete BEFORE DELETE ON cache_stamps BEGIN SELECT RAISE(FAIL, 'disk failure'); END",
    );
    await expectLater(
      clearLegacyFirestoreRecords(
        store: store,
        preferences: prefs,
        clearPersistence: () async {},
      ),
      throwsA(isA<LocalRecordCleanupFailure>()),
    );
    expect(prefs.getBool(completedKey), isNull);
    expect(await store.approval('farmer-a'), isNotNull);
  });
}
