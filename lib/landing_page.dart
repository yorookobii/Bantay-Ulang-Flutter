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
import 'offline/offline_services.dart';
import 'offline/offline_widgets.dart';
import 'offline/session_controller.dart';
import 'phone_back_logout.dart';
import 'water_parameter_status.dart';
import 'water_parameter_badge.dart';

class DashboardPage extends StatefulWidget {
  final int initialIndex;
  const DashboardPage({super.key, this.initialIndex = 0});

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

  late int _currentNavIndex;
  final List<int> _navHistory = [];
  PhoneBackLogoutCoordinator? _phoneBackCoordinator;
  VoidCallback? _removeBackOverlayHandler;
  bool _showNotificationDropdown = false;
  final ValueNotifier<bool> _isNavBarVisible = ValueNotifier(true);
  Offset? _pointerDownPosition;
  DateTime? _pointerDownTime;
  late AnimationController _fadeController;

  final _cacheStatus = CacheStatus('dashboard');
  final _alertsCache = CacheStatus('alerts');
  final _summaryCache = CacheStatus('growth_indicators');
  final _tasksCache = CacheStatus('tasks');
  final _thresholdsCache = CacheStatus('water_parameter_thresholds');

  // Live data from Aquaponics/Ulang
  double? _waterTemp;
  double? _phLevel;
  double? _dissolvedOxygen;
  double? _salinity;
  double? _tds;
  double? _turbidity;
  DateTime? _sensorMeasuredAt;
  double? _waterLevel;
  double? get waterLevel => _waterLevel;

  // Same global Firebase configuration as the administrator's readings cards.
  var _waterThresholds = WaterParameterThresholds.fromFirestore(null);
  bool _thresholdsReady = false;
  int _thresholdsRevision = 0;

  // Live data from growth_indicators (populated via YieldEstimationPage callback)
  double? _expectedYield;
  String _shrimpHealth = 'Malusog';
  String _plantHealth = 'Maayos';

  // Live data from alerts
  List<Map<String, dynamic>> _activeAlerts = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  Set<String> _seenNotificationKeys = <String>{};

  List<Map<String, dynamic>> get _displayAlerts => _activeAlerts;

  // Profile
  String _initials = 'JS';

  // Firestore subscriptions
  StreamSubscription<DocumentSnapshot>? _sensorSub;
  StreamSubscription<QuerySnapshot>? _alertsSub;
  StreamSubscription<QuerySnapshot>? _tasksSub;
  StreamSubscription<QuerySnapshot>? _growthSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _thresholdsSub;

  @override
  void initState() {
    super.initState();
    _currentNavIndex = widget.initialIndex;
    if (NotificationService.instance.consumePendingNavigationToTasks()) {
      _currentNavIndex = 1;
    }
    NotificationService.instance.onNavigateToTasks = _navigateToTasksTab;
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _seenNotificationKeys = NotificationService.instance
        .getSeenNotificationKeys();
    _subscribeSensorReadings();
    _subscribeAlerts();
    _subscribeTasks();
    _subscribeGrowthIndicators();
    _loadUserInitials();
    _subscribeWaterParameterThresholds();
  }

  void _navigateToTasksTab() {
    if (!mounted || !_cacheStatus.isCurrent) return;
    _closeNotificationDropdown();
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.popUntil(
        (route) => route.isFirst || route.settings.name == '/dashboard',
      );
    }
    _onNavTapped(1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = PhoneBackLogoutScope.maybeOf(context);
    if (identical(coordinator, _phoneBackCoordinator)) return;
    _removeBackOverlayHandler?.call();
    _phoneBackCoordinator = coordinator;
    _removeBackOverlayHandler = coordinator?.registerOverlayDismissal(() {
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_showNotificationDropdown) {
        return false;
      }
      _closeNotificationDropdown();
      return true;
    });
  }

  void _subscribeSensorReadings() {
    // Reads the live Aquaponics/Ulang doc (ESP32-updated), nested
    // statistics.*.average paths — mirrors the web's normalizeAquaponicsReading
    // (aquaponicsReading.js:48-53) so mobile and web read the same source.
    _sensorSub = FirebaseFirestore.instance
        .collection('Aquaponics')
        .doc('Ulang')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) async {
            await _cacheStatus.loaded;
            if (!mounted || !_cacheStatus.isCurrent) return;
            if (!_cacheStatus.canUse(snapshot.metadata)) {
              _cacheStatus.observe(snapshot.metadata, hasData: false);
              return;
            }
            _cacheStatus.observe(snapshot.metadata, hasData: snapshot.exists);
            final data = snapshot.data() as Map<String, dynamic>?;
            final stats = data?['statistics'] as Map<String, dynamic>?;
            setState(() {
              _sensorMeasuredAt = _parseSensorMeasuredAt(data?['measuredAt']);
              _waterTemp = (stats?['waterTemperatureC']?['average'] as num?)?.toDouble();
              _phLevel = (stats?['phValue']?['average'] as num?)?.toDouble();
              _dissolvedOxygen = (stats?['oxygenLevelMgL']?['average'] as num?)?.toDouble();
              _salinity = (stats?['salinityPpt']?['average'] as num?)?.toDouble();
              _tds = (stats?['tdsPpm']?['average'] as num?)?.toDouble();
              _turbidity = (stats?['turbidityNTU']?['average'] as num?)?.toDouble();
            });
          },
          onError: (error) {
            _cacheStatus.reportError(error);
            debugPrint('Sensor readings subscription error: $error');
          },
        );
  }

  // Match the admin's measuredAt source; never substitute the fetch time.
  DateTime? _parseSensorMeasuredAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    final milliseconds = value is num
        ? value
        : value is Map && value['seconds'] is num
            ? (value['seconds'] as num) * 1000
            : null;
    if (milliseconds == null || !milliseconds.isFinite) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds.round(),
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  String get _sensorReadingTime {
    final measuredAt = _sensorMeasuredAt?.toLocal();
    if (measuredAt == null) return '--';
    final hour = measuredAt.hour % 12 == 0 ? 12 : measuredAt.hour % 12;
    final minute = measuredAt.minute.toString().padLeft(2, '0');
    final period = measuredAt.hour < 12 ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  void _subscribeAlerts() {
    _alertsSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('status', isEqualTo: 'active')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          await _alertsCache.loaded;
          if (!mounted || !_cacheStatus.isCurrent) return;
          final usable = _alertsCache.canUse(snapshot.metadata);
          _alertsCache.observe(snapshot.metadata, hasData: usable && snapshot.docs.isNotEmpty);
          if (!usable) return;
          for (final change in snapshot.docChanges) {
            if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) continue;
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
        }, onError: (error) {
            _cacheStatus.reportError(error);
            debugPrint('Alerts subscription error: $error');
          });
  }

  void _subscribeTasks() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _tasksSub = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          if (!mounted || !_cacheStatus.isCurrent) return;
          _tasksCache.observe(snapshot.metadata, hasData: snapshot.docs.isNotEmpty);
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
        }, onError: (error) {
            _cacheStatus.reportError(error);
            debugPrint('Tasks subscription error: $error');
          });
  }

  void _subscribeGrowthIndicators() {
    _growthSub = FirebaseFirestore.instance
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) async {
            await _summaryCache.loaded;
            if (!mounted || !_cacheStatus.isCurrent) return;
            final usable = _summaryCache.canUse(snapshot.metadata);
            _summaryCache.observe(snapshot.metadata, hasData: usable && snapshot.docs.isNotEmpty);
            if (!usable) return;
            if (snapshot.docs.isEmpty) return;
            final data = snapshot.docs.first.data() as Map<String, dynamic>;
            final rfYield = (data['rfProjectedYield'] as num?)?.toDouble() ??
                (data['expectedYield'] as num?)?.toDouble();
            final sHealth = (data['shrimpHealth'] as String?) ?? 'Malusog';
            final pHealth = (data['plantHealth'] as String?) ?? 'Maayos';
            setState(() {
              if (rfYield != null && rfYield > 0) {
                _expectedYield = rfYield;
              }
              _shrimpHealth = sHealth;
              _plantHealth = pHealth;
            });
          },
          onError: (error) {
            _cacheStatus.reportError(error);
            debugPrint('Growth indicators subscription error: $error');
          },
        );
  }

  Future<void> _refreshDashboardData() async {
    if (OfflineServices.current?.session.online == false) {
      _showDashboardRefreshMessage('Showing saved data. Connect to refresh.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    const serverOptions = GetOptions(source: Source.server);

    final sensorFuture = FirebaseFirestore.instance
        .collection('Aquaponics')
        .doc('Ulang')
        .get(serverOptions);
    final alertsFuture = FirebaseFirestore.instance
        .collection('alerts')
        .where('status', isEqualTo: 'active')
        .get(serverOptions);
    final growthFuture = FirebaseFirestore.instance
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get(serverOptions);
    final Future<QuerySnapshot<Map<String, dynamic>>?> tasksFuture = uid == null
        ? Future.value()
        : FirebaseFirestore.instance
              .collection('tasks')
              .where('assignedTo', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .get(serverOptions);

    try {
      final snapshots = await Future.wait<Object?>([
        sensorFuture,
        alertsFuture,
        growthFuture,
        tasksFuture,
      ]).timeout(const Duration(seconds: 10));
      if (!mounted || !_cacheStatus.isCurrent) return;

      final sensorSnapshot =
          snapshots[0] as DocumentSnapshot<Map<String, dynamic>>;
      _cacheStatus.observe(sensorSnapshot.metadata, hasData: sensorSnapshot.exists);
      final alertsSnapshot =
          snapshots[1] as QuerySnapshot<Map<String, dynamic>>;
      final growthSnapshot =
          snapshots[2] as QuerySnapshot<Map<String, dynamic>>;
      final tasksSnapshot =
          snapshots[3] as QuerySnapshot<Map<String, dynamic>>?;

      _alertsCache.observe(alertsSnapshot.metadata, hasData: alertsSnapshot.docs.isNotEmpty);
      _summaryCache.observe(growthSnapshot.metadata, hasData: growthSnapshot.docs.isNotEmpty);
      if (tasksSnapshot != null) _tasksCache.observe(tasksSnapshot.metadata, hasData: tasksSnapshot.docs.isNotEmpty);
      final sensorData = sensorSnapshot.data();
      final stats = sensorData?['statistics'] as Map<String, dynamic>?;
      final refreshedWaterTemp =
          (stats?['waterTemperatureC']?['average'] as num?)?.toDouble();
      final refreshedPh =
          (stats?['phValue']?['average'] as num?)?.toDouble();
      final refreshedDissolvedOxygen =
          (stats?['oxygenLevelMgL']?['average'] as num?)?.toDouble();
      final refreshedSalinity =
          (stats?['salinityPpt']?['average'] as num?)?.toDouble();
      final refreshedTds =
          (stats?['tdsPpm']?['average'] as num?)?.toDouble();
      final refreshedTurbidity =
          (stats?['turbidityNTU']?['average'] as num?)?.toDouble();
      final readingsChanged = refreshedWaterTemp != _waterTemp ||
          refreshedPh != _phLevel ||
          refreshedDissolvedOxygen != _dissolvedOxygen ||
          refreshedSalinity != _salinity ||
          refreshedTds != _tds ||
          refreshedTurbidity != _turbidity;
      final activeAlerts = alertsSnapshot.docs.map((doc) {
        return <String, dynamic>{'id': doc.id, ...doc.data()};
      }).toList();
      final pendingTasks = tasksSnapshot?.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .where((task) => task['status'] == 'pending')
              .toList() ??
          <Map<String, dynamic>>[];

      Map<String, dynamic>? growthData;
      if (growthSnapshot.docs.isNotEmpty) {
        growthData = growthSnapshot.docs.first.data();
      }

      setState(() {
        _sensorMeasuredAt = _parseSensorMeasuredAt(sensorData?['measuredAt']);
        _waterTemp = refreshedWaterTemp;
        _phLevel = refreshedPh;
        _dissolvedOxygen = refreshedDissolvedOxygen;
        _salinity = refreshedSalinity;
        _tds = refreshedTds;
        _turbidity = refreshedTurbidity;
        _activeAlerts = activeAlerts;
        _pendingTasks = pendingTasks;

        if (growthData != null) {
          final rfYield =
              (growthData['rfProjectedYield'] as num?)?.toDouble() ??
              (growthData['expectedYield'] as num?)?.toDouble();
          if (rfYield != null && rfYield > 0) {
            _expectedYield = rfYield;
          }
          _shrimpHealth =
              (growthData['shrimpHealth'] as String?) ?? 'Malusog';
          _plantHealth = (growthData['plantHealth'] as String?) ?? 'Maayos';
        }
      });

      await Future.wait([_loadUserInitials(), _loadWaterParameterThresholds()]);
      if (!mounted || !_cacheStatus.isCurrent) return;
      _showDashboardRefreshMessage(
        readingsChanged
            ? 'Dashboard refreshed with new sensor data.'
            : 'The data is up to date.',
      );
    } catch (error) {
      _cacheStatus.reportError(error);
      debugPrint('Dashboard refresh error: $error');
      _showDashboardRefreshMessage(
        isNetworkFailure(error)
            ? 'Showing saved data. Connect to refresh.'
            : 'Unable to refresh the dashboard. Please try again.',
        isError: true,
      );
    }
  }

  void _showDashboardRefreshMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted || !_cacheStatus.isCurrent) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? warningRed : tealDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _loadUserInitials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(GetOptions(source: OfflineServices.current?.session.online == false ? Source.cache : Source.serverAndCache));
      if (!mounted || !_cacheStatus.isCurrent) return;
      final fullName = (doc.data()?['fullName'] as String?) ?? '';
      if (fullName.isEmpty) return;
      final parts = fullName.trim().split(' ');
      final initials = parts.length == 1
          ? parts[0][0].toUpperCase()
          : '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
      setState(() => _initials = initials);
    } catch (e) {
      _cacheStatus.reportError(e);
      debugPrint('Failed to load user initials: $e');
    }
  }

  void _subscribeWaterParameterThresholds() {
    _thresholdsSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('thresholds')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          await _thresholdsCache.loaded;
          if (!mounted || !_thresholdsCache.isCurrent) return;
          if (!_thresholdsCache.canUse(snapshot.metadata)) return;
          _applyWaterParameterThresholds(snapshot);
        }, onError: _reportThresholdsError);
  }

  void _applyWaterParameterThresholds(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!mounted || !_thresholdsCache.isCurrent) return;
    _thresholdsCache.observe(snapshot.metadata, hasData: snapshot.exists);
    setState(() {
      _thresholdsRevision++;
      _waterThresholds = WaterParameterThresholds.fromFirestore(snapshot.data());
      _thresholdsReady = true;
    });
  }

  Future<void> _loadWaterParameterThresholds() async {
    final revision = _thresholdsRevision;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('thresholds')
          .get(GetOptions(source: OfflineServices.current?.session.online == false
              ? Source.cache : Source.server));
      await _thresholdsCache.loaded;
      if (revision != _thresholdsRevision) return;
      if (!_thresholdsCache.canUse(snapshot.metadata)) return;
      _applyWaterParameterThresholds(snapshot);
    } catch (error) {
      _reportThresholdsError(error);
    }
  }

  void _reportThresholdsError(Object error) {
    if (!mounted || !_thresholdsCache.isCurrent) return;
    _thresholdsCache.reportError(error);
    debugPrint('Water parameter thresholds error: $error');
    // Match the admin's default fallback only before any usable configuration.
    // A later connectivity failure retains the last confirmed thresholds.
    if (!_thresholdsReady && _thresholdsCache.isCurrent) {
      setState(() => _thresholdsReady = true);
    }
  }

  @override
  void dispose() {
    _removeBackOverlayHandler?.call();
    if (NotificationService.instance.onNavigateToTasks == _navigateToTasksTab) {
      NotificationService.instance.onNavigateToTasks = null;
    }
    _cacheStatus.dispose();
    _alertsCache.dispose();
    _summaryCache.dispose();
    _tasksCache.dispose();
    _thresholdsCache.dispose();
    _fadeController.dispose();
    _sensorSub?.cancel();
    _alertsSub?.cancel();
    _tasksSub?.cancel();
    _growthSub?.cancel();
    _thresholdsSub?.cancel();
    _isNavBarVisible.dispose();
    super.dispose();
  }

  // ── Derived status from sensor values ─────────────────────────────────

  WaterParameterStatus? _waterStatus(WaterParameter parameter, double? value) {
    if (value == null || !value.isFinite) return WaterParameterStatus.noData;
    if (!_thresholdsReady) return null;
    return _waterThresholds.classify(parameter, value);
  }

  int get _notificationCount => _pendingTasks.length;
  bool get _hasUnreadNotifications => _notificationCount > 0;

  void _toggleNotificationDropdown() {
    _phoneBackCoordinator?.reset();
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

  String get _yieldDisplay {
    if (_expectedYield != null && _expectedYield! > 0) {
      return '${_expectedYield!.toStringAsFixed(1)} kg';
    }
    if (_expectedYield != null) {
      return 'Pending';
    }
    return '--';
  }

  Color get _shrimpHealthColor {
    final h = _shrimpHealth.toLowerCase();
    if (h.contains('babala') || h.contains('panganib') || h.contains('delikado')) {
      return warningRed;
    }
    if (h.contains('katamtaman') || h.contains('bantayan')) {
      return const Color(0xFFD97706);
    }
    return const Color(0xFF059669);
  }

  Color get _shrimpHealthBg {
    final h = _shrimpHealth.toLowerCase();
    if (h.contains('babala') || h.contains('panganib') || h.contains('delikado')) {
      return const Color(0xFFFEE2E2);
    }
    if (h.contains('katamtaman') || h.contains('bantayan')) {
      return const Color(0xFFFEF3C7);
    }
    return const Color(0xFFECFDF5);
  }

  Color get _plantHealthColor {
    final h = _plantHealth.toLowerCase();
    if (h.contains('babala') || h.contains('lanta') || h.contains('sakit')) {
      return warningRed;
    }
    if (h.contains('katamtaman') || h.contains('bantayan')) {
      return const Color(0xFFD97706);
    }
    return const Color(0xFF059669);
  }

  Color get _plantHealthBg {
    final h = _plantHealth.toLowerCase();
    if (h.contains('babala') || h.contains('lanta') || h.contains('sakit')) {
      return const Color(0xFFFEE2E2);
    }
    if (h.contains('katamtaman') || h.contains('bantayan')) {
      return const Color(0xFFFEF3C7);
    }
    return const Color(0xFFECFDF5);
  }


  String get _salinityDisplay => _salinity != null && _salinity!.isFinite
      ? '${_salinity!.toStringAsFixed(2)} ppt' : '--';

  String get _tdsDisplay => _tds != null && _tds!.isFinite
      ? '${(_tds! + 0.5).floor()} ppm' : '--';

  String get _turbidityDisplay => _turbidity != null && _turbidity!.isFinite
      ? '${_turbidity!.toStringAsFixed(0)} NTU' : '--';

  // ── BUILD ──────────────────────────────────────────────────────────────

  void _onNavTapped(int index) {
    _phoneBackCoordinator?.reset();
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
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _pointerDownPosition = event.position;
            _pointerDownTime = DateTime.now();
          },
          onPointerUp: (event) {
            if (_showNotificationDropdown) return;
            if (_pointerDownPosition != null && _pointerDownTime != null) {
              final distance =
                  (event.position - _pointerDownPosition!).distance;
              final elapsed = DateTime.now().difference(_pointerDownTime!);
              // True tap/click (not a drag or scroll gesture) - toggle visibility
              if (distance < 18 && elapsed.inMilliseconds < 600) {
                _isNavBarVisible.value = !_isNavBarVisible.value;
              }
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              // Only react to vertical scrolling (ignores horizontal swipes in tabs)
              if (notification.metrics.axis != Axis.vertical) return false;
              if (_showNotificationDropdown) return false;

              if (notification is UserScrollNotification) {
                if (notification.direction == ScrollDirection.reverse) {
                  if (_isNavBarVisible.value) _isNavBarVisible.value = false;
                } else if (notification.direction == ScrollDirection.forward) {
                  if (!_isNavBarVisible.value) _isNavBarVisible.value = true;
                }
              } else if (notification is ScrollUpdateNotification) {
                final delta = notification.scrollDelta ?? 0;
                if (delta < -4) {
                  // Scrolling up: reveal navbar
                  if (!_isNavBarVisible.value) _isNavBarVisible.value = true;
                } else if (delta > 4) {
                  // Scrolling down: hide navbar
                  if (_isNavBarVisible.value) _isNavBarVisible.value = false;
                }
              }

              if (notification.metrics.maxScrollExtent > 20 &&
                  notification.metrics.pixels >=
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
                        if (!mounted || !_cacheStatus.isCurrent) return;
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
        child: RefreshIndicator(
          key: const Key('dashboard_refresh_indicator'),
          color: teal,
          onRefresh: _refreshDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreetingHeader(),
                const SizedBox(height: 18),
                // Living Assets (Ulang & Plants) + Water Parameters
                _buildWaterParametersSection(),
                const SizedBox(height: 22),
                // Babala warning notifications
                _buildUrgentTasksSection(),
              ],
            ),
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
                  child: ClipOval(
                    child: Image.asset(
                      'assets/img/logo_BU.png',
                      fit: BoxFit.contain,
                      semanticLabel: 'Bantay Ulang logo',
                    ),
                  ),
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

                // Bell icon — badge shows the current user's assigned tasks.
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
                        onTap: () {
                          setState(
                            () => _showNotificationDropdown = false,
                          );
                          if (!isTask) {
                            _acknowledgeAlert(alert['id'] as String);
                          }
                          _onNavTapped(1);
                        },
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

  // ── LIVING ASSETS & WATER PARAMETERS ─────────────────────────────────

  Widget _buildWaterParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big Card: Living Assets (Ulang Yield & Plant Status) with primary visual emphasis
        _buildLivingAssetsHeroCard(),
        const SizedBox(height: 14),
        Text(
          'Last reading: $_sensorReadingTime',
          key: const Key('dashboard_reading_time'),
          style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: 8),

        // Row 1: pH Level & Dissolved Oxygen
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildPHMiniCard()),
              const SizedBox(width: 10),
              Expanded(child: _buildOxygenMiniCard()),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Row 2: Separate TDS and Salinity readings, matching the admin cards.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildTdsMiniCard()),
              const SizedBox(width: 10),
              Expanded(child: _buildSalinityMiniCard()),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Row 3: Turbidity & Temperatura
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildTurbidityMiniCard()),
              const SizedBox(width: 10),
              Expanded(child: _buildTempMiniCard()),
            ],
          ),
        ),
      ],
    );
  }

  // ── LIVING ASSETS HERO CARD (BIG CARD INCLUDING ULANG & PLANTS) ───────

  Widget _buildLivingAssetsHeroCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildUlangCard()),
            const SizedBox(width: 10),
            Expanded(child: _buildPlantCard()),
          ],
        ),
      ),
    );
  }

  // Card 0A: Inaasahang Ani ng Ulang (Primary Focus Card)
  Widget _buildUlangCard() {
    return Material(
      color: tealDark,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _phoneBackCoordinator?.reset();
          setState(() {
            _currentNavIndex = 2; // Switch to Ani tab
          });
          _isNavBarVisible.value = true;
        },
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: tealDark,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF042F2E).withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                    width: 33,
                    height: 33,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.scale_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Inaasahang Ani",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Ulang",
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFCCFBF1),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _yieldDisplay,
                style: GoogleFonts.poppins(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: _shrimpHealthBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _shrimpHealthColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  _shrimpHealth.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _shrimpHealthColor,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Card 0B: Kalagayan ng mga Halaman (Primary Focus Card)
  Widget _buildPlantCard() {
    return Material(
      color: tealDark,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _phoneBackCoordinator?.reset();
          setState(() {
            _currentNavIndex = 2; // Switch to Ani tab
          });
          _isNavBarVisible.value = true;
        },
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: tealDark,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF042F2E).withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                    width: 33,
                    height: 33,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.eco_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Mga Halaman",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Thai Oregano ",
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFCCFBF1),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _plantHealth,
                style: GoogleFonts.poppins(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: _plantHealthBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _plantHealthColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  _plantHealth.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _plantHealthColor,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
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
                    _phoneBackCoordinator?.reset();
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

  // Card 2: pH Level
  Widget _buildPHMiniCard() {
    final phVal = _phLevel != null && _phLevel!.isFinite
        ? _phLevel!.toStringAsFixed(1) : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.water_drop_rounded,
                    size: 15,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  "pH Level",
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            phVal,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          WaterParameterBadge(
            key: const ValueKey(WaterParameter.ph),
            status: _waterStatus(WaterParameter.ph, _phLevel),
          ),
        ],
      ),
    );
  }

  // Card 3: Dissolved Oxygen
  Widget _buildOxygenMiniCard() {
    final oxygenVal =
        _dissolvedOxygen != null && _dissolvedOxygen!.isFinite
            ? _dissolvedOxygen!.toStringAsFixed(1) : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.air_rounded,
                    size: 15,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  "Dissolved Oxygen",
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            oxygenVal,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          WaterParameterBadge(
            key: const ValueKey(WaterParameter.oxygen),
            status: _waterStatus(WaterParameter.oxygen, _dissolvedOxygen),
          ),
        ],
      ),
    );
  }

  // Card 4: Temperatura ng Tubig
  Widget _buildTempMiniCard() {
    final tempVal =
        _waterTemp != null && _waterTemp!.isFinite
            ? '${_waterTemp!.toStringAsFixed(1)}°C' : '--';
    final isTempAlert = _waterStatus(WaterParameter.temperature, _waterTemp) ==
        WaterParameterStatus.critical;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isTempAlert ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.thermostat_rounded,
                    size: 15,
                    color: isTempAlert ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  "Temperatura",
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tempVal,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isTempAlert ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          WaterParameterBadge(
            key: const ValueKey(WaterParameter.temperature),
            status: _waterStatus(WaterParameter.temperature, _waterTemp),
          ),
        ],
      ),
    );
  }

  // The admin reads these independently from Aquaponics/Ulang statistics.
  Widget _buildTdsMiniCard() => _buildWaterParameterMiniCard(
    parameter: WaterParameter.tds,
    label: 'TDS',
    value: _tdsDisplay,
    reading: _tds,
    icon: Icons.grain_rounded,
  );

  Widget _buildSalinityMiniCard() => _buildWaterParameterMiniCard(
    parameter: WaterParameter.salinity,
    label: 'Salinity',
    value: _salinityDisplay,
    reading: _salinity,
    icon: Icons.opacity_rounded,
  );

  Widget _buildTurbidityMiniCard() => _buildWaterParameterMiniCard(
    parameter: WaterParameter.turbidity,
    label: 'Turbidity',
    value: _turbidityDisplay,
    reading: _turbidity,
    icon: Icons.blur_on_rounded,
  );

  Widget _buildWaterParameterMiniCard({
    required WaterParameter parameter,
    required String label,
    required String value,
    required double? reading,
    required IconData icon,
  }) {
    return Container(
      key: ValueKey('water_card_${parameter.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(icon, size: 15, color: const Color(0xFF0284C7))),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            key: ValueKey('water_value_${parameter.name}'),
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          WaterParameterBadge(
            key: ValueKey(parameter),
            status: _waterStatus(parameter, reading),
          ),
        ],
      ),
    );
  }
}
