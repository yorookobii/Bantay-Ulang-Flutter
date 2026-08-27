import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class YieldEstimationPage extends StatefulWidget {
  final void Function(
    double expectedYield,
    String shrimpHealth,
    String plantHealth,
  )?
  onGrowthData;
  const YieldEstimationPage({super.key, this.onGrowthData});

  @override
  State<YieldEstimationPage> createState() => _YieldEstimationPageState();
}

class _YieldEstimationPageState extends State<YieldEstimationPage>
    with SingleTickerProviderStateMixin {
  // High-Contrast Aquatic Palette
  final Color tealLight = const Color(0xFFE6FFF9);
  final Color teal = const Color(0xFF0D9488);
  final Color tealDark = const Color(0xFF0F766E);
  final Color seaBlue = const Color(0xFF0369A1);
  final Color textDark = const Color(0xFF1F2937);
  final Color textMuted = const Color(0xFF6B7280);
  final Color successGreen = const Color(0xFF10B981);

  late AnimationController _fadeController;
  StreamSubscription<QuerySnapshot>? _growthSub;

  bool _isLoading = true;
  bool _isRecalculating = false;

  // Firestore-backed fields
  double? _rfProjectedYield;
  double? _rfProjectedWeight;
  DateTime? _cycleStart;
  DateTime? _cycleEnd;
  DateTime? _targetHarvestDate;
  double _survivalRate = 0;
  String _summaryNote = '';
  String? _errorMessage;

  // RF batch-inference metadata (written by ml-analytics/predict_yield.py)
  String? _rfMode;
  String _rfNote = '';
  int? _rfReadingsUsed;
  DateTime? _rfUpdatedAt;

  // Panelist requirement: yield prediction only after 90 days of real
  // cultivation data — mirrors RF_GATE_DAYS in web/yieldPrediction.js.
  static const int _rfGateDays = 90;
  bool _eligible = false;
  int? _weeksRemaining;

  bool get _rfAvailable =>
      _eligible && _rfProjectedYield != null && _rfProjectedYield! > 0;

  static const Map<String, String> _rfModeLabels = {
    'hybrid': 'RF Prediction — Hybrid',
    'real': 'RF Prediction — Real',
    'test': 'RF Prediction — Test',
  };

  String get _yieldBadgeText {
    if (_rfAvailable) return _rfModeLabels[_rfMode] ?? 'RF Prediction';
    if (!_eligible) return 'Pending';
    return 'Processing';
  }

  String get _yieldBigText {
    if (_rfAvailable) return '${_rfProjectedYield!.toStringAsFixed(0)} kg';
    if (!_eligible) return 'Pending';
    return 'Prediction being processed';
  }

  String get _yieldSubText {
    if (_rfAvailable) return 'Random Forest projection from live sensor data';
    if (!_eligible) {
      return _weeksRemaining != null
          ? 'Prediction available in $_weeksRemaining week${_weeksRemaining == 1 ? '' : 's'}'
          : 'Prediction pending — cycle start date not set';
    }
    return "The RF model hasn't produced a prediction for this cycle yet";
  }

  // Market price range (min/avg/max per kg) — BFAR National Consolidated
  // Price Monitoring Report 2025, matches web/yieldPrediction.js rates.
  static const double _priceMin = 150.0;
  static const double _priceAvg = 300.0;
  static const double _priceMax = 450.0;

  double? get _incomeMin =>
      _rfAvailable ? _rfProjectedYield! * _priceMin : null;
  double? get _incomeAvg =>
      _rfAvailable ? _rfProjectedYield! * _priceAvg : null;
  double? get _incomeMax =>
      _rfAvailable ? _rfProjectedYield! * _priceMax : null;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _subscribeGrowthIndicators();
  }

  void _subscribeGrowthIndicators() {
    _growthSub = FirebaseFirestore.instance
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            if (snapshot.docs.isEmpty) {
              setState(() => _isLoading = false);
              return;
            }
            final data = snapshot.docs.first.data() as Map<String, dynamic>;
            final rfProjectedYield =
                (data['rfProjectedYield'] as num?)?.toDouble();
            final shrimpHealth = (data['shrimpHealth'] as String?) ?? 'Malusog';
            final plantHealth = (data['plantHealth'] as String?) ?? 'Maayos';

            // 90-day gate — fractional days, matching web's
            // (Date.now() - cycleStart) / msPerDay (not whole-day truncation),
            // so the eligibility boundary lands on the same moment as the web.
            final cycleStart = (data['cycleStart'] as Timestamp?)?.toDate();
            bool eligible = false;
            int? weeksRemaining;
            if (cycleStart != null) {
              final daysSince =
                  DateTime.now().difference(cycleStart).inMilliseconds /
                  86400000;
              eligible = daysSince >= _rfGateDays;
              weeksRemaining = eligible
                  ? null
                  : ((_rfGateDays - daysSince) / 7).ceil();
            }

            setState(() {
              _isLoading = false;
              _errorMessage = null;
              _rfProjectedYield = rfProjectedYield;
              _rfProjectedWeight =
                  (data['rfProjectedWeight'] as num?)?.toDouble();
              _rfMode = data['rfMode'] as String?;
              _rfNote = (data['rfNote'] as String?) ?? '';
              _rfReadingsUsed = (data['rfReadingsUsed'] as num?)?.toInt();
              _rfUpdatedAt = (data['rfUpdatedAt'] as Timestamp?)?.toDate();
              _cycleStart = cycleStart;
              _cycleEnd = (data['cycleEnd'] as Timestamp?)?.toDate();
              _targetHarvestDate = (data['targetHarvestDate'] as Timestamp?)
                  ?.toDate();
              _survivalRate = (data['survivalRate'] as num?)?.toDouble() ?? 0;
              _summaryNote = (data['summaryNote'] as String?) ?? '';
              _eligible = eligible;
              _weeksRemaining = weeksRemaining;
            });
            widget.onGrowthData?.call(
              _rfAvailable ? _rfProjectedYield! : 0,
              shrimpHealth,
              plantHealth,
            );
          },
          onError: (error) {
            debugPrint('Growth indicators subscription error: $error');
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = 'Unable to load yield data. Please try again.';
            });
          },
        );
  }

  @override
  void dispose() {
    _growthSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _recalculateYield() async {
    setState(() => _isRecalculating = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isRecalculating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.sync, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Data is automatically updated in real time.",
                style: GoogleFonts.poppins(),
              ),
            ),
          ],
        ),
        backgroundColor: tealDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: teal))
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 56, color: textMuted),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          _growthSub?.cancel();
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _subscribeGrowthIndicators();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          "Try Again",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _recalculateYield,
                color: teal,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Expected Yield and Income",
                                  style: GoogleFonts.poppins(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Estimated harvest and income based on your records and current market prices.",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: textMuted,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isRecalculating
                                ? null
                                : _recalculateYield,
                            icon: _isRecalculating
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: teal,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color: tealDark,
                                    size: 28,
                                  ),
                            tooltip: 'Refresh data',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Main Yield & Revenue Highlight
                      _buildMainYieldAndRevenueCard(),
                      const SizedBox(height: 20),

                      // Progress Card
                      _buildSectionTitle(Icons.timelapse, "Growth Cycle"),
                      const SizedBox(height: 12),
                      _buildCycleProgressCard(),
                      const SizedBox(height: 24),

                      // Calculation Factors
                      _buildSectionTitle(Icons.calculate, "Estimation Factors"),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildFactorCard(
                            "Average Weight",
                            (_rfProjectedWeight != null &&
                                    _rfProjectedWeight! > 0)
                                ? "${_rfProjectedWeight!.toStringAsFixed(1)}g"
                                : "—",
                            Icons.scale,
                          ),
                          const SizedBox(width: 12),
                          _buildFactorCard(
                            "Survival Rate",
                            _survivalRate > 0
                                ? "${_survivalRate.toStringAsFixed(0)}%"
                                : "—",
                            Icons.health_and_safety,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Market Price Factor taking full width for emphasis
                      _buildFactorCard(
                        "Market Price Range (Min–Max)",
                        "₱${_priceMin.toStringAsFixed(0)}–₱${_priceMax.toStringAsFixed(0)} / kg",
                        Icons.storefront,
                        isFullWidth: true,
                      ),
                      const SizedBox(height: 24),

                      // Recommendation Section
                      _buildSectionTitle(
                        Icons.lightbulb,
                        "Status and Recommendations",
                      ),
                      const SizedBox(height: 12),
                      _buildRecommendationCard(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: tealDark),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textDark,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // Combined Yield and Revenue Card
  Widget _buildMainYieldAndRevenueCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tealDark, teal],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: tealDark.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Yield Section
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total Expected Yield",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _yieldBadgeText,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _yieldBigText,
                  style: GoogleFonts.poppins(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1.0,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _yieldSubText,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Target Harvest: ${_fmtDate(_targetHarvestDate)}",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(height: 1, color: Colors.white.withOpacity(0.2)),

          // Revenue Section
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.payments,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Expected Income (Gross Revenue)",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIncomeColumn(
                      "Min",
                      _incomeMin,
                      Colors.white.withOpacity(0.75),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    _buildIncomeColumn("Avg", _incomeAvg, Colors.white),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    _buildIncomeColumn(
                      "Max",
                      _incomeMax,
                      Colors.white.withOpacity(0.75),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Based on the market price of ₱${_priceMin.toStringAsFixed(0)}–₱${_priceMax.toStringAsFixed(0)} per kg",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleProgressCard() {
    final int totalDays = (_cycleStart != null && _cycleEnd != null)
        ? _cycleEnd!.difference(_cycleStart!).inDays.clamp(1, 9999)
        : 120;
    final int currentDay = _cycleStart != null
        ? DateTime.now().difference(_cycleStart!).inDays.clamp(0, totalDays)
        : 0;
    final double progress = currentDay / totalDays;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Day $currentDay of $totalDays",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tealDark,
                ),
              ),
              Text(
                "${(progress * 100).toInt()}%",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFF3F4F6),
              valueColor: AlwaysStoppedAnimation<Color>(teal),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtDate(_cycleStart),
                style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
              ),
              Text(
                _fmtDate(_cycleEnd),
                style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFactorCard(
    String label,
    String value,
    IconData icon, {
    bool isFullWidth = false,
  }) {
    Widget cardContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: seaBlue, size: 24),
              if (isFullWidth) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: textDark,
            ),
          ),
          if (!isFullWidth) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    return isFullWidth ? cardContent : Expanded(child: cardContent);
  }

  Widget _buildIncomeColumn(String label, double? amount, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount != null ? "₱${_formatIncome(amount)}" : "₱--",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatIncome(double amount) {
    if (amount >= 1000000) return "${(amount / 1000000).toStringAsFixed(1)}M";
    if (amount >= 1000) return "${(amount / 1000).toStringAsFixed(1)}K";
    return amount.toStringAsFixed(0);
  }

  Widget _buildRecommendationCard() {
    final note = _summaryNote.isNotEmpty
        ? _summaryNote
        : (_incomeAvg != null
              ? "Growth is progressing normally. Maintain regular feeding to reach or exceed the estimated average income of ₱${_formatIncome(_incomeAvg!)}."
              : "Growth is progressing normally. Maintain regular feeding until the yield prediction becomes available.");

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tealLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: teal.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.check_circle, color: tealDark, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "On Track",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tealDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  note,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: textDark.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
