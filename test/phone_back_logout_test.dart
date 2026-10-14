import 'dart:async';

import 'package:demo_1_langto/logout_confirmation_dialog.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/offline_widgets.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/phone_back_logout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/offline_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineServices services;
  late SessionController session;
  late _LogoutBackend backend;
  late PhoneBackLogoutCoordinator coordinator;
  late GlobalKey<ScaffoldMessengerState> messengerKey;
  late GlobalKey<ScaffoldState> scaffoldKey;
  late Completer<void> logoutFinished;
  final navigatorKey = NotificationService.navigatorKey;
  final platformCalls = <MethodCall>[];
  final dialog = find.byType(LogoutConfirmationDialog);
  var logoutCalls = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    backend = _LogoutBackend();
    session = SessionController(store, backend);
    services = OfflineServices(store, session, TestSyncBackend());
    OfflineServices.current = services;
    await session.acceptLogin('farmer-a', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
    messengerKey = GlobalKey<ScaffoldMessengerState>();
    scaffoldKey = GlobalKey<ScaffoldState>();
    logoutCalls = 0;
    logoutFinished = Completer<void>();
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    coordinator = PhoneBackLogoutCoordinator(
      navigatorKey: navigatorKey,
      messengerKey: messengerKey,
      session: session,
      logout: () async {
        logoutCalls++;
        try {
          await services.logout();
        } finally {
          logoutFinished.complete();
        }
      },
    );
  });
  tearDown(() async {
    coordinator.dispose();
    await services.dispose();
    await backend.events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showApp(WidgetTester tester, {Widget? home}) async {
    await tester.pumpWidget(
      _CoordinatorHost(
        coordinator: coordinator,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          navigatorObservers: [coordinator],
          onNavigationNotification: coordinator.onNavigationNotification,
          theme: ThemeData(
            platform: TargetPlatform.android,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
              },
            ),
          ),
          builder: (context, child) => SessionNavigationGuard(child: child!),
          home:
              home ??
              Scaffold(
                key: scaffoldKey,
                drawer: const Drawer(child: Text('Open menu')),
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const Text('Dashboard data'),
                      const TextField(),
                      TextButton(
                        key: const Key('profile_logout'),
                        onPressed: () => coordinator.requestLogout(context),
                        child: const Text('Profile Log Out'),
                      ),
                    ],
                  ),
                ),
              ),
          routes: {
            '/session': (_) => const Scaffold(body: Text('Signed out')),
            '/login': (_) => const Scaffold(body: Text('Signed out')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> finishLogout(WidgetTester tester) async {
    final elapsed = Stopwatch()..start();
    while (!logoutFinished.isCompleted &&
        elapsed.elapsed < const Duration(seconds: 5)) {
      // SQLite uses real I/O; pump its Future continuations between I/O waits.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(logoutFinished.isCompleted, isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    await back(tester);
    await back(tester);
    expect(dialog, findsOneWidget);
  }

  Future<void> pushPage(WidgetTester tester, String name) async {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(name)),
            body: Text('$name details'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Object?> gesture(
    WidgetTester tester,
    String method, [
    Map<String, Object?>? arguments,
  ]) => tester.runAsync<Object?>(() async {
    final reply = Completer<ByteData?>();
    final channel = SystemChannels.backGesture;
    tester.binding.channelBuffers.push(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      reply.complete,
    );
    return channel.codec.decodeEnvelope((await reply.future)!);
  });

  Future<void> startGesture(WidgetTester tester) async {
    expect(
      await gesture(tester, 'startBackGesture', {
        'touchOffset': <double>[0, 100],
        'progress': 0.0,
        'swipeEdge': 0,
      }),
      isTrue,
    );
  }

  testWidgets('root Back is consumed and the second press prompts', (
    tester,
  ) async {
    await showApp(tester);
    await back(tester);
    expect(dialog, findsNothing);
    expect(find.text('Press Back again to log out'), findsOneWidget);
    expect(
      platformCalls.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await back(tester);
    expect(dialog, findsOneWidget);
    expect(logoutCalls, 0);
    expect(session.canAccess, isTrue);
    expect(
      platformCalls
          .where((c) => c.method == 'SystemNavigator.setFrameworkHandlesBack')
          .last
          .arguments,
      isTrue,
    );
  });

  for (final page in ['Profile', 'Tasks', 'Logs', 'Ani']) {
    testWidgets('$page returns first; second Back prompts on Dashboard', (
      tester,
    ) async {
      await showApp(tester);
      await pushPage(tester, page);
      await back(tester);
      expect(find.text('$page details'), findsNothing);
      expect(find.text('Dashboard data'), findsOneWidget);
      expect(dialog, findsNothing);
      await back(tester);
      expect(dialog, findsOneWidget);
    });
  }

  testWidgets('first Back still runs a dashboard tab PopScope', (tester) async {
    await showApp(tester, home: const _TabHistoryPage());
    await back(tester);
    expect(find.text('Dashboard tab'), findsOneWidget);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('the pair expires after two seconds', (tester) async {
    await showApp(tester);
    await back(tester);
    await tester.pump(const Duration(milliseconds: 2001));
    await back(tester);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
  });

  for (final dismissal in ['No', 'Back', 'outside']) {
    testWidgets('$dismissal cancels without logout and resets the pair', (
      tester,
    ) async {
      await showApp(tester);
      await openConfirmation(tester);
      if (dismissal == 'No') {
        await tester.tap(find.byKey(const Key('logout_no_button')));
      } else if (dismissal == 'Back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(session.canAccess, isTrue);
      expect(logoutCalls, 0);
      await back(tester);
      expect(dialog, findsNothing);
    });
  }

  testWidgets('an existing dialog is dismissed without counting Back', (
    tester,
  ) async {
    await showApp(tester);
    unawaited(
      showDialog<void>(
        context: navigatorKey.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(title: Text('Record details')),
      ),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Record details'), findsNothing);
    await back(tester);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('an open drawer is dismissed before counting presses', (
    tester,
  ) async {
    await showApp(tester);
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await back(tester);
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    await back(tester);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('keyboard Back only hides the keyboard and resets the pair', (
    tester,
  ) async {
    await showApp(tester);
    await back(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.binding.handlePopRoute();
    expect(dialog, findsNothing);
    tester.view.resetViewInsets();
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await back(tester);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
    expect(find.text('draft'), findsOneWidget);
  });

  testWidgets('notification overlay dismissal does not prime logout', (
    tester,
  ) async {
    await showApp(tester);
    var open = true;
    final unregister = coordinator.registerOverlayDismissal(() {
      if (!open) return false;
      open = false;
      return true;
    });
    addTearDown(unregister);
    await back(tester);
    expect(open, isFalse);
    await back(tester);
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsOneWidget);
  });

  testWidgets('on-screen and programmatic navigation reset the window', (
    tester,
  ) async {
    await showApp(tester);
    await back(tester);
    await pushPage(tester, 'Profile');
    expect(dialog, findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    await back(tester);
    expect(dialog, findsNothing);
    coordinator.reset(); // Dashboard's explicit tab-navigation hook.
    await back(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('canceled gestures do not count; committed gestures count once', (
    tester,
  ) async {
    await showApp(tester);
    await startGesture(tester);
    await gesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    await startGesture(tester);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    await startGesture(tester);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(logoutCalls, 0);
  });

  testWidgets(
    'Profile logout is immediate and duplicate requests are ignored',
    (tester) async {
      await showApp(tester);
      await tester.tap(find.byKey(const Key('profile_logout')));
      unawaited(
        coordinator.requestLogout(navigatorKey.currentState!.overlay!.context),
      );
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(logoutCalls, 0);
    },
  );

  testWidgets(
    'confirmation logs out once and the guard removes protected routes',
    (tester) async {
      await showApp(tester);
      await pushPage(tester, 'Profile');
      unawaited(
        coordinator.requestLogout(navigatorKey.currentState!.overlay!.context),
      );
      await tester.pumpAndSettle();
      final yes = tester
          .widget<ElevatedButton>(find.byKey(const Key('logout_yes_button')))
          .onPressed!;
      yes();
      yes();
      await finishLogout(tester);
      expect(logoutCalls, 1);
      expect(backend.signOutCalls, 1);
      expect(session.canAccess, isFalse);
      expect(find.text('Profile details'), findsNothing);
      expect(find.text('Dashboard data'), findsNothing);
      expect(find.text('Signed out'), findsOneWidget);
      expect(
        await tester.runAsync(() => services.store.approval('farmer-a')),
        isNull,
      );
    },
  );

  testWidgets('offline logout uses the same existing service', (tester) async {
    session.networkLost();
    await showApp(tester);
    await openConfirmation(tester);
    await tester.tap(find.byKey(const Key('logout_yes_button')));
    await finishLogout(tester);
    expect(logoutCalls, 1);
    expect(session.canAccess, isFalse);
    expect(backend.uid, isNull);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('logout failure is shown without claiming success', (
    tester,
  ) async {
    backend.failure = StateError('Sign-out failed');
    await showApp(tester);
    await openConfirmation(tester);
    await tester.tap(find.byKey(const Key('logout_yes_button')));
    await finishLogout(tester);
    expect(logoutCalls, 1);
    expect(session.canAccess, isFalse);
    expect(
      find.text('Unable to finish logging out. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('backgrounding resets a pending pair', (tester) async {
    await showApp(tester);
    await back(tester);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await back(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('session revocation dismisses confirmation without logout', (
    tester,
  ) async {
    await showApp(tester);
    await openConfirmation(tester);
    await tester.runAsync(() => session.block('Access changed'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.text('Signed out'), findsOneWidget);
    expect(logoutCalls, 0);
  });

  testWidgets('signed-out Back keeps ordinary platform behavior', (
    tester,
  ) async {
    await showApp(tester);
    await tester.runAsync(() => session.logout());
    await tester.pumpAndSettle();
    platformCalls.clear();
    await back(tester);
    expect(dialog, findsNothing);
    expect(
      platformCalls.where((c) => c.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
  });
}

class _LogoutBackend extends TestSessionBackend {
  int signOutCalls = 0;
  Object? failure;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failure != null) throw failure!;
    await super.signOut();
  }
}

class _CoordinatorHost extends StatefulWidget {
  const _CoordinatorHost({required this.coordinator, required this.child});

  final PhoneBackLogoutCoordinator coordinator;
  final Widget child;

  @override
  State<_CoordinatorHost> createState() => _CoordinatorHostState();
}

class _CoordinatorHostState extends State<_CoordinatorHost> {
  @override
  void initState() {
    super.initState();
    widget.coordinator.start();
  }

  @override
  void dispose() {
    widget.coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PhoneBackLogoutScope(
    coordinator: widget.coordinator,
    child: widget.child,
  );
}

class _TabHistoryPage extends StatefulWidget {
  const _TabHistoryPage();

  @override
  State<_TabHistoryPage> createState() => _TabHistoryPageState();
}

class _TabHistoryPageState extends State<_TabHistoryPage> {
  bool _hasHistory = true;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_hasHistory,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) setState(() => _hasHistory = false);
    },
    child: Scaffold(body: Text(_hasHistory ? 'Logs tab' : 'Dashboard tab')),
  );
}
