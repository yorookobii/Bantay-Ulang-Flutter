import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'water_parameter_status.dart';

/// One badge for every dashboard water card, with the admin's exact labels.
class WaterParameterBadge extends StatelessWidget {
  const WaterParameterBadge({super.key, required this.status});

  /// Null means thresholds are still loading; avoid a guessed warning label.
  final WaterParameterStatus? status;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (status) {
      WaterParameterStatus.optimal => (
        const Color(0xFF059669),
        const Color(0xFFECFDF5),
      ),
      WaterParameterStatus.warning => (
        const Color(0xFFD97706),
        const Color(0xFFFEF3C7),
      ),
      WaterParameterStatus.critical => (
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
      ),
      WaterParameterStatus.noData ||
      null => (const Color(0xFF6B7280), const Color(0xFFF3F4F6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Text(
        status?.label ?? '--',
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
