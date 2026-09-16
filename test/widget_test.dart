import 'package:demo_1_langto/signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildAuthScreen() {
    return const MaterialApp(home: SignupPage());
  }

  testWidgets('shows the direct login form', (tester) async {
    await tester.pumpWidget(buildAuthScreen());

    expect(find.textContaining('Bantay Ulang'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Create an Account'), findsWidgets);
  });

  testWidgets('validates sign-up fields before creating an account', (
    tester,
  ) async {
    await tester.pumpWidget(buildAuthScreen());

    await tester.tap(find.text('Create an Account').first);
    await tester.pump(const Duration(milliseconds: 300));
    final submitButton = find.widgetWithText(ElevatedButton, 'Create an Account');
    await tester.ensureVisible(submitButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(submitButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Kinakailangan ang buong pangalan.'), findsOneWidget);
    expect(find.text('Kinakailangan ang email address.'), findsOneWidget);
    expect(find.text('Kinakailangan ang password.'), findsOneWidget);
  });
}
