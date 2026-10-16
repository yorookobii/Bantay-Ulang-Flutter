import 'dart:io';
import 'dart:ui' as ui;

import 'package:demo_1_langto/main.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/privacy_policy.dart';
import 'package:demo_1_langto/settings.dart';
import 'package:demo_1_langto/signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrivacyPolicyDocument document;

  setUpAll(() async {
    document = await PrivacyPolicyDocument.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final previewFont = Platform.environment['BANTAY_PREVIEW_ROBOTO'];
    if (previewFont != null) {
      await (FontLoader('Roboto')..addFont(
            File(previewFont).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    OfflineServices.current = null;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    // The bundled asset can complete in the real I/O zone, outside FakeAsync.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(MaterialApp(home: home));
    await settle(tester);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('bundled policy is readable without Firebase or authentication', (
    tester,
  ) async {
    // No Firebase.initializeApp, backend doubles, or signed-in user is needed.
    await show(tester, const PrivacyPolicyPage());
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Bantay Ulang'), findsOneWidget);
    expect(document.lastUpdated, 'October 12, 2026');
    expect(find.text('Last updated: October 12, 2026'), findsOneWidget);
    for (final removedText in [
      'Proposed effective date:',
      'Authentication service information:',
      'On your device:',
      'Privacy correspondence:',
      'Publication review pending:',
      'This policy describes the current mobile application',
      'The current app does not request FCM notification tokens',
      'Google processes information to provide these services',
      'The current mobile app does not integrate Firebase Realtime Database',
      'Administrators access account and farm information to operate the system',
      'Server access also depends on deployed Firebase Security Rules',
      'Firebase documents HTTPS encryption',
      'There is currently no automatic in-app account-deletion flow',
      'The current app does not request camera',
      'Provider privacy information',
      'https://firebase.google.com/',
    ]) {
      expect(find.textContaining(removedText), findsNothing);
    }
    expect(
      find.textContaining('not designed for users under 13 years of age'),
      findsOneWidget,
    );
    expect(document.sections, hasLength(10));
    for (final section in document.sections) {
      expect(find.text(section.title), findsOneWidget);
      for (final paragraph in section.paragraphs) {
        expect(find.text(paragraph), findsOneWidget);
      }
    }
    await tester.ensureVisible(find.text('Contact Information'));
    await settle(tester);
    expect(find.text('quadlabs2026@gmail.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final register in [false, true]) {
    testWidgets(
      '${register ? 'registration' : 'login'} policy link preserves form',
      (tester) async {
        await show(tester, const SignupPage());
        if (register) {
          await tester.tap(find.text('Create an Account').first);
          await settle(tester);
        }
        await tester.enterText(
          find.byType(TextFormField).first,
          register ? 'Farm Practitioner' : 'farm@example.com',
        );
        final policyLink = find.byKey(const Key('auth_privacy_policy'));
        await tester.ensureVisible(policyLink);
        await tester.tap(policyLink);
        await settle(tester);
        expect(find.byType(PrivacyPolicyPage), findsOneWidget);
        expect(find.text('Introduction'), findsOneWidget);
        await tester.pageBack();
        await settle(tester);
        expect(find.byType(SignupPage), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(register ? 4 : 2));
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          register ? 'Farm Practitioner' : 'farm@example.com',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Settings opens public policy and Back returns to Settings', (
    tester,
  ) async {
    await show(tester, const SettingsPage());
    await tester.tap(find.byKey(const Key('settings_privacy_policy')));
    await settle(tester);
    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real app exposes privacy and settings routes without a session',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      NotificationService.navigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/privacy',
        (_) => false,
      );
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
      expect(NotificationService.navigatorKey.currentState!.canPop(), isFalse);
      NotificationService.navigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/settings',
        (_) => false,
      );
      await settle(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'policy, settings, and login render at phone sizes with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final originalDisableShadows = debugDisableShadows;
      debugDisableShadows = false;

      Widget app(Widget home, double scale) => RepaintBoundary(
        key: const Key('privacy_capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: home,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      );

      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('privacy_capture')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final folder = Directory('build/privacy-validation')
            ..createSync(recursive: true);
          File(
            '${folder.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      try {
        for (final layout in [
          (size: const Size(320, 700), scale: 1.0, name: 'small'),
          (size: const Size(390, 844), scale: 1.0, name: 'phone'),
          (size: const Size(844, 390), scale: 1.0, name: 'landscape'),
          (size: const Size(320, 568), scale: 1.6, name: 'large-text'),
        ]) {
          tester.view.physicalSize = layout.size;
          await tester.pumpWidget(app(const PrivacyPolicyPage(), layout.scale));
          await settle(tester);
          await capture('privacy-${layout.name}');
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Policy Updates'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          if (layout.name == 'phone') await capture('privacy-footer');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(app(const SettingsPage(), layout.scale));
          await settle(tester);
          expect(tester.takeException(), isNull);
          if (layout.name == 'phone') await capture('settings-phone');
          await tester.pumpWidget(const SizedBox());
        }
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(app(const SignupPage(), 1));
        await settle(tester);
        await capture('login-policy-link');
        expect(find.byKey(const Key('auth_privacy_policy')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = originalDisableShadows;
      }
    },
  );
}
