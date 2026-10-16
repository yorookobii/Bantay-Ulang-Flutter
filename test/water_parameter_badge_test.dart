import 'package:demo_1_langto/water_parameter_badge.dart';
import 'package:demo_1_langto/water_parameter_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (status, label, color) in [
    (WaterParameterStatus.optimal, 'OPTIMAL', const Color(0xFF059669)),
    (WaterParameterStatus.warning, 'WARNING', const Color(0xFFD97706)),
    (WaterParameterStatus.critical, 'CRITICAL', const Color(0xFFDC2626)),
    (WaterParameterStatus.noData, 'NO DATA', const Color(0xFF6B7280)),
    (null, '--', const Color(0xFF6B7280)),
  ]) {
    testWidgets('badge renders $label with its correct status color', (
      tester,
    ) async {
      // The existing mobile cards have little space; verify the longest labels
      // also fit at the accessible text scale without changing the card layout.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 110,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: WaterParameterBadge(status: status),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(tester.widget<Text>(find.text(label)).style!.color, color);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'same reading changes its badge when Firebase thresholds change',
    (tester) async {
      Future<void> show(Map<String, dynamic>? settings) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaterParameterBadge(
              status: WaterParameterThresholds.fromFirestore(
                settings,
              ).classify(WaterParameter.ph, 8.2),
            ),
          ),
        ),
      );
      await show(null);
      expect(find.text('OPTIMAL'), findsOneWidget);
      await show({'ph_max': 8.0});
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('OPTIMAL'), findsNothing);
      await show({'ph_max': 7.0});
      expect(find.text('CRITICAL'), findsOneWidget);
    },
  );
}
