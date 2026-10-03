import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard pull to refresh', () {
    test('refreshes every live dashboard source from the server', () {
      final content = File('lib/landing_page.dart').readAsStringSync();
      final refreshStart = content.indexOf(
        'Future<void> _refreshDashboardData() async',
      );
      final refreshEnd = content.indexOf(
        'Future<void> _loadUserInitials()',
        refreshStart,
      );

      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(refreshEnd, greaterThan(refreshStart));
      final refreshMethod = content.substring(refreshStart, refreshEnd);
      expect(refreshMethod, contains("collection('Aquaponics')"));
      expect(refreshMethod, contains("doc('Ulang')"));
      expect(refreshMethod, contains("collection('alerts')"));
      expect(refreshMethod, contains("collection('tasks')"));
      expect(refreshMethod, contains("where('assignedTo', isEqualTo: uid)"));
      expect(refreshMethod, contains("task['status'] == 'pending'"));
      expect(refreshMethod, contains("collection('growth_indicators')"));
      expect(refreshMethod, contains('Source.server'));
      expect(refreshMethod, isNot(contains("collection('sensor_readings')")));
      expect(refreshMethod, contains('final readingsChanged ='));
      expect(
        refreshMethod,
        contains('Dashboard refreshed with new sensor data.'),
      );
      expect(
        refreshMethod,
        contains(
          'The data is up to date and matches the latest readings.',
        ),
      );
      expect(
        refreshMethod,
        contains('Unable to refresh the dashboard. Please try again.'),
      );
      expect(refreshMethod, isNot(contains('Matagumpay')));
      expect(refreshMethod, isNot(contains('Napapanahon')));
      expect(refreshMethod, isNot(contains('Hindi ma-refresh')));
      expect(refreshMethod, contains('_showDashboardRefreshMessage('));
    });

    test('dashboard scroll view is connected to the refresh callback', () {
      final content = File('lib/landing_page.dart').readAsStringSync();

      expect(content, contains("Key('dashboard_refresh_indicator')"));
      expect(content, contains('onRefresh: _refreshDashboardData'));
      expect(content, contains('AlwaysScrollableScrollPhysics()'));
    });

    test('refresh message matches the Logs success message styling', () {
      final dashboard = File('lib/landing_page.dart').readAsStringSync();
      final logs = File('lib/logs.dart').readAsStringSync();
      final dashboardStyle = dashboard.substring(
        dashboard.indexOf('void _showDashboardRefreshMessage('),
        dashboard.indexOf('Future<void> _loadUserInitials()'),
      );
      final logsStyle = logs.substring(
        logs.indexOf('void _showSuccessSnackbar('),
        logs.indexOf('void _showErrorSnackbar('),
      );

      for (final style in [dashboardStyle, logsStyle]) {
        expect(style, contains('Icons.check_circle'));
        expect(style, contains('SizedBox(width: 12)'));
        expect(style, contains('fontWeight: FontWeight.w500'));
        expect(style, contains('BorderRadius.circular(10)'));
        expect(style, contains('EdgeInsets.all(16)'));
        expect(style, isNot(contains('padding:')));
      }
      expect(dashboardStyle, contains('isError ? warningRed : tealDark'));
      expect(logsStyle, contains('backgroundColor: tealDark'));
    });

    testWidgets('pulling down triggers the refresh callback', (tester) async {
      var refreshTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              key: const Key('dashboard_refresh_indicator'),
              onRefresh: () async {
                refreshTriggered = true;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 1000)],
              ),
            ),
          ),
        ),
      );

      await tester.fling(
        find.byType(ListView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshTriggered, isTrue);
    });
  });
}
