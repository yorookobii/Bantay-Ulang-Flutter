import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/tasks.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/offline/sync_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/offline_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineServices services;
  late TestSessionBackend auth;
  late _TaskFirestore db;
  setUpAll(() async {
    sqfliteFfiInit();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            return null;
          },
        );
    await NotificationService.instance.initialize();
  });
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    auth = TestSessionBackend();
    final session = SessionController(store, auth);
    db = _TaskFirestore();
    services = OfflineServices(
      store,
      session,
      FirestoreSyncBackend(db, () => session.uid),
    );
    OfflineServices.current = services;
    await session.acceptLogin('farmer-a', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
    await db.doc('users/farmer-a').set({'role': 'user', 'status': 'active'});
    await db.doc('tasks/task').set({
      'assignedTo': 'farmer-a',
      'status': 'pending',
      'title': 'Check water',
      'description': 'Test task',
      'createdAt': Timestamp.now(),
    });
  });
  tearDown(() async {
    await services.dispose();
    await auth.events.close();
  });
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => services.session.logout());
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: TasksPage(firestore: db)));
    await settle(tester);
  }

  Future<void> complete(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Tapusin'));
    await tester.tap(find.text('Tapusin'));
    await settle(tester);
  }

  testWidgets(
    'offline task completion keeps task actionable and creates no queue',
    (tester) async {
      services.session.networkLost();
      await open(tester);
      await complete(tester);
      expect(find.text('Internet connection is required.'), findsOneWidget);
      expect(find.text('Tapusin'), findsOneWidget);
      expect(find.textContaining('Saved on this device'), findsNothing);
      expect(find.text('Pending sync'), findsNothing);
      expect(db.transactionCalls, 0);
      await tester.runAsync(() async {
        expect((await db.doc('tasks/task').get()).data()!['status'], 'pending');
      });
      await close(tester);
    },
  );
  testWidgets(
    'task completion waits for transaction and ignores repeated taps',
    (tester) async {
      db.gate = Completer<void>();
      await open(tester);
      await complete(tester);
      expect(find.text('Saving...'), findsOneWidget);
      expect(find.textContaining('Matagumpay'), findsNothing);
      await tester.tap(find.text('Saving...'));
      await tester.pump();
      expect(db.transactionCalls, 1);
      await tester.runAsync(() async {
        expect((await db.doc('tasks/task').get()).data()!['status'], 'pending');
      });
      db.gate!.complete();
      await settle(tester);
      expect(find.text('Matagumpay na natapos ang gawain.'), findsOneWidget);
      expect(find.text('Saving...'), findsNothing);
      await tester.runAsync(() async {
        expect((await db.doc('tasks/task').get()).data()!['status'], 'done');
      });
      await close(tester);
    },
  );
  for (final transition in [
    'disconnect',
    'logout',
    'account change',
    'reassign',
    'delete',
    'deny',
  ]) {
    testWidgets(
      '$transition during completion cannot silently mark the task done',
      (tester) async {
        db.gate = Completer<void>();
        await open(tester);
        await complete(tester);
        await tester.runAsync(() async {
          if (transition == 'disconnect') {
            services.session.networkLost();
          } else if (transition == 'logout' || transition == 'account change') {
            await services.session.logout();
            if (transition == 'account change') {
              auth.uid = 'farmer-b';
              await services.session.acceptLogin('farmer-b', {
                'role': 'user',
                'status': 'active',
              }, emailVerified: true);
            }
          } else if (transition == 'reassign') {
            await db.doc('tasks/task').update({'assignedTo': 'farmer-b'});
          } else if (transition == 'delete') {
            await db.doc('tasks/task').delete();
          } else {
            db.failure = FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            );
          }
        });
        db.gate!.complete();
        await settle(tester);
        expect(find.textContaining('Matagumpay'), findsNothing);
        expect(find.text('Saving...'), findsNothing);
        await tester.runAsync(() async {
          final task = await db.doc('tasks/task').get();
          if (transition == 'delete') {
            expect(task.exists, isFalse);
          } else {
            expect(task.data()!['status'], 'pending');
          }
        });
        if (transition == 'disconnect') {
          await tester.runAsync(() => services.session.refresh());
          await settle(tester);
          expect(db.transactionCalls, 1);
        }
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }
}

class _TaskFirestore extends FakeFirebaseFirestore {
  Completer<void>? gate;
  Object? failure;
  int transactionCalls = 0;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCalls++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}
