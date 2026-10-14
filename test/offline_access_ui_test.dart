import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/offline_widgets.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
    GoogleFonts.config.allowRuntimeFetching = false;
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
    NotificationService.instance.onNavigateToTasks = null;
    NotificationService.instance.canNavigateToTasks = null;
    NotificationService.instance.consumePendingNavigationToTasks();
  });

  test('login and reconnect never submit records automatically', () async {
    await session.logout();
    auth.uid = 'farmer-b';
    await session.acceptLogin('farmer-b', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
    session.networkLost();
    await session.refresh();
    services.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(remote.calls, 0);
  });

  test(
    'late cache response and denial cannot affect a different login',
    () async {
      final old = CacheStatus('growth_indicators');
      await old.loaded;
      final epoch = session.accessEpoch;
      await session.logout();
      auth.uid = 'farmer-b';
      await session.acceptLogin('farmer-b', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: true);
      old.observe(const _ServerMetadata(), hasData: true);
      await services.reportReadError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        'farmer-a',
        epoch,
      );
      expect(old.isCurrent, isFalse);
      expect(old.hasData, isFalse);
      expect(
        await store.lastConfirmed('farmer-b', 'growth_indicators'),
        isNull,
      );
      expect(session.canAccess, isTrue);
      old.dispose();
    },
  );

  test('permission rejection clears access', () async {
    await services.reportReadError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      auth.uid,
      session.accessEpoch,
    );
    expect(session.canAccess, isFalse);
    expect(await store.approval('farmer-a'), isNull);
  });

  test(
    'notification callback cannot bypass expired or revoked access',
    () async {
      final notifications = NotificationService.instance;
      notifications.canNavigateToTasks = () => session.canAccess;
      var navigations = 0;
      notifications.onNavigateToTasks = () => navigations++;
      notifications.navigateToTasks();
      expect(navigations, 1);
      await session.block('Account suspended');
      notifications.navigateToTasks();
      expect(navigations, 1);
      expect(notifications.consumePendingNavigationToTasks(), isTrue);
    },
  );

  test('missing cache is distinct from a confirmed empty result', () async {
    final status = CacheStatus('logs');
    try {
      await status.loaded;
      expect(status.lastConfirmed, isNull);
      expect(status.canUse(const _CacheMetadata()), isFalse);
      status.observe(const _ServerMetadata(), hasData: false);
      expect(status.fromCache, isFalse);
      expect(status.hasData, isFalse);
      expect(status.lastConfirmed, isNotNull);
      final confirmed = status.lastConfirmed;
      session.networkLost();
      expect(status.fromCache, isTrue);
      expect(status.hasData, isFalse);
      expect(status.lastConfirmed, confirmed);
      expect(status.canUse(const _CacheMetadata()), isTrue);
      // Let the existing asynchronous timestamp write finish before teardown.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        (await store.lastConfirmed('farmer-a', 'logs'))!.millisecondsSinceEpoch,
        confirmed!.millisecondsSinceEpoch,
      );
    } finally {
      status.dispose();
    }
  });

  Widget noticeApp({GlobalKey<NavigatorState>? navigatorKey, Widget? home}) =>
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => SessionOfflineNotice(child: child!),
        home: home ?? const Scaffold(body: Text('Dashboard')),
      );
  final offlineNotice = find.text('This session is in offline mode.');

  testWidgets('offline startup notice disappears after exactly four seconds', (
    tester,
  ) async {
    session.networkLost();
    await tester.pumpWidget(noticeApp());
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(offlineNotice, findsNothing);
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cached snapshots alone do not show an offline notice', (
    tester,
  ) async {
    final status = CacheStatus('logs');
    await tester.runAsync(() => status.loaded);
    await tester.pumpWidget(noticeApp());
    status.observe(const _CacheMetadata(), hasData: false);
    await tester.pump();
    expect(status.fromCache, isTrue);
    expect(session.online, isTrue);
    expect(offlineNotice, findsNothing);
    status.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a delayed first notice frame still gets four display seconds', (
    tester,
  ) async {
    await tester.pumpWidget(noticeApp());
    session.networkLost();
    await tester.pump(const Duration(seconds: 10));
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notice waits until the offline session is ready and allowed', (
    tester,
  ) async {
    session.ready = false;
    session.networkLost();
    await tester.pumpWidget(noticeApp());
    expect(offlineNotice, findsNothing);
    session.ready = true;
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsOneWidget);
    await tester.runAsync(() => session.logout());
    await tester.pump();
    expect(offlineNotice, findsNothing);
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only a new offline period repeats the notice', (tester) async {
    await tester.pumpWidget(noticeApp());
    expect(offlineNotice, findsNothing);
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    session.networkLost();
    await tester.pump(const Duration(seconds: 1));
    expect(offlineNotice, findsNothing);
    await tester.runAsync(
      () => session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: true),
    );
    await tester.pump();
    expect(offlineNotice, findsNothing);
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsOneWidget);
    await tester.runAsync(
      () => session.acceptLogin('farmer-a', {
        'role': 'user',
        'status': 'active',
      }, emailVerified: true),
    );
    await tester.pump();
    expect(offlineNotice, findsNothing);
    expect(find.textContaining('back online'), findsNothing);
    // The old timer must not dismiss a notice from a later offline period.
    session.networkLost();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Profile navigation shares the notice and does not restart it', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(noticeApp(navigatorKey: key));
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Profile')),
      ),
    );
    await tester.pumpAndSettle();
    session.networkLost();
    await tester.pump();
    expect(find.text('Profile'), findsOneWidget);
    expect(offlineNotice, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    key.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Dashboard'), findsOneWidget);
    expect(offlineNotice, findsNothing);
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Profile')),
      ),
    );
    await tester.pumpAndSettle();
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notice allows taps and leaves save notifications visible', (
    tester,
  ) async {
    final buttonKey = GlobalKey();
    var taps = 0;
    session.networkLost();
    await tester.pumpWidget(
      noticeApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: SizedBox(
                  height: 64,
                  child: TextButton(
                    key: buttonKey,
                    onPressed: () => taps++,
                    child: const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(offlineNotice, findsOneWidget);
    final noticePosition = tester.getCenter(offlineNotice);
    expect(
      tester.getRect(find.byKey(buttonKey)).contains(noticePosition),
      isTrue,
    );
    await tester.tapAt(noticePosition);
    expect(taps, 1);
    ScaffoldMessenger.of(buttonKey.currentContext!).showSnackBar(
      const SnackBar(content: Text('Internet connection is required.')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Internet connection is required.'), findsOneWidget);
    expect(offlineNotice, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('access revocation dismisses the notice and cancels its timer', (
    tester,
  ) async {
    session.networkLost();
    await tester.pumpWidget(noticeApp());
    expect(offlineNotice, findsOneWidget);
    await tester.runAsync(() => session.block('Account suspended'));
    await tester.pump();
    expect(offlineNotice, findsNothing);
    await tester.pump(const Duration(seconds: 4));
    session.networkLost();
    await tester.pump();
    expect(offlineNotice, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('revocation removes protected routes including profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        builder: (context, child) => SessionNavigationGuard(child: child!),
        home: const Scaffold(body: Text('Dashboard data')),
        routes: {
          '/session': (_) => const Scaffold(body: Text('Access blocked')),
        },
      ),
    );
    NotificationService.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Private profile')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => session.block('Account suspended'));
    await tester.pumpAndSettle();
    expect(find.text('Private profile'), findsNothing);
    expect(find.text('Dashboard data'), findsNothing);
    expect(find.text('Access blocked'), findsOneWidget);
    expect(NotificationService.navigatorKey.currentState!.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'sign-in replaces the stack without constructing two dashboards',
    (tester) async {
      await tester.runAsync(() => session.logout());
      final key = GlobalKey<NavigatorState>();
      var dashboards = 0;
      Widget entry() => SessionEntry(
        dashboardBuilder: (_) => _DashboardProbe(onOpen: () => dashboards++),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: entry(),
          routes: {'/dashboard': (_) => entry()},
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Signing in')),
        ),
      );
      await tester.pumpAndSettle();
      auth.uid = 'farmer-a';
      await tester.runAsync(
        () => session.acceptLogin('farmer-a', {
          'role': 'user',
          'status': 'active',
        }, emailVerified: true),
      );
      await tester.pump();
      expect(dashboards, 0);
      key.currentState!.pushNamedAndRemoveUntil('/dashboard', (_) => false);
      await tester.pumpAndSettle();
      expect(dashboards, 1);
      expect(key.currentState!.canPop(), isFalse);
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Profile')),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(dashboards, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DashboardProbe extends StatefulWidget {
  const _DashboardProbe({required this.onOpen});
  final VoidCallback onOpen;
  @override
  State<_DashboardProbe> createState() => _DashboardProbeState();
}

class _DashboardProbeState extends State<_DashboardProbe> {
  @override
  void initState() {
    super.initState();
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Dashboard'));
}

class _ServerMetadata implements SnapshotMetadata {
  const _ServerMetadata();
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

class _CacheMetadata implements SnapshotMetadata {
  const _CacheMetadata();
  @override
  bool get isFromCache => true;
  @override
  bool get hasPendingWrites => false;
}
