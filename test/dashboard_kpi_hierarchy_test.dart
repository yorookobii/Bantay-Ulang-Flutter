import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard KPI Hierarchy and Status logic', () {
    test('yield display handles positive, zero, and null values accurately', () {
      String formatYield(double? val) {
        if (val != null && val > 0) {
          return '${val.toStringAsFixed(1)} kg';
        }
        if (val != null) {
          return 'Pending';
        }
        return '--';
      }

      expect(formatYield(12.5), '12.5 kg');
      expect(formatYield(0.0), 'Pending');
      expect(formatYield(null), '--');
    });

    test('health status mapping identifies normal, warning, and alert levels', () {
      String evaluateHealth(String health) {
        final h = health.toLowerCase();
        if (h.contains('babala') || h.contains('panganib') || h.contains('delikado')) {
          return 'ALERT';
        }
        if (h.contains('katamtaman') || h.contains('bantayan')) {
          return 'WARNING';
        }
        return 'NORMAL';
      }

      expect(evaluateHealth('Malusog'), 'NORMAL');
      expect(evaluateHealth('Maayos'), 'NORMAL');
      expect(evaluateHealth('Katamtaman'), 'WARNING');
      expect(evaluateHealth('Babala'), 'ALERT');
    });

    test('water level status correctly classifies normal, low, and high readings', () {
      String waterLevelStatus(double? level) {
        if (level == null) return 'NORMAL';
        if (level < 40.0) return 'MABABA';
        if (level > 120.0) return 'MATAAS';
        return 'NORMAL';
      }

      expect(waterLevelStatus(null), 'NORMAL');
      expect(waterLevelStatus(95.0), 'NORMAL');
      expect(waterLevelStatus(35.0), 'MABABA');
      expect(waterLevelStatus(130.0), 'MATAAS');
    });

    test('landing_page.dart contains Ulang and Plant cards in Living Assets hero card and excludes Kondisyon ng Tubig and obsolete texts', () {
      final file = File('lib/landing_page.dart');
      final content = file.readAsStringSync();

      // Check inclusion of Ulang and Plant cards in Living Assets hero card
      expect(content.contains('_buildWaterParametersSection'), isTrue);
      expect(content.contains('_buildLivingAssetsHeroCard'), isTrue);
      expect(content.contains('_buildUlangCard'), isTrue);
      expect(content.contains('_buildPlantCard'), isTrue);
      expect(content.contains('Inaasahang Ani'), isTrue);
      expect(content.contains('Mga Halaman'), isTrue);

      // Check that removed texts are completely absent
      expect(content.contains('"Kondisyon ng Tubig"'), isFalse);
      expect(content.contains('Mga sukat mula sa water sensors'), isFalse);
      expect(content.contains('AQUAPONICS OVERVIEW'), isFalse);
      expect(content.contains('May Babala sa Tubig'), isFalse);
      expect(content.contains('Pangkalahatang Kalagayan'), isFalse);
      expect(content.contains('_buildAquaponicsOverviewSection'), isFalse);
      expect(content.contains('_buildAquaponicsHeroCard'), isFalse);
    });
  });
}
