import 'package:demo_1_langto/water_parameter_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final defaults = WaterParameterThresholds.fromFirestore(null);

  test('missing settings use the administrator fallback ranges', () {
    expect(defaults.rangeFor(WaterParameter.ph).min, 6.5);
    expect(defaults.rangeFor(WaterParameter.ph).max, 8.5);
    expect(defaults.rangeFor(WaterParameter.temperature).min, 22);
    expect(defaults.rangeFor(WaterParameter.temperature).max, 32);
    expect(defaults.rangeFor(WaterParameter.oxygen).min, 5);
    expect(defaults.rangeFor(WaterParameter.oxygen).max, isNull);
    expect(defaults.rangeFor(WaterParameter.salinity).min, isNull);
    expect(defaults.rangeFor(WaterParameter.salinity).max, 5);
    expect(defaults.rangeFor(WaterParameter.turbidity).max, 25);
    expect(defaults.rangeFor(WaterParameter.tds).min, isNull);
    expect(defaults.rangeFor(WaterParameter.tds).max, isNull);
  });

  test('every admin Firebase field overrides its corresponding range', () {
    final configured = WaterParameterThresholds.fromFirestore({
      'ph_min': 7, 'ph_max': 9,
      'temp_min': 26, 'temp_max': 29,
      'o2_min': 7,
      'salinity_min': 1, 'salinity_max': 2,
      'turbidity_max': 10,
      'tds_min': 1000, 'tds_max': 3000,
      // Former farm fields must not influence the global admin configuration.
      'phMin': 1, 'phMax': 2,
    });
    expect(configured.rangeFor(WaterParameter.ph).min, 7);
    expect(configured.rangeFor(WaterParameter.ph).max, 9);
    expect(configured.rangeFor(WaterParameter.temperature).min, 26);
    expect(configured.rangeFor(WaterParameter.temperature).max, 29);
    expect(configured.rangeFor(WaterParameter.oxygen).min, 7);
    expect(configured.rangeFor(WaterParameter.salinity).min, 1);
    expect(configured.rangeFor(WaterParameter.salinity).max, 2);
    expect(configured.rangeFor(WaterParameter.turbidity).max, 10);
    expect(configured.rangeFor(WaterParameter.tds).min, 1000);
    expect(configured.rangeFor(WaterParameter.tds).max, 3000);
    expect(
      configured.classify(WaterParameter.ph, 7.5),
      WaterParameterStatus.optimal,
    );
    expect(
      configured.classify(WaterParameter.oxygen, 6),
      WaterParameterStatus.warning,
    );
    expect(
      configured.classify(WaterParameter.salinity, 3),
      WaterParameterStatus.critical,
    );
    expect(
      configured.classify(WaterParameter.turbidity, 15),
      WaterParameterStatus.critical,
    );
  });

  test('TDS has no invented safe range when admin limits are unset', () {
    expect(
      defaults.classify(WaterParameter.tds, 3852),
      WaterParameterStatus.optimal,
    );
    expect(
      defaults.classify(WaterParameter.tds, 100000),
      WaterParameterStatus.optimal,
    );
  });

  test(
    'TDS follows its independent configured near-edge and severity boundaries',
    () {
      final settings = WaterParameterThresholds.fromFirestore({
        'tds_min': 1000,
        'tds_max': 3000,
      });
      for (final (reading, status) in <(double, WaterParameterStatus)>[
        (1000, WaterParameterStatus.warning),
        (1200, WaterParameterStatus.warning),
        (1200.01, WaterParameterStatus.optimal),
        (2000, WaterParameterStatus.optimal),
        (2800, WaterParameterStatus.warning),
        (3000, WaterParameterStatus.warning),
        (3500, WaterParameterStatus.warning),
        (3500.01, WaterParameterStatus.critical),
        (500, WaterParameterStatus.warning),
        (499.99, WaterParameterStatus.critical),
      ]) {
        expect(
          settings.classify(WaterParameter.tds, reading),
          status,
          reason: 'TDS=$reading',
        );
      }
      expect(settings.rangeFor(WaterParameter.salinity).max, 5);
      expect(
        settings.classify(WaterParameter.salinity, 1),
        WaterParameterStatus.optimal,
      );
    },
  );

  test('TDS also supports one-sided admin limits', () {
    final minimum = WaterParameterThresholds.fromFirestore({'tds_min': 1000});
    expect(
      minimum.classify(WaterParameter.tds, 1100),
      WaterParameterStatus.warning,
    );
    expect(
      minimum.classify(WaterParameter.tds, 1100.01),
      WaterParameterStatus.optimal,
    );
    expect(
      minimum.classify(WaterParameter.tds, 749),
      WaterParameterStatus.critical,
    );
    final maximum = WaterParameterThresholds.fromFirestore({'tds_max': 3000});
    expect(
      maximum.classify(WaterParameter.tds, 0),
      WaterParameterStatus.optimal,
    );
    expect(
      maximum.classify(WaterParameter.tds, 2700),
      WaterParameterStatus.warning,
    );
    expect(
      maximum.classify(WaterParameter.tds, 3751),
      WaterParameterStatus.critical,
    );
  });

  test(
    'numeric settings strings are accepted and invalid fields fall back',
    () {
      final settings = WaterParameterThresholds.fromFirestore({
        'ph_min': ' 7.0 ',
        'ph_max': '9',
        'o2_min': 'invalid',
        'turbidity_max': double.infinity,
      });
      expect(settings.rangeFor(WaterParameter.ph).min, 7);
      expect(settings.rangeFor(WaterParameter.ph).max, 9);
      expect(settings.rangeFor(WaterParameter.oxygen).min, 5);
      expect(settings.rangeFor(WaterParameter.turbidity).max, 25);
      final invalidMinimum = WaterParameterThresholds.fromFirestore({
        'ph_min': 'invalid',
      });
      expect(
        invalidMinimum.classify(WaterParameter.ph, 6.6),
        WaterParameterStatus.warning,
      );
    },
  );

  test('text minima preserve the admin JavaScript near-edge behavior', () {
    // Admin uses `min + edgeBand`: text '6' concatenates with the band.
    // Numeric 6 behaves differently. Both clients must still agree.
    final text = WaterParameterThresholds.fromFirestore({
      'ph_min': '6',
      'ph_max': '9',
    });
    final numeric = WaterParameterThresholds.fromFirestore({
      'ph_min': 6,
      'ph_max': 9,
    });
    expect(text.classify(WaterParameter.ph, 7.5), WaterParameterStatus.warning);
    expect(
      numeric.classify(WaterParameter.ph, 7.5),
      WaterParameterStatus.optimal,
    );
  });

  // Explicit expected results at each admin near-edge/severity boundary.
  final cases = <(WaterParameter, double, WaterParameterStatus)>[
    (WaterParameter.ph, 6.5, WaterParameterStatus.warning),
    (WaterParameter.ph, 6.7, WaterParameterStatus.warning),
    (WaterParameter.ph, 6.70001, WaterParameterStatus.optimal),
    (WaterParameter.ph, 7.5, WaterParameterStatus.optimal),
    (WaterParameter.ph, 8.29999, WaterParameterStatus.optimal),
    (WaterParameter.ph, 8.3, WaterParameterStatus.warning),
    (WaterParameter.ph, 8.5, WaterParameterStatus.warning),
    (WaterParameter.ph, 6.0, WaterParameterStatus.warning),
    (WaterParameter.ph, 5.99999, WaterParameterStatus.critical),
    (WaterParameter.ph, 9.0, WaterParameterStatus.warning),
    (WaterParameter.ph, 9.00001, WaterParameterStatus.critical),
    (WaterParameter.temperature, 22, WaterParameterStatus.warning),
    (WaterParameter.temperature, 23, WaterParameterStatus.warning),
    (WaterParameter.temperature, 23.00001, WaterParameterStatus.optimal),
    (WaterParameter.temperature, 31, WaterParameterStatus.warning),
    (WaterParameter.temperature, 34.5, WaterParameterStatus.warning),
    (WaterParameter.temperature, 34.50001, WaterParameterStatus.critical),
    (WaterParameter.oxygen, 5, WaterParameterStatus.warning),
    (WaterParameter.oxygen, 5.5, WaterParameterStatus.warning),
    (WaterParameter.oxygen, 5.50001, WaterParameterStatus.optimal),
    (WaterParameter.oxygen, 3.75, WaterParameterStatus.warning),
    (WaterParameter.oxygen, 3.74999, WaterParameterStatus.critical),
    (WaterParameter.oxygen, 100, WaterParameterStatus.optimal),
    (WaterParameter.salinity, 0, WaterParameterStatus.optimal),
    (WaterParameter.salinity, 4.49999, WaterParameterStatus.optimal),
    (WaterParameter.salinity, 4.5, WaterParameterStatus.warning),
    (WaterParameter.salinity, 5, WaterParameterStatus.warning),
    (WaterParameter.salinity, 6.25, WaterParameterStatus.warning),
    (WaterParameter.salinity, 6.25001, WaterParameterStatus.critical),
    (WaterParameter.turbidity, 0, WaterParameterStatus.optimal),
    (WaterParameter.turbidity, 22.49999, WaterParameterStatus.optimal),
    (WaterParameter.turbidity, 22.5, WaterParameterStatus.warning),
    (WaterParameter.turbidity, 25, WaterParameterStatus.warning),
    (WaterParameter.turbidity, 31.25, WaterParameterStatus.warning),
    (WaterParameter.turbidity, 31.25001, WaterParameterStatus.critical),
  ];
  for (final (parameter, reading, status) in cases) {
    test('$parameter at $reading is ${status.label}', () {
      expect(defaults.classify(parameter, reading), status);
    });
  }

  for (final parameter in WaterParameter.values) {
    test('$parameter never treats missing or nonfinite data as optimal', () {
      for (final value in [
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          defaults.classify(parameter, value),
          WaterParameterStatus.noData,
        );
      }
    });
  }

  test('a zero lower boundary has no near-zero warning, matching admin', () {
    final settings = WaterParameterThresholds.fromFirestore({
      'salinity_min': 0,
      'salinity_max': 10,
    });
    expect(
      settings.classify(WaterParameter.salinity, 0),
      WaterParameterStatus.optimal,
    );
    expect(
      settings.classify(WaterParameter.salinity, 1),
      WaterParameterStatus.optimal,
    );
    expect(
      settings.classify(WaterParameter.salinity, 9),
      WaterParameterStatus.warning,
    );
  });

  test('new admin thresholds change the label for an unchanged reading', () {
    final updated = WaterParameterThresholds.fromFirestore({
      'turbidity_max': 50,
    });
    expect(
      defaults.classify(WaterParameter.turbidity, 30),
      WaterParameterStatus.warning,
    );
    expect(
      updated.classify(WaterParameter.turbidity, 30),
      WaterParameterStatus.optimal,
    );
  });
}
