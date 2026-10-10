import 'package:demo_1_langto/signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget buildAuthScreen() {
    return const MaterialApp(home: SignupPage());
  }

  testWidgets('shows the direct login form', (tester) async {
    await tester.pumpWidget(buildAuthScreen());
    await tester.pump();

    expect(find.textContaining('Bantay Ulang'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Create an Account'), findsWidgets);
  });

  testWidgets('validates sign-up fields before creating an account', (
    tester,
  ) async {
    await tester.pumpWidget(buildAuthScreen());
    await tester.pump();

    await tester.tap(find.text('Create an Account').first);
    await tester.pump(const Duration(milliseconds: 300));
    final submitButton = find.widgetWithText(
      ElevatedButton,
      'Create an Account',
    );
    await tester.ensureVisible(submitButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(submitButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });
}
