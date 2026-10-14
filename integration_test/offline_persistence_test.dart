import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/logs.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/offline_widgets.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/offline/sync_backend.dart';
import 'package:flutter/material.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../test/support/offline_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android SQLite discards legacy queues and preserves offline viewing on upgrade',
    (tester) async {
      final databasePath = path.join(
        await getDatabasesPath(),
        'offline_integration_only.db',
      );
      await deleteDatabase(databasePath);
      final legacy = await openDatabase(
        databasePath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE operations (id TEXT PRIMARY KEY, uid TEXT, status TEXT)',
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
      );
      for (final owner in ['farmer-a', 'farmer-b']) {
        await legacy.insert('operations', {
          'id': '$owner-pending',
          'uid': owner,
          'status': 'pending',
        });
        await legacy.insert('recalculations', {
          'uid': owner,
          'cycleId': 'cycle',
          'cycleStart': 1,
        });
      }
      var store = OfflineStore(legacy);
      final auth = TestSessionBackend();
      var session = SessionController(store, auth);
      await session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: true);
      final confirmed = DateTime.now();
      await store.confirmCache('farmer-a', 'logs', confirmed);
      session.dispose();
      await store.close();
      auth.connected = false;
      store = await OfflineStore.open(databasePath: databasePath);
      session = SessionController(store, auth);
      await session.start();
      final remote = TestSyncBackend();
      final services = OfflineServices(store, session, remote);
      OfflineServices.current = services;
      expect(session.canAccess, isTrue);
      expect(session.online, isFalse);
      expect(
        (await store.lastConfirmed('farmer-a', 'logs'))!.millisecondsSinceEpoch,
        confirmed.millisecondsSinceEpoch,
      );
      for (final kind in OperationKind.values) {
        await expectLater(
          services.submitOnline(kind, {}),
          throwsA(isA<SyncConflict>()),
        );
      }
      expect(await store.db.getVersion(), 2);
      final tables = await store.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(tables.map((r) => r['name']), isNot(contains('operations')));
      expect(tables.map((r) => r['name']), isNot(contains('recalculations')));
      auth.connected = true;
      await session.refresh();
      expect(remote.calls, 0);
      await services.dispose();
      await auth.events.close();
      await deleteDatabase(databasePath);
    },
  );

  testWidgets(
    'Android forms block offline logs and save online in the same approved session',
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final databasePath = path.join(
        await getDatabasesPath(),
        'online_logs_integration_only.db',
      );
      await deleteDatabase(databasePath);
      final store = await OfflineStore.open(databasePath: databasePath);
      final auth = TestSessionBackend();
      final session = SessionController(store, auth);
      await session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: true);
      final firestore = FakeFirebaseFirestore();
      final services = OfflineServices(
        store,
        session,
        FirestoreSyncBackend(firestore, () => session.uid),
      );
      OfflineServices.current = services;
      await firestore.collection('users').doc('farmer-a').set({
        'role': 'user',
        'status': 'active',
        'fullName': 'Test Farmer',
        'email': 'test@example.com',
      });
      auth.connected = false;
      session.networkLost();
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.binding.setSurfaceSize(null);
        await services.dispose();
        await auth.events.close();
        await deleteDatabase(databasePath);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SessionEntry(
            dashboardBuilder: (_) => LogsPage(firestore: firestore),
          ),
          builder: _offlineNoticeBuilder,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '5');
      await tester.enterText(find.byType(TextField).at(1), '12');
      final ulangSave = find.text('I-save ang Ulang Log');
      await tester.ensureVisible(ulangSave);
      await tester.tap(ulangSave);
      await tester.pumpAndSettle();
      expect(find.text('Internet connection is required.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '5',
      );
      expect(session.canAccess, isTrue);
      expect((await firestore.collection('logs').get()).docs, isEmpty);

      await tester.tap(find.text('Tala ng Tanim'));
      await tester.pumpAndSettle();
      for (final item in ['Mint', 'Malusog (Healthy)', 'Seedling (Punla)']) {
        final index = item == 'Mint'
            ? 0
            : item == 'Malusog (Healthy)'
            ? 1
            : 2;
        final dropdown = find.byType(DropdownButtonFormField<String>).at(index);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, '15');
      final plantSave = find.text('I-save ang Plant Log');
      await tester.ensureVisible(plantSave);
      await tester.tap(plantSave);
      await tester.pumpAndSettle();
      expect(find.text('Internet connection is required.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '15',
      );
      expect((await firestore.collection('logs').get()).docs, isEmpty);

      auth.connected = true;
      expect(await session.refresh(), isTrue);
      await tester.pumpAndSettle();
      expect(session.uid, 'farmer-a');
      await tester.ensureVisible(plantSave);
      await tester.tap(plantSave);
      await tester.pumpAndSettle();
      expect(
        find.text('Matagumpay na na-save ang tala ng Tanim.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tala ng Ulang'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '5',
      );
      await tester.ensureVisible(ulangSave);
      await tester.tap(ulangSave);
      await tester.pumpAndSettle();
      expect(
        find.text('Matagumpay na na-save ang tala ng Ulang.'),
        findsOneWidget,
      );
      expect((await firestore.collection('logs').get()).docs, hasLength(2));
      expect(
        (await firestore.collection('ulang_growth_records').get()).docs,
        hasLength(1),
      );
      expect(session.uid, 'farmer-a');
      expect(session.canAccess, isTrue);
    },
  );
}

Widget _offlineNoticeBuilder(BuildContext context, Widget? child) =>
    SessionOfflineNotice(child: child!);
