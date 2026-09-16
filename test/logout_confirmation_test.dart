import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:demo_1_langto/profile.dart';

void main() {
  Widget buildTestApp({VoidCallback? onConfirm}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('trigger_logout'),
              onPressed: () {
                showLogoutConfirmationDialog(
                  context,
                  onConfirm: onConfirm,
                );
              },
              child: const Text('Log Out'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping logout shows confirmation dialog with Yes and No options', (tester) async {
    await tester.pumpWidget(buildTestApp());

    // Initially, dialog should not be visible
    expect(find.text('Confirm Logout'), findsNothing);
    expect(find.text('Are you sure you want to log out?'), findsNothing);

    // Tap the trigger button
    await tester.tap(find.byKey(const Key('trigger_logout')));
    await tester.pumpAndSettle();

    // The dialog should now be visible
    expect(find.text('Confirm Logout'), findsOneWidget);
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);
    expect(find.byKey(const Key('logout_no_button')), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.byKey(const Key('logout_yes_button')), findsOneWidget);
    expect(find.text('Yes, Log Out'), findsOneWidget);
  });

  testWidgets('choosing No closes the confirmation window without confirming', (tester) async {
    bool confirmed = false;
    await tester.pumpWidget(buildTestApp(onConfirm: () {
      confirmed = true;
    }));

    // Open confirmation dialog
    await tester.tap(find.byKey(const Key('trigger_logout')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Logout'), findsOneWidget);

    // Tap "No"
    await tester.tap(find.byKey(const Key('logout_no_button')));
    await tester.pumpAndSettle();

    // Dialog should have disappeared
    expect(find.text('Confirm Logout'), findsNothing);
    expect(find.text('Are you sure you want to log out?'), findsNothing);
    // User should not be logged out
    expect(confirmed, isFalse);
  });

  testWidgets('choosing Yes, Log Out closes the window and executes onConfirm', (tester) async {
    bool confirmed = false;
    await tester.pumpWidget(buildTestApp(onConfirm: () {
      confirmed = true;
    }));

    // Open confirmation dialog
    await tester.tap(find.byKey(const Key('trigger_logout')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Logout'), findsOneWidget);

    // Tap "Yes, Log Out"
    await tester.tap(find.byKey(const Key('logout_yes_button')));
    await tester.pumpAndSettle();

    // Dialog should have disappeared
    expect(find.text('Confirm Logout'), findsNothing);
    // onConfirm should have been triggered
    expect(confirmed, isTrue);
  });
}
