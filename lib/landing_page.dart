import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tasks.dart';
import 'yield.dart';
import 'logs.dart';
import 'profile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final Color tealLight = const Color(0xFFE6FFF9);
  final Color teal = const Color(0xFF0D9488);
  final Color tealDark = const Color(0xFF0F766E);
  final Color deepsea = const Color(0xFF001F3F);
  final Color warningRed = const Color(0xFFDC2626);
  final Color textDark = const Color(0xFF1F2937);
  final Color textMuted = const Color(0xFF6B7280);

  int _currentNavIndex = 0;
  bool _showNotificationDropdown = false;
  bool _isNavBarVisible = true;
  late AnimationController _fadeController;

  // Live data from sensor_readings
  double? _waterTemp;
  double? _phLevel;
  double? _dissolvedOxygen;
  double? _salinity;
  double? _turbidity;
  double? _waterLevel;

  // Live data from growth_indicators
  double? _expectedYield;
  String _shrimpHealth = 'Malusog';
  String _plantHealth = 'Maayos';

  // Live data from alerts
  List<Map<String, dynamic>> _activeAlerts = [];

  // Firestore subscriptions
  StreamSubscription<QuerySnapshot>? _sensorSub;
  StreamSubscription<QuerySnapshot>? _growthSub;
  StreamSubscription<QuerySnapshot>? _alertsSub;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _subscribeSensorReadings();
    _subscribeGrowthIndicators();
    _subscribeAlerts();
  }

  void _subscribeSensorReadings() {
    _sensorSub = FirebaseFirestore.instance
        .collection('sensor_readings')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;
      final data = snapshot.docs.first.data() as Map<String, dynamic>;
      setState(() {
        _waterTemp = (data['waterTemp'] as num?)?.toDouble();
        _phLevel = (data['phLevel'] as num?)?.toDouble();
        _dissolvedOxygen = (data['dissolvedOxygen'] as num?)?.toDouble();
        _salinity = (data['salinity'] as num?)?.toDouble();
        _turbidity = (data['turbidity'] as num?)?.toDouble();
        _waterLevel = (data['waterLevel'] as num?)?.toDouble();
      });
    });
  }

  void _subscribeGrowthIndicators() {
    _growthSub = FirebaseFirestore.instance
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;
      final data = snapshot.docs.first.data() as Map<String, dynamic>;
      setState(() {
        _expectedYield = (data['expectedYield'] as num?)?.toDouble();
        _shrimpHealth = (data['shrimpHealth'] as String?) ?? 'Malusog';
        _plantHealth = (data['plantHealth'] as String?) ?? 'Maayos';
      });
    });
  }

  void _subscribeAlerts() {
    _alertsSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _activeAlerts = snapshot.docs.map((doc) {
          return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sensorSub?.cancel();
    _growthSub?.cancel();
    _alertsSub?.cancel();
    super.dispose();
  }

  // ── Derived status from sensor values ─────────────────────────────────

  String get _tempStatus {
    if (_waterTemp == null) return 'WALANG DATA';
    if (_waterTemp! < 24) return 'MABABA';
    if (_waterTemp! > 30) return 'MATAAS';
    return 'KATAMTAMAN';
  }

  String get _tempDescription {
    if (_waterTemp == null) return 'Walang datos mula sa sensor.';
    if (_waterTemp! < 24) return 'Mababa ang temperatura. Maaaring makaapekto sa ulang.';
    if (_waterTemp! > 30) return 'Mataas ang temperatura. Bantayan ang mga ulang.';
    return 'Tamang-tama ang temperatura para sa paglaki ng ulang.';
  }

  Color get _tempColor {
    if (_waterTemp == null) return textMuted;
    if (_waterTemp! < 24 || _waterTemp! > 30) return warningRed;
    return teal;
  }

  String get _oxygenStatus {
    if (_dissolvedOxygen == null) return 'WALANG DATA';
    if (_dissolvedOxygen! < 5.0) return 'MABABA';
    return 'SAPAT';
  }

  String get _oxygenDescription {
    if (_dissolvedOxygen == null) return 'Walang datos mula sa sensor.';
    if (_dissolvedOxygen! < 5.0) {
      return 'Mababa ang dissolved oxygen. Suriin ang sistema ng aeration.';
    }
    return 'May sapat na hangin para sa mga ulang.';
  }

  Color get _oxygenColor {
    if (_dissolvedOxygen == null) return textMuted;
    if (_dissolvedOxygen! < 5.0) return warningRed;
    return teal;
  }

  String get _turbidityStatus {
    if (_turbidity == null) return 'WALANG DATA';
    if (_turbidity! > 100) return 'MALABO';
    if (_turbidity! > 50) return 'KATAMTAMAN';
    return 'MALINAW';
  }

  String get _turbidityDescription {
    if (_turbidity == null) return 'Walang datos mula sa sensor.';
    if (_turbidity! > 100) return 'Malabo ang tubig. Kailangang linisin.';
    if (_turbidity! > 50) return 'Katamtamang kalinisan ng tubig. Bantayan pa rin.';
    return 'Malinis ang tubig. Walang nakitang lason o dumi.';
  }

  Color get _turbidityColor {
    if (_turbidity == null) return textMuted;
    if (_turbidity! > 100) return warningRed;
    if (_turbidity! > 50) return const Color(0xFFF59E0B);
    return teal;
  }

  bool get _hasAlerts => _activeAlerts.isNotEmpty;

  String get _systemStatusTitle =>
      _hasAlerts ? 'May Babala' : 'Mabuti ang Kalagayan';

  String get _systemStatusDescription {
    if (_hasAlerts) {
      return (_activeAlerts.first['message'] as String?) ??
          'May aktibong babala. Suriin ang sistema agad.';
    }
    return 'Ligtas ang tubig at masigla ang mga ulang at tanim.';
  }

  String get _yieldDisplay =>
      _expectedYield != null ? '${_expectedYield!.toStringAsFixed(0)} kg' : '--';

  // ── BUILD ──────────────────────────────────────────────────────────────

  void _onNavTapped(int index) {
    if (index == _currentNavIndex) return;
    setState(() {
      _currentNavIndex = index;
      _isNavBarVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      extendBody: true,
      appBar: _buildTopBar(context),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification is UserScrollNotification) {
            if (notification.direction == ScrollDirection.reverse) {
              if (_isNavBarVisible) setState(() => _isNavBarVisible = false);
            } else if (notification.direction == ScrollDirection.forward) {
              if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
            }
          }
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 20) {
            if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
          }
          return false;
        },
        child: Stack(
          children: [
            IndexedStack(
              index: _currentNavIndex,
              children: [
                _buildDashboardView(),
                const TasksPage(),
                const YieldEstimationPage(),
                const LogsPage(),
              ],
            ),
            if (_showNotificationDropdown)
              Positioned(
                top: 0,
                right: 12,
                child: _buildNotificationDropdown(),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        offset: _isNavBarVisible ? Offset.zero : const Offset(0, 1.0),
        child: _buildBottomNavBar(),
      ),
    );
  }

  // ── DASHBOARD TAB CONTENT ──────────────────────────────────────────────

  Widget _buildDashboardView() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Magandang Araw!",
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Narito ang buod ng iyong Bantay Ulang system ngayon.",
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),

            _buildStatusCard(),
            const SizedBox(height: 24),

            _buildUrgentTasksSection(),
            const SizedBox(height: 24),

            _buildYieldSection(),
            const SizedBox(height: 24),

            Text(
              "Kondisyon ng Tubig",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildConditionCard(
              Icons.thermostat,
              "Temperatura",
              _tempDescription,
              _tempStatus,
              _tempColor,
              value: _waterTemp != null
                  ? '${_waterTemp!.toStringAsFixed(1)}°C'
                  : null,
            ),
            const SizedBox(height: 12),
            _buildConditionCard(
              Icons.water_drop,
              "Linis ng Tubig",
              _turbidityDescription,
              _turbidityStatus,
              _turbidityColor,
              value: _turbidity != null
                  ? '${_turbidity!.toStringAsFixed(0)} NTU'
                  : null,
            ),
            const SizedBox(height: 12),
            _buildConditionCard(
              Icons.air,
              "Hangin (Oxygen)",
              _oxygenDescription,
              _oxygenStatus,
              _oxygenColor,
              value: _dissolvedOxygen != null
                  ? '${_dissolvedOxygen!.toStringAsFixed(1)} mg/L'
                  : null,
            ),
            const SizedBox(height: 24),

            Text(
              "Status ng mga Tanim",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildConditionCard(
              Icons.eco,
              "Mga Halaman",
              "Malusog at patuloy na lumalaki.",
              _plantHealth.toUpperCase(),
              const Color(0xFF10B981),
            ),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(65),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tealLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: teal, width: 1.5),
                  ),
                  child: Icon(Icons.water_drop, color: tealDark, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Bantay Ulang",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: tealDark,
                    ),
                  ),
                ),

                // Bell icon — badge appears only when there are active alerts
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_none,
                        color: textDark,
                        size: 28,
                      ),
                      onPressed: () {
                        setState(() {
                          _showNotificationDropdown =
                              !_showNotificationDropdown;
                        });
                      },
                    ),
                    if (_hasAlerts)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: warningRed,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),

                // Profile Avatar
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfilePage(),
                      ),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: tealLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: teal, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        "JD",
                        style: TextStyle(
                          color: tealDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── BOTTOM NAV BAR ─────────────────────────────────────────────────────

  Widget _buildBottomNavBar() {
    const navItems = [
      (Icons.home_rounded, Icons.home_outlined, "Dashboard"),
      (Icons.assignment_turned_in_rounded, Icons.assignment_outlined, "Gawain"),
      (Icons.show_chart_rounded, Icons.show_chart_outlined, "Ani"),
      (Icons.list_alt_rounded, Icons.list_alt_outlined, "Logs"),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (i) {
              final isActive = i == _currentNavIndex;
              final (activeIcon, inactiveIcon, label) = navItems[i];
              return _buildNavItem(
                activeIcon: activeIcon,
                inactiveIcon: inactiveIcon,
                label: label,
                isActive: isActive,
                onTap: () => _onNavTapped(i),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? tealLight : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              color: isActive ? tealDark : textMuted,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? tealDark : textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── NOTIFICATION DROPDOWN ──────────────────────────────────────────────

  Widget _buildNotificationDropdown() {
    final displayed = _activeAlerts.take(5).toList();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Mga Abiso",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            if (displayed.isEmpty)
              Text(
                "Walang aktibong abiso.",
                style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
              )
            else
              ...List.generate(displayed.length, (i) {
                final alert = displayed[i];
                final String title = (alert['title'] as String?) ?? 'Abiso';
                final String message = (alert['message'] as String?) ?? '';
                final String prio =
                    ((alert['priority'] as String?) ?? '').toUpperCase();
                final bool isHigh = prio == 'HIGH' || prio == 'URGENT';
                return Column(
                  children: [
                    _buildNotifItem(
                      isHigh ? Icons.assignment_late : Icons.water_drop,
                      title,
                      message,
                      isHigh ? warningRed : teal,
                    ),
                    if (i < displayed.length - 1) const Divider(height: 16),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotifItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textDark,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── CONTENT WIDGETS ────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    final cardColor = _hasAlerts ? warningRed : tealDark;
    final statusIcon =
        _hasAlerts ? Icons.warning_amber_rounded : Icons.check_circle;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: cardColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _systemStatusTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _systemStatusDescription,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatusSubcard("Laki ng Ulang", _shrimpHealth),
              const SizedBox(width: 16),
              _buildStatusSubcard("Dami ng Tanim", _plantHealth),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSubcard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.8),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgentTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _hasAlerts ? Icons.assignment_late : Icons.assignment_turned_in,
              color: _hasAlerts ? warningRed : teal,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              "Mahahalagang Gawain",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            if (_hasAlerts) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: warningRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_activeAlerts.length}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (!_hasAlerts)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: teal.withOpacity(0.3), width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: teal, size: 20),
                const SizedBox(width: 12),
                Text(
                  "Walang mahahalagang gawain ngayon.",
                  style: GoogleFonts.poppins(fontSize: 14, color: textMuted),
                ),
              ],
            ),
          )
        else
          Column(
            children: _activeAlerts.map((alert) {
              final String title = (alert['title'] as String?) ?? 'Babala';
              final String message = (alert['message'] as String?) ?? '';
              final String priority =
                  ((alert['priority'] as String?) ?? 'URGENT').toUpperCase();
              final bool isHigh =
                  priority == 'HIGH' || priority == 'URGENT';
              final Color alertColor =
                  isHigh ? warningRed : const Color(0xFFF59E0B);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: alertColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: alertColor.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: alertColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.warning_amber_rounded,
                            color: alertColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: alertColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    priority,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: textMuted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _currentNavIndex = 1;
                                  _isNavBarVisible = true;
                                });
                              },
                              child: Text(
                                "Tingnan ang gawain →",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildYieldSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tealLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.scale, color: tealDark, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                "Inaasahang Ani",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _yieldDisplay,
            style: GoogleFonts.poppins(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: tealDark,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Base sa kasalukuyang kondisyon at dami ng ulang.",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionCard(
    IconData icon,
    String title,
    String description,
    String status,
    Color themeColor, {
    String? value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: themeColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        value,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: themeColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
