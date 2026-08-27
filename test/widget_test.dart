import 'package:demo_1_langto/signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildAuthScreen() {
    return const MaterialApp(home: SignupPage());
  }

  testWidgets('shows the direct login form', (tester) async {
    await tester.pumpWidget(buildAuthScreen());

    expect(find.text('Bantay Ulang'), findsOneWidget);
    expect(find.text('Mag-log in'), findsWidgets);
    expect(find.text('Nakalimutan ang Password?'), findsOneWidget);
    expect(find.text('Gumawa ng Account'), findsOneWidget);
  });

  testWidgets('validates sign-up fields before creating an account', (
    tester,
  ) async {
    await tester.pumpWidget(buildAuthScreen());

    await tester.tap(find.text('Gumawa ng Account').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Gumawa ng Account'));
    await tester.pump();

    expect(find.text('Kinakailangan ang buong pangalan.'), findsOneWidget);
    expect(find.text('Kinakailangan ang email address.'), findsOneWidget);
    expect(find.text('Kinakailangan ang password.'), findsOneWidget);
  });
}
