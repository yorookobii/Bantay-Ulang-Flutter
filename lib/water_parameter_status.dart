/// Numeric water-card rules shared with the administrator's sensorReadings.js.
/// Configuration comes from Firestore settings/thresholds (snake_case fields).
enum WaterParameter { ph, temperature, oxygen, salinity, turbidity, tds }

enum WaterParameterStatus {
  optimal('OPTIMAL'),
  warning('WARNING'),
  critical('CRITICAL'),
  noData('NO DATA');

  const WaterParameterStatus(this.label);
  final String label;
}

class WaterParameterRange {
  const WaterParameterRange({this.min, this.max, String? minimumText})
    : _minimumText = minimumText;
  final double? min;
  final double? max;
  final String? _minimumText;

  WaterParameterStatus classify(double? value) {
    if (value == null || !value.isFinite) return WaterParameterStatus.noData;
    final lower = min;
    final upper = max;
    if (lower == null && upper == null) return WaterParameterStatus.optimal;

    final below = lower != null && value < lower;
    final above = upper != null && value > upper;
    if (below || above) {
      // Admin computeSeverity: high/critical (>25% beyond the reference)
      // renders CRITICAL; low/medium renders WARNING.
      final reference = lower != null && upper != null
          ? upper - lower
          : (lower ?? upper)!;
      final deviation = below ? lower - value : value - upper!;
      return deviation / reference > 0.25
          ? WaterParameterStatus.critical
          : WaterParameterStatus.warning;
    }

    if (lower != null && upper != null) {
      final edgeBand = (upper - lower) * 0.10;
      // Match admin JS's `min + edgeBand`, including its concatenation when
      // a legacy Firebase minimum was stored as text rather than a number.
      // The Settings page writes numbers; preserve parity for older documents.
      final edgeText =
          edgeBand.isFinite && edgeBand == edgeBand.truncateToDouble()
          ? edgeBand.toInt().toString()
          : edgeBand.toString();
      final lowerEdge = _minimumText == null
          ? lower + edgeBand
          : double.tryParse('$_minimumText$edgeText');
      if (value >= upper - edgeBand ||
          (lower > 0 && lowerEdge != null && value <= lowerEdge)) {
        return WaterParameterStatus.warning;
      }
    } else if (lower != null) {
      if (lower > 0 && value <= lower * 1.10) {
        return WaterParameterStatus.warning;
      }
    } else if (value >= upper! * 0.90) {
      return WaterParameterStatus.warning;
    }
    return WaterParameterStatus.optimal;
  }
}

class WaterParameterThresholds {
  WaterParameterThresholds._(this._ranges);
  final Map<WaterParameter, WaterParameterRange> _ranges;

  /// Missing fields use the same fallback ranges as admin thresholds.js.
  factory WaterParameterThresholds.fromFirestore(Map<String, dynamic>? data) {
    double? number(String key, double? fallback) {
      final raw = data?[key];
      final parsed = raw is num
          ? raw.toDouble()
          : raw is String
          ? double.tryParse(raw.trim())
          : null;
      return parsed != null && parsed.isFinite ? parsed : fallback;
    }

    String? minimumText(String key) {
      final raw = data?[key];
      return raw is String && double.tryParse(raw.trim())?.isFinite == true
          ? raw
          : null;
    }

    return WaterParameterThresholds._({
      WaterParameter.ph: WaterParameterRange(
        min: number('ph_min', 6.5),
        max: number('ph_max', 8.5),
        minimumText: minimumText('ph_min'),
      ),
      WaterParameter.temperature: WaterParameterRange(
        min: number('temp_min', 22),
        max: number('temp_max', 32),
        minimumText: minimumText('temp_min'),
      ),
      WaterParameter.oxygen: WaterParameterRange(min: number('o2_min', 5)),
      WaterParameter.salinity: WaterParameterRange(
        min: number('salinity_min', null),
        max: number('salinity_max', 5),
        minimumText: minimumText('salinity_min'),
      ),
      WaterParameter.turbidity: WaterParameterRange(
        max: number('turbidity_max', 25),
      ),
      WaterParameter.tds: WaterParameterRange(
        min: number('tds_min', null),
        max: number('tds_max', null),
        minimumText: minimumText('tds_min'),
      ),
    });
  }

  WaterParameterRange rangeFor(WaterParameter parameter) => _ranges[parameter]!;

  WaterParameterStatus classify(WaterParameter parameter, double? value) =>
      rangeFor(parameter).classify(value);
}
