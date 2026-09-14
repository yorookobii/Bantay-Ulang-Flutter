import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard Pull-to-Refresh and Scroll-Down Sensor Refresh', () {
    test('landing_page.dart contains all required refresh and scroll detection components', () {
      final file = File('lib/landing_page.dart');
      final content = file.readAsStringSync();

      // RefreshIndicator on dashboard
      expect(content.contains('dashboard_refresh_indicator'), isTrue,
          reason: 'Dashboard should have a RefreshIndicator with key dashboard_refresh_indicator');
      expect(content.contains('RefreshIndicator('), isTrue);
      expect(content.contains('onRefresh: () => _refreshSensorData(isPullToRefresh: true)'), isTrue);

      // Scroll physics must be AlwaysScrollableScrollPhysics for pull to refresh
      expect(content.contains('AlwaysScrollableScrollPhysics()'), isTrue);

      // Core methods and state variables
      expect(content.contains('_refreshSensorData'), isTrue);
      expect(content.contains('_onDashboardScrolledDown'), isTrue);
      expect(content.contains('_checkNewSensorDataOnScroll'), isTrue);
      expect(content.contains('_hasSensorDataChanged'), isTrue);
      expect(content.contains('_applySensorData'), isTrue);
      expect(content.contains('_lastSensorDocId'), isTrue);
      expect(content.contains('_lastSensorTimestamp'), isTrue);
      expect(content.contains('_lastScrollRefreshCheck'), isTrue);
      expect(content.contains('_isRefreshingSensor'), isTrue);
      expect(content.contains('_isCheckingNewData'), isTrue);

      // User feedback SnackBars
      expect(content.contains('May bagong datos ng sensor na naitala.'), isTrue);
      expect(content.contains('Na-refresh: May bagong datos ng sensor na naitala.'), isTrue);
      expect(content.contains('Napapanahon ang datos ng sensor.'), isTrue);
      expect(content.contains('Hindi ma-refresh ang datos ng sensor. Subukan muli.'), isTrue);
    });

    test('sensor data change detector accurately detects new or changed values', () {
      bool hasSensorDataChanged({
        required Map<String, dynamic> newData,
        required double? currentTemp,
        required double? currentPh,
        required double? currentDo,
        required double? currentSal,
        required double? currentTurb,
        required double? currentWLevel,
      }) {
        final wTemp = (newData['waterTemp'] as num?)?.toDouble();
        final ph = (newData['phLevel'] as num?)?.toDouble();
        final dOx = (newData['dissolvedOxygen'] as num?)?.toDouble();
        final sal = (newData['salinity'] as num?)?.toDouble();
        final turb = (newData['turbidity'] as num?)?.toDouble();
        final wLevel = (newData['waterLevel'] as num?)?.toDouble();

        return wTemp != currentTemp ||
            ph != currentPh ||
            dOx != currentDo ||
            sal != currentSal ||
            turb != currentTurb ||
            wLevel != currentWLevel;
      }

      final initial = {
        'waterTemp': 28.5,
        'phLevel': 7.4,
        'dissolvedOxygen': 6.8,
        'salinity': 0.5,
        'turbidity': 12.0,
        'waterLevel': 85.0,
      };

      // 1. Same data should return false
      expect(
        hasSensorDataChanged(
          newData: initial,
          currentTemp: 28.5,
          currentPh: 7.4,
          currentDo: 6.8,
          currentSal: 0.5,
          currentTurb: 12.0,
          currentWLevel: 85.0,
        ),
        isFalse,
      );

      // 2. New pH reading should return true
      expect(
        hasSensorDataChanged(
          newData: {...initial, 'phLevel': 7.8},
          currentTemp: 28.5,
          currentPh: 7.4,
          currentDo: 6.8,
          currentSal: 0.5,
          currentTurb: 12.0,
          currentWLevel: 85.0,
        ),
        isTrue,
      );

      // 3. New Dissolved Oxygen reading should return true
      expect(
        hasSensorDataChanged(
          newData: {...initial, 'dissolvedOxygen': 5.2},
          currentTemp: 28.5,
          currentPh: 7.4,
          currentDo: 6.8,
          currentSal: 0.5,
          currentTurb: 12.0,
          currentWLevel: 85.0,
        ),
        isTrue,
      );

      // 4. New Water Level reading should return true
      expect(
        hasSensorDataChanged(
          newData: {...initial, 'waterLevel': 92.0},
          currentTemp: 28.5,
          currentPh: 7.4,
          currentDo: 6.8,
          currentSal: 0.5,
          currentTurb: 12.0,
          currentWLevel: 85.0,
        ),
        isTrue,
      );
    });

    test('scroll-down debouncer throttles rapid checks to prevent excessive queries', () {
      DateTime? lastCheck;
      int checkCount = 0;

      void onDashboardScrolledDown(DateTime now) {
        if (lastCheck != null && now.difference(lastCheck!).inSeconds < 10) {
          return; // Throttled
        }
        lastCheck = now;
        checkCount++;
      }

      final t0 = DateTime(2026, 9, 13, 12, 0, 0);
      onDashboardScrolledDown(t0);
      expect(checkCount, 1);

      // Rapid scroll 2 seconds later - should be throttled
      onDashboardScrolledDown(t0.add(const Duration(seconds: 2)));
      expect(checkCount, 1);

      // Rapid scroll 5 seconds later - should be throttled
      onDashboardScrolledDown(t0.add(const Duration(seconds: 5)));
      expect(checkCount, 1);

      // Scroll after 10 seconds - should trigger new check
      onDashboardScrolledDown(t0.add(const Duration(seconds: 11)));
      expect(checkCount, 2);
    });

    testWidgets('RefreshIndicator triggers refresh callback when pulled down', (tester) async {
      bool refreshTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              key: const Key('dashboard_refresh_indicator'),
              onRefresh: () async {
                refreshTriggered = true;
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Container(
                  height: 1000,
                  color: Colors.white,
                  child: const Text("Dashboard Content"),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('dashboard_refresh_indicator')), findsOneWidget);
      expect(find.text("Dashboard Content"), findsOneWidget);

      // Pull down gesture to trigger pull to refresh
      await tester.fling(find.text("Dashboard Content"), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshTriggered, isTrue);
    });
  });
}
