import 'dart:io';
import 'dart:ui' as ui;
import 'package:demo_1_langto/login.dart';
import 'package:demo_1_langto/main.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/offline_widgets.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/offline_fakes.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final splash = find.byType(StartupSplashPage);
  late GlobalKey<NavigatorState> navigator;
  late _Routes routes;
  OfflineServices? services;
  TestSessionBackend? backend;

  void background() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void resume() {
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    // Optional preview font avoids Flutter tests' Ahem placeholder glyphs.
    final previewFont = Platform.environment['BANTAY_PREVIEW_ROBOTO'];
    if (previewFont != null) {
      await (FontLoader('Roboto')..addFont(
            File(previewFont).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() {
    resume();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    OfflineServices.current = null;
    navigator = GlobalKey<NavigatorState>();
    routes = _Routes();
  });
  tearDown(() async {
    resume();
    await services?.dispose();
    await backend?.events.close();
    services = null;
    backend = null;
    OfflineServices.current = null;
  });

  Widget app({WidgetBuilder? destination, double scale = 1}) => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [routes],
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: StartupSplashPage(sessionEntryBuilder: destination),
  );

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  Future<SessionController> savedSession(
    WidgetTester tester, {
    bool offline = false,
  }) async => (await tester.runAsync(() async {
    final store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    backend = TestSessionBackend();
    final previousSession = SessionController(store, backend!);
    await previousSession.acceptLogin('farmer-a', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
    previousSession.dispose();
    backend!.connected = !offline;
    final session = SessionController(store, backend!);
    services = OfflineServices(store, session, TestSyncBackend());
    OfflineServices.current = services;
    await session.start();
    return session;
  }))!;

  Widget entry(BuildContext context) => SessionEntry(
    dashboardBuilder: (_) => const Scaffold(body: Text('Approved dashboard')),
  );

  testWidgets('2.5 seconds precedes exactly one 350 ms fade to real login', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(splash, findsOneWidget);
    expect(find.text('Keep track of your ulang and plants'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
    expect(find.byType(SignupPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 2499));
    expect(routes.replaced, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(routes.replaced, hasLength(1));
    expect(routes.replaced.single.settings.name, '/session');
    final route = routes.replaced.single as PageRoute;
    expect(route.transitionDuration, const Duration(milliseconds: 350));
    await tester.pump();
    expect(route.animation!.value, 0);
    expect(navigator.currentState!.canPop(), isFalse);
    await tester.pump(const Duration(milliseconds: 175));
    expect(route.animation!.value, closeTo(0.5, 0.01));
    expect(await navigator.currentState!.maybePop(), isFalse);
    await tester.pump(const Duration(milliseconds: 175));
    expect(route.animation!.value, closeTo(1, 0.001));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(splash, findsNothing);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(await navigator.currentState!.maybePop(), isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(routes.replaced, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rebuilds do not restart the splash clock', (tester) async {
    await tester.pumpWidget(app(scale: 1));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpWidget(app(scale: 1.2));
    await tester.pump(const Duration(milliseconds: 1499));
    expect(routes.replaced, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(routes.replaced, hasLength(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing the splash cancels its pending navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(routes.replaced, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background defers navigation and resume never repeats a completed splash',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 1000));
      background();
      await tester.pump(const Duration(seconds: 3));
      expect(routes.replaced, isEmpty);
      resume();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(SignupPage), findsOneWidget);
      expect(routes.replaced, hasLength(1));
      background();
      await tester.pump(const Duration(seconds: 3));
      resume();
      await tester.pump();
      expect(splash, findsNothing);
      expect(routes.replaced, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an open dialog is not replaced by the splash timer', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final dialog = showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Temporary dialog')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    expect(routes.replaced, isEmpty);
    expect(find.text('Temporary dialog'), findsOneWidget);
    navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(find.byType(SignupPage), findsOneWidget);
    expect(routes.replaced, hasLength(1));
    expect(routes.old.single, isNot(isA<PopupRoute>()));
    expect(splash, findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final offline in [false, true]) {
    testWidgets(
      'approved ${offline ? 'offline' : 'online'} session is retained after splash',
      (tester) async {
        final session = await savedSession(tester, offline: offline);
        await tester.pumpWidget(app(destination: entry));
        expect(find.text('Approved dashboard'), findsNothing);
        await finish(tester);
        expect(find.text('Approved dashboard'), findsOneWidget);
        expect(find.byType(SignupPage), findsNothing);
        expect(splash, findsNothing);
        expect(session.canAccess, isTrue);
        expect(session.online, !offline);
        // Startup restores/checks once; the splash does not add another check.
        expect(backend!.checks, 1);
        expect(navigator.currentState!.canPop(), isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'a signed-out initialized session opens login without a second splash',
    (tester) async {
      final session = await savedSession(tester);
      await tester.runAsync(session.logout);
      await tester.pumpWidget(app(destination: entry));
      await finish(tester);
      expect(find.byType(SignupPage), findsOneWidget);
      expect(find.text('Approved dashboard'), findsNothing);
      expect(splash, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('session validation loading and access errors remain intact', (
    tester,
  ) async {
    final session = await savedSession(tester);
    session.ready = false;
    await tester.pumpWidget(app(destination: entry));
    await finish(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Approved dashboard'), findsNothing);
    await tester.runAsync(() => session.block('Account access was rejected'));
    session.ready = true;
    session.networkLost();
    await tester.pumpAndSettle();
    expect(find.text('Account access was rejected'), findsOneWidget);
    expect(find.text('Check connection'), findsOneWidget);
    expect(find.text('Approved dashboard'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('logout after splash clears the dashboard and opens real login', (
    tester,
  ) async {
    final session = await savedSession(tester);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        home: StartupSplashPage(sessionEntryBuilder: entry),
        builder: (_, child) => SessionNavigationGuard(child: child!),
        routes: {'/session': entry, '/login': (_) => const SignupPage()},
      ),
    );
    await finish(tester);
    expect(find.text('Approved dashboard'), findsOneWidget);
    await tester.runAsync(services!.logout);
    await tester.pumpAndSettle();
    expect(session.canAccess, isFalse);
    expect(find.text('Approved dashboard'), findsNothing);
    expect(find.byType(SignupPage), findsOneWidget);
    expect(splash, findsNothing);
    expect(NotificationService.navigatorKey.currentState!.canPop(), isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SignupPage), findsOneWidget);
    expect(splash, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'real app launches splash but login route is immediate after logout',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      expect(splash, findsOneWidget);
      await finish(tester);
      expect(find.byType(SignupPage), findsOneWidget);
      NotificationService.navigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
      await tester.pump();
      expect(find.byType(SignupPage), findsWidgets);
      expect(splash, findsNothing);
      await tester.pumpAndSettle();
      expect(NotificationService.navigatorKey.currentState!.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'phone renders show centered branding, midpoint fade, and white login',
    (tester) async {
      final previousDisableShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousDisableShadows);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('splash_capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('build/startup-splash-validation')
            ..createSync(recursive: true);
          File(
            '${folder.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      try {
        for (final layout in [
          (size: const Size(320, 700), scale: 1.0, name: 'splash-small-phone'),
          (size: const Size(390, 844), scale: 1.0, name: 'splash-phone'),
          (size: const Size(844, 390), scale: 1.0, name: 'splash-landscape'),
          (size: const Size(320, 568), scale: 1.6, name: 'splash-large-text'),
        ]) {
          final size = layout.size;
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('splash_capture'),
              child: app(scale: layout.scale),
            ),
          );
          final context = tester.element(splash);
          await tester.runAsync(
            () => Future.wait([
              precacheImage(const AssetImage('assets/img/3.png'), context),
              precacheImage(
                const AssetImage('assets/img/logo_BU.png'),
                context,
              ),
            ]),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final logo = find.byWidgetPredicate(
            (widget) =>
                widget is Image && widget.semanticLabel == 'Bantay Ulang logo',
          );
          expect(logo, findsOneWidget);
          final logoRect = tester.getRect(logo);
          final titleRect = tester.getRect(find.text('Bantay Ulang'));
          final subtitleRect = tester.getRect(
            find.text('Keep track of your ulang and plants'),
          );
          expect(logoRect.center.dx, closeTo(size.width / 2, 0.5));
          expect(titleRect.center.dx, closeTo(logoRect.center.dx, 0.5));
          expect(subtitleRect.center.dx, closeTo(logoRect.center.dx, 0.5));
          expect(logoRect.bottom, lessThan(titleRect.top));
          expect(titleRect.bottom, lessThan(subtitleRect.top));
          expect(logoRect.top, greaterThanOrEqualTo(0));
          expect(subtitleRect.bottom, lessThanOrEqualTo(size.height));
          await capture(layout.name);
          await tester.pump(const Duration(milliseconds: 2500));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 175));
          if (size.width == 390) await capture('fade-midpoint');
          await tester.pump(const Duration(milliseconds: 175));
          await tester.pumpAndSettle();
          expect(find.text('Welcome Back'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (size.width == 390) await capture('login-phone');
          await tester.pumpWidget(const SizedBox());
        }
      } finally {
        debugDisableShadows = previousDisableShadows;
      }
    },
  );
}

class _Routes extends NavigatorObserver {
  final replaced = <Route<dynamic>>[];
  final old = <Route<dynamic>?>[];
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaced.add(newRoute!);
    old.add(oldRoute);
  }
}
