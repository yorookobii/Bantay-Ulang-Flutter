import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:demo_1_langto/logs.dart';

void main() {
  testWidgets('WeeklyGrowthLinePainter renders without throwing exceptions for 1 week', (tester) async {
    final data = [
      {
        'weekNumber': 1,
        'label': 'W1',
        'longLabel': 'Linggo 1',
        'avgWeight': 12.5,
        'totalWeight': 37.5,
        'count': 3,
        'dateRange': 'Jan 1 - Jan 7',
      }
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 180,
            child: CustomPaint(
              size: const Size(360, 180),
              painter: WeeklyGrowthLinePainter(
                data: data,
                selectedIndex: 0,
                tealColor: const Color(0xFF0D9488),
                tealDarkColor: const Color(0xFF0F766E),
                textDarkColor: const Color(0xFF1F2937),
                textMutedColor: const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is WeeklyGrowthLinePainter),
      findsOneWidget,
    );
  });

  testWidgets('WeeklyGrowthLinePainter renders without throwing exceptions for 3 weeks', (tester) async {
    final data = [
      {
        'weekNumber': 1,
        'label': 'W1',
        'longLabel': 'Linggo 1',
        'avgWeight': 10.0,
        'totalWeight': 20.0,
        'count': 2,
        'dateRange': 'Jan 1 - Jan 7',
      },
      {
        'weekNumber': 2,
        'label': 'W2',
        'longLabel': 'Linggo 2',
        'avgWeight': 18.5,
        'totalWeight': 74.0,
        'count': 4,
        'dateRange': 'Jan 8 - Jan 14',
      },
      {
        'weekNumber': 3,
        'label': 'W3',
        'longLabel': 'Linggo 3',
        'avgWeight': 25.2,
        'totalWeight': 126.0,
        'count': 5,
        'dateRange': 'Jan 15 - Jan 21',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 180,
            child: CustomPaint(
              size: const Size(380, 180),
              painter: WeeklyGrowthLinePainter(
                data: data,
                selectedIndex: 2,
                tealColor: const Color(0xFF0D9488),
                tealDarkColor: const Color(0xFF0F766E),
                textDarkColor: const Color(0xFF1F2937),
                textMutedColor: const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is WeeklyGrowthLinePainter),
      findsOneWidget,
    );
  });
}
