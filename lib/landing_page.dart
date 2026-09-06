import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tasks.dart';
import 'yield.dart';
import 'logs.dart';
import 'profile.dart';
import 'notification_service.dart';

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
  final List<int> _navHistory = [];
  bool _showNotificationDropdown = false;
  final ValueNotifier<bool> _isNavBarVisible = ValueNotifier(true);
  late AnimationController _fadeController;

  // Live data from sensor_readings
  double? _waterTemp;
  double? _phLevel;
  double? _dissolvedOxygen;
  double? _salinity;
  double? _turbidity;
  double? _waterLevel;

  // pH threshold configuration (user-defined per farm)
  double _phMin = 6.8;
  double _phMax = 8.0;

  // Live data from growth_indicators (populated via YieldEstimationPage callback)
  double? _expectedYield;
  String _shrimpHealth = 'Malusog';
  String _plantHealth = 'Maayos';

  // Live data from alerts
  List<Map<String, dynamic>> _activeAlerts = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  Set<String> _seenNotificationKeys = <String>{};

  // Default alerts matching the prototype in Image 2
  final List<Map<String, dynamic>> _defaultAlerts = [
    {
      'id': 'alert-ph',
      'title': 'Babala',
      'priority': 'URGENT',
      'message':
          'pH Level is above the safe range. Current: 6.98. Safe range: 6.5 – 6.8. Add acid buffer or increase water change frequency.',
    },
    {
      'id': 'alert-do',
      'title': 'Babala',
      'priority': 'URGENT',
      'message':
          'Dissolved Oxygen is below the safe range. Current: 6.73 mg/L. Safe range: > 8 mg/L. Increase aeration immediately. Inspect air pump and diffusers.',
    },
  ];

  List<Map<String, dynamic>> get _displayAlerts =>
      _activeAlerts.isNotEmpty ? _activeAlerts : _defaultAlerts;

  // Profile
  String _initials = 'JS';

  // Firestore subscriptions
  StreamSubscription<QuerySnapshot>? _sensorSub;
  StreamSubscription<QuerySnapshot>? _alertsSub;
  StreamSubscription<QuerySnapshot>? _tasksSub;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _seenNotificationKeys = NotificationService.instance
        .getSeenNotificationKeys();
    _subscribeSensorReadings();
    _subscribeAlerts();
    _subscribeTasks();
    _loadUserInitials();
    _loadPhThresholds();
  }

  void _subscribeSensorReadings() {
    _sensorSub = FirebaseFirestore.instance
        .collection('sensor_readings')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
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
          },
          onError: (error) =>
              debugPrint('Sensor readings subscription error: $error'),
        );
  }

  void _subscribeAlerts() {
    _alertsSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) {
              _seenNotificationKeys.remove('alert:${change.doc.id}');
              unawaited(
                NotificationService.instance.resolveNotification(
                  'alert:${change.doc.id}',
                ),
              );
              continue;
            }
            if (change.type != DocumentChangeType.added) continue;
            final alert = change.doc.data() as Map<String, dynamic>;
            final title = (alert['title'] as String?) ?? 'Bagong Abiso';
            final message = (alert['message'] as String?) ?? '';
            final priority = ((alert['priority'] as String?) ?? '')
                .toUpperCase();
            unawaited(
              NotificationService.instance.showAlert(
                id: change.doc.id,
                title: title,
                message: message,
                isUrgent: priority == 'HIGH' || priority == 'URGENT',
              ),
            );
          }
          setState(() {
            _activeAlerts = snapshot.docs.map((doc) {
              return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
            }).toList();
          });
        }, onError: (error) => debugPrint('Alerts subscription error: $error'));
  }

  void _subscribeTasks() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _tasksSub = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            _pendingTasks = snapshot.docs
                .map(
                  (doc) => {
                    'id': doc.id,
                    ...doc.data() as Map<String, dynamic>,
                  },
                )
                .where((task) => task['status'] == 'pending')
                .toList();
          });
        }, onError: (error) => debugPrint('Tasks subscription error: $error'));
  }

  Future<void> _loadUserInitials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final fullName = (doc.data()?['fullName'] as String?) ?? '';
      if (fullName.isEmpty) return;
      final parts = fullName.trim().split(' ');
      final initials = parts.length == 1
          ? parts[0][0].toUpperCase()
          : '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
      setState(() => _initials = initials);
    } catch (e) {
      debugPrint('Failed to load user initials: $e');
    }
  }

  Future<void> _loadPhThresholds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // Try to load from user's farm settings
      // First, get the user's farm reference
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final farmId = userDoc.data()?['farmId'] as String?;
      
      if (farmId == null) {
        debugPrint('No farm ID found for user');
        return;
      }

      // Load water parameters settings for the farm
      final settingsDoc = await FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('settings')
          .doc('waterParameters')
          .get();

      if (!mounted) return;

      if (settingsDoc.exists) {
        final data = settingsDoc.data() as Map<String, dynamic>;
        setState(() {
          _phMin = (data['phMin'] as num?)?.toDouble() ?? 6.8;
          _phMax = (data['phMax'] as num?)?.toDouble() ?? 8.0;
        });
      }
    } catch (e) {
      debugPrint('Failed to load pH thresholds: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sensorSub?.cancel();
    _alertsSub?.cancel();
    _tasksSub?.cancel();
    _isNavBarVisible.dispose();
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
    if (_waterTemp! < 24)
      return 'Mababa ang temperatura. Maaaring makaapekto sa ulang.';
    if (_waterTemp! > 30)
      return 'Mataas ang temperatura. Bantayan ang mga ulang.';
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
    if (_turbidity! > 50)
      return 'Katamtamang kalinisan ng tubig. Bantayan pa rin.';
    return 'Malinis ang tubig. Walang nakitang lason o dumi.';
  }

  Color get _turbidityColor {
    if (_turbidity == null) return textMuted;
    if (_turbidity! > 100) return warningRed;
    if (_turbidity! > 50) return const Color(0xFFF59E0B);
    return teal;
  }

  String get _phStatus {
    if (_phLevel == null) return 'WALANG DATA';
    if (_phLevel! < _phMin || _phLevel! > _phMax) return 'BABALA';
    return 'NORMAL';
  }

  String get _phDescription {
    if (_phLevel == null) return 'Walang datos mula sa sensor.';
    if (_phLevel! < _phMin) {
      return 'Mababa ang pH level. Ang tubig ay masyadong asido para sa mga ulang.';
    }
    if (_phLevel! > _phMax) {
      return 'Mataas ang pH level. Ang tubig ay masyadong alkaline para sa mga ulang.';
    }
    return 'Tamang-tama ang pH level para sa kalusugan ng mga ulang at tanim.';
  }

  Color get _phColor {
    if (_phLevel == null) return textMuted;
    if (_phLevel! < _phMin || _phLevel! > _phMax) return warningRed;
    return teal;
  }

  bool get _hasAlerts => _displayAlerts.isNotEmpty;
  int get _notificationCount {
    final alerts = _displayAlerts;
    final unread = alerts.where((alert) {
      return !_seenNotificationKeys.contains('alert:${alert['id']}');
    }).length;
    return _pendingTasks.length + (unread > 0 ? 1 : 0);
  }
  bool get _hasUnreadNotifications => _notificationCount > 0;

  void _toggleNotificationDropdown() {
    setState(() {
      _showNotificationDropdown = !_showNotificationDropdown;
    });
  }

  void _closeNotificationDropdown() {
    if (!_showNotificationDropdown) return;
    setState(() => _showNotificationDropdown = false);
  }

  void _acknowledgeAlert(String id) {
    final key = 'alert:$id';
    if (_seenNotificationKeys.contains(key)) return;
    setState(() => _seenNotificationKeys.add(key));
    unawaited(NotificationService.instance.markNotificationsSeen([key]));
    unawaited(NotificationService.instance.cancelNotification(key));
  }

  String get _systemStatusTitle =>
      _hasAlerts ? 'May Babala' : 'Mabuti ang Kalagayan';

  String get _systemStatusDescription {
    if (_hasAlerts) {
      return (_displayAlerts.first['message'] as String?) ??
          'May aktibong babala. Suriin ang sistema agad.';
    }
    return 'Ligtas ang tubig at masigla ang mga ulang at tanim.';
  }

  String get _yieldDisplay => _expectedYield != null
      ? '${_expectedYield!.toStringAsFixed(0)} kg'
      : '2 kg';

  // ── BUILD ──────────────────────────────────────────────────────────────

  void _onNavTapped(int index) {
    if (index == _currentNavIndex) return;
    setState(() {
      _navHistory.add(_currentNavIndex);
      _currentNavIndex = index;
    });
    _isNavBarVisible.value = true;
  }

  bool get _canPopDashboard =>
      _showNotificationDropdown || _navHistory.isNotEmpty;

  void _handleDashboardBack() {
    if (_showNotificationDropdown) {
      _closeNotificationDropdown();
      return;
    }
    if (_navHistory.isEmpty) return;
    setState(() {
      _currentNavIndex = _navHistory.removeLast();
    });
    _isNavBarVisible.value = true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_canPopDashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleDashboardBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        extendBody: true,
        appBar: _buildTopBar(context),
        body: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification.depth != 0) return false;
            if (notification is UserScrollNotification) {
              if (notification.direction == ScrollDirection.reverse) {
                if (_isNavBarVisible.value) _isNavBarVisible.value = false;
              } else if (notification.direction == ScrollDirection.forward) {
                if (!_isNavBarVisible.value) _isNavBarVisible.value = true;
              }
            }
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 20) {
              if (!_isNavBarVisible.value) _isNavBarVisible.value = true;
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
                  YieldEstimationPage(
                    onGrowthData: (expectedYield, shrimpHealth, plantHealth) {
                      if (!mounted) return;
                      setState(() {
                        _expectedYield = expectedYield;
                        _shrimpHealth = shrimpHealth;
                        _plantHealth = plantHealth;
                      });
                    },
                  ),
                  const LogsPage(),
                ],
              ),
              if (_showNotificationDropdown)
                Positioned(
                  top: 0,
                  right: 12,
                  child: TapRegion(
                    groupId: 'notification-dropdown',
                    child: _buildNotificationDropdown(),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _isNavBarVisible,
          builder: (context, isNavBarVisible, child) {
            return AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              offset: isNavBarVisible ? Offset.zero : const Offset(0, 1.0),
              child: child,
            );
          },
          child: _buildBottomNavBar(),
        ),
      ),
    );
  }

  // ── DASHBOARD TAB CONTENT ──────────────────────────────────────────────

  Widget _buildDashboardView() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: FadeTransition(
        opacity: Tween<double>(
          begin: 0,
          end: 1,
        ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreetingHeader(),
              const SizedBox(height: 18),
              // KPI cards with "Kasalukuyang Kondisyon" header at top of dashboard
              _buildMiniParameterGrid(),
              const SizedBox(height: 24),
              // Babala warning notifications
              _buildUrgentTasksSection(),
              const SizedBox(height: 16),
              // Additional condition metrics
              _buildAdditionalParametersSection(),
            ],
          ),
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
          border: const Border(
            bottom: BorderSide(
              color: Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
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

                // Bell icon — badge includes water alerts and assigned tasks.
                TapRegion(
                  groupId: 'notification-dropdown',
                  onTapOutside: (_) => _closeNotificationDropdown(),
                  child: SizedBox(
                    width: 52,
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: IconButton(
                            tooltip: 'Mga abiso at gawain',
                            icon: Icon(
                              Icons.notifications_none,
                              color: textDark,
                              size: 28,
                            ),
                            onPressed: _toggleNotificationDropdown,
                          ),
                        ),
                        if (_hasUnreadNotifications)
                          Positioned(
                            top: 3,
                            right: 4,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              height: 18,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: warningRed,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _notificationCount > 9
                                      ? '9+'
                                      : '$_notificationCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: teal, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        _initials,
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
    final combined = <Map<String, dynamic>>[
      ..._activeAlerts.map((alert) => {...alert, '_kind': 'alert'}),
      ..._pendingTasks.map((task) => {...task, '_kind': 'task'}),
    ];
    combined.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
        aTs?.millisecondsSinceEpoch ?? 0,
      );
    });
    final displayed = combined;

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
              "Mga Abiso at Gawain",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            if (displayed.isEmpty)
              Text(
                "Walang bagong abiso o nakatalagang gawain.",
                style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Scrollbar(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: displayed.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, i) {
                      final alert = displayed[i];
                      final String title =
                          (alert['title'] as String?) ?? 'Abiso';
                      final bool isTask = alert['_kind'] == 'task';
                      final String message = isTask
                          ? ((alert['description'] as String?) ??
                                'May bagong nakatalagang gawain.')
                          : ((alert['message'] as String?) ?? '');
                      final String prio = ((alert['priority'] as String?) ?? '')
                          .toUpperCase();
                      final bool isHigh = prio == 'HIGH' || prio == 'URGENT';
                      return InkWell(
                        onTap: isTask
                            ? () {
                                setState(
                                  () => _showNotificationDropdown = false,
                                );
                                _onNavTapped(1);
                              }
                            : () => _acknowledgeAlert(alert['id'] as String),
                        child: _buildNotifItem(
                          isTask
                              ? Icons.assignment_outlined
                              : (isHigh
                                    ? Icons.assignment_late
                                    : Icons.water_drop),
                          title,
                          message,
                          isTask
                              ? const Color(0xFF0369A1)
                              : (isHigh ? warningRed : teal),
                        ),
                      );
                    },
                  ),
                ),
              ),
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
                style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── GREETING HEADER ────────────────────────────────────────────────────

  Widget _buildGreetingHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Magandang Araw!",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Narito ang buod ng iyong Bantay Ulang system ngayon.",
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ── 2-COLUMN KEY METRIC MINI-PARAMETER GRID (WITH KASALUKUYANG KONDISYON HEADER) ─

  Widget _buildMiniParameterGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: tealDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Kasalukuyang Kondisyon",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Row 1: Inaasahang Ani & pH Level
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildHarvestMiniCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildPHMiniCard()),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Row 2: Dissolved Oxygen & Temperatura
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildOxygenMiniCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildTempMiniCard()),
            ],
          ),
        ),
      ],
    );
  }

  // ── URGENT TASKS / NOTIFICATIONS (IMAGE 2 BANTAY ULANG STYLE) ──────────

  Widget _buildUrgentTasksSection() {
    final alerts = _displayAlerts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alerts.map((alert) {
        final String title = (alert['title'] as String?) ?? 'Babala';
        final String message = (alert['message'] as String?) ?? '';
        final String priority =
            ((alert['priority'] as String?) ?? 'URGENT').toUpperCase();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFECACA),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Warning icon container matching original theme
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        priority,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF475569),
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentNavIndex = 1;
                    });
                    _isNavBarVisible.value = true;
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    "Tingnan ang gawain →",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tealDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Card 1: Inaasahang Ani
  Widget _buildHarvestMiniCard() {
    final yieldVal = _yieldDisplay;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFE6F4F1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.shopping_basket_rounded,
                    size: 17,
                    color: teal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Inaasahang Ani",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            yieldVal,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: tealDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Base sa kasalukuyang kondisyon at dami ng ulang.",
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: const Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // Card 2: pH Level
  Widget _buildPHMiniCard() {
    final phVal = _phLevel != null ? _phLevel!.toStringAsFixed(1) : '7.0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.water_drop_rounded,
                    size: 17,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "pH Level",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            phVal,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: _phColor == warningRed
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _phColor == warningRed
                    ? const Color(0xFFEF4444).withOpacity(0.35)
                    : const Color(0xFF10B981).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Text(
              _phStatus == 'WALANG DATA' ? "NORMAL" : _phStatus,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _phColor == warningRed
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card 3: Dissolved Oxygen
  Widget _buildOxygenMiniCard() {
    final oxygenVal =
        _dissolvedOxygen != null ? _dissolvedOxygen!.toStringAsFixed(1) : '7.0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.air_rounded,
                    size: 17,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Dissolved Oxygen",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            oxygenVal,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: _oxygenColor == warningRed
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _oxygenColor == warningRed
                    ? const Color(0xFFEF4444).withOpacity(0.35)
                    : const Color(0xFF10B981).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Text(
              _oxygenStatus == 'WALANG DATA'
                  ? "NORMAL"
                  : (_oxygenStatus == 'SAPAT' ? "NORMAL" : _oxygenStatus),
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _oxygenColor == warningRed
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card 4: Temperatura ng Tubig
  Widget _buildTempMiniCard() {
    final tempVal =
        _waterTemp != null ? '${_waterTemp!.toStringAsFixed(1)}°C' : '50.0°C';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.thermostat_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Kondisyon ng Tubig",
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "Temperatura",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tempVal,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFDC2626),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _waterTemp == null ? "Mataas ang temperatura." : _tempDescription,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: _tempColor == textMuted ? const Color(0xFFDC2626) : _tempColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Text(
              _tempStatus == 'WALANG DATA' ? "MATAAS" : _tempStatus,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _tempColor == textMuted ? const Color(0xFFDC2626) : _tempColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ADDITIONAL PARAMETERS SECTION ──────────────────────────────────────

  Widget _buildAdditionalParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Iba Pang Kondisyon",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildConditionCard(
          Icons.water_drop_outlined,
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
          Icons.eco_outlined,
          "Mga Halaman",
          "Malusog at patuloy na lumalaki.",
          _plantHealth.toUpperCase(),
          const Color(0xFF10B981),
        ),
      ],
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: themeColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
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
                const SizedBox(height: 3),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.12),
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
