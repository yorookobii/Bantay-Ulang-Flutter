import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage>
    with SingleTickerProviderStateMixin {
  final Color tealLight = const Color(0xFFE6FFF9);
  final Color teal = const Color(0xFF0D9488);
  final Color tealDark = const Color(0xFF0F766E);
  final Color seaBlue = const Color(0xFF0369A1);
  final Color textDark = const Color(0xFF1F2937);
  final Color textMuted = const Color(0xFF6B7280);

  late AnimationController _fadeController;
  StreamSubscription<QuerySnapshot>? _logsSub;

  List<QueryDocumentSnapshot> _ulangLogs = [];
  List<QueryDocumentSnapshot> _plantLogs = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSavingUlang = false;
  bool _isSavingPlant = false;
  
  List<QueryDocumentSnapshot> _ulangGrowthRecords = [];
  StreamSubscription<QuerySnapshot>? _growthRecordsSub;

  // New mortality records state
  List<QueryDocumentSnapshot> _mortalityRecords = [];
  StreamSubscription<QuerySnapshot>? _mortalityRecordsSub;

  // Growth indicators state for cycle tracking
  DateTime? _cycleStart;
  StreamSubscription<QuerySnapshot>? _indicatorsSub;

  // Weekly growth chart state
  int? _selectedWeekIndex;
  bool _showAllWeeks = false;
  bool _isRefreshingChart = false;

  // See More state for lists
  bool _showAllMortality = false;
  bool _showAllUlangLogs = false;
  bool _showAllPlantLogs = false;

  // Ulang form controllers
  final sizeController = TextEditingController();
  final weightController = TextEditingController();

  // Mortality form controller
  final mortalityController = TextEditingController();
  bool _isSavingMortality = false;

  // Plant form controllers
  final plantHeightController = TextEditingController();
  String? selectedPlantStage;
  String? selectedPlantName;
  String? selectedPlantCondition;

  // Predefined options (validation must match these) - Kangkong removed
  static const List<String> _plantNames = ['Mint', 'Oregano'];
  static const List<String> _plantStages = [
    'Seedling',
    'Vegetative',
    'Pre-Flowering',
    'Harvest',
  ];
  static const List<String> _plantConditions = [
    'Malusog',
    'Dilaw',
    'Nalalanta',
    'May Peste',
  ];

  // Ulang input ranges
  static const double _sizeMin = 0.1;
  static const double _sizeMax = 30.0;
  static const double _weightMin = 0.1;
  static const double _weightMax = 500.0;

  // Plant height range
  static const double _heightMin = 0.0;
  static const double _heightMax = 100.0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _subscribeLogs();
    _subscribeGrowthRecords();
    _subscribeMortalityRecords();
    _subscribeGrowthIndicators();
  }

  void _subscribeLogs() {
    _logsSub = FirebaseFirestore.instance
        .collection('logs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = null;
              _ulangLogs = snapshot.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['type'] == 'ulang';
              }).toList();
              _plantLogs = snapshot.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['type'] == 'plant';
              }).toList();
            });
          },
          onError: (error) {
            debugPrint('Logs subscription error: $error');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Hindi ma-load ang mga tala. Subukan muli.';
              });
            }
          },
        );
  }

  void _subscribeGrowthRecords() {
    _growthRecordsSub = FirebaseFirestore.instance
        .collection('ulang_growth_records')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() => _ulangGrowthRecords = snapshot.docs);
          },
          onError: (error) =>
              debugPrint('Growth records subscription error: $error'),
        );
  }

  void _subscribeMortalityRecords() {
    _mortalityRecordsSub = FirebaseFirestore.instance
        .collection('mortality_records')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() => _mortalityRecords = snapshot.docs);
          },
          onError: (error) =>
              debugPrint('Mortality records subscription error: $error'),
        );
  }

  void _subscribeGrowthIndicators() {
    _indicatorsSub = FirebaseFirestore.instance
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            if (snapshot.docs.isNotEmpty) {
              final data = snapshot.docs.first.data();
              final cycleStartTs = data['cycleStart'] as Timestamp?;
              setState(() {
                _cycleStart = cycleStartTs?.toDate();
              });
            }
          },
          onError: (error) =>
              debugPrint('Growth indicators subscription error: $error'),
        );
  }

  Future<void> _refreshAllData() async {
    if (_isRefreshingChart) return;
    setState(() => _isRefreshingChart = true);
    try {
      final recordsSnap = await FirebaseFirestore.instance
          .collection('ulang_growth_records')
          .orderBy('createdAt', descending: true)
          .get();

      final indicatorsSnap = await FirebaseFirestore.instance
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      final logsSnap = await FirebaseFirestore.instance
          .collection('logs')
          .orderBy('createdAt', descending: true)
          .get();

      if (!mounted) return;
      setState(() {
        _ulangGrowthRecords = recordsSnap.docs;
        _ulangLogs = logsSnap.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['type'] == 'ulang';
        }).toList();
        _plantLogs = logsSnap.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['type'] == 'plant';
        }).toList();
        if (indicatorsSnap.docs.isNotEmpty) {
          final data = indicatorsSnap.docs.first.data();
          final cycleStartTs = data['cycleStart'] as Timestamp?;
          _cycleStart = cycleStartTs?.toDate();
        }
        _selectedWeekIndex = null;
      });
      _showSuccessSnackbar("Matagumpay na na-refresh ang graph at mga tala.");
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        _showErrorSnackbar("Hindi ma-refresh ang data. Subukan muli.");
      }
    } finally {
      if (mounted) setState(() => _isRefreshingChart = false);
    }
  }

  int _weekNumberFor(DateTime date, DateTime cycleStart) {
    return (date.difference(cycleStart).inDays ~/ 7) + 1;
  }

  Future<void> _recalculateAndUpdateGrowthIndicators() async {
    try {
      final indicatorsSnap = await FirebaseFirestore.instance
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (indicatorsSnap.docs.isEmpty) return;

      final indicatorDoc = indicatorsSnap.docs.first;
      final data = indicatorDoc.data() as Map<String, dynamic>;
      final initialStock = (data['initialStock'] as num?)?.toDouble() ?? 0;
      final cycleStartTs = data['cycleStart'] as Timestamp?;

      if (cycleStartTs == null) return;
      final cycleStart = cycleStartTs.toDate();

      final updates = <String, dynamic>{};

      final recordsSnap = await FirebaseFirestore.instance
          .collection('ulang_growth_records')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStart),
          )
          .get();

      double? avgWeight;
      if (recordsSnap.docs.isNotEmpty) {
        final now = DateTime.now();
        final currentWeek = _weekNumberFor(now, cycleStart);
        for (int week = currentWeek; week >= 1; week--) {
          final weekDocs = recordsSnap.docs.where((doc) {
            final ts =
                (doc.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (ts == null) return false;
            return _weekNumberFor(ts.toDate(), cycleStart) == week;
          }).toList();
          if (weekDocs.isNotEmpty) {
            double totalWeight = 0;
            for (final doc in weekDocs) {
              totalWeight +=
                  ((doc.data() as Map<String, dynamic>)['weight'] as num?)
                      ?.toDouble() ??
                  0;
            }
            avgWeight = totalWeight / weekDocs.length;
            break;
          }
        }
      }
      if (avgWeight != null) {
        updates['avgWeightPerPiece'] = avgWeight;
      }

      final mortalitySnap = await FirebaseFirestore.instance
          .collection('mortality_records')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStart),
          )
          .get();
      int totalDeaths = 0;
      for (final doc in mortalitySnap.docs) {
        totalDeaths += ((doc.data()['deathCount'] as num?)?.toInt() ?? 0);
      }
      double? survivalRate;
      if (initialStock > 0) {
        survivalRate = (((initialStock - totalDeaths) / initialStock) * 100)
            .clamp(0, 100);
        updates['survivalRate'] = survivalRate;
      }

      final effectiveAvgWeight =
          avgWeight ?? (data['avgWeightPerPiece'] as num?)?.toDouble() ?? 0;
      final effectiveSurvival =
          survivalRate ?? (data['survivalRate'] as num?)?.toDouble() ?? 0;
      if (initialStock > 0 && effectiveSurvival > 0) {
        updates['expectedYield'] =
            initialStock *
            (effectiveSurvival / 100) *
            (effectiveAvgWeight / 1000);
      }

      if (updates.isNotEmpty) {
        await indicatorDoc.reference.update(updates);
      }
    } catch (e) {
      debugPrint('Failed to recalculate growth indicators: $e');
    }
  }

  @override
  void dispose() {
    _logsSub?.cancel();
    _growthRecordsSub?.cancel();
    _mortalityRecordsSub?.cancel();
    _indicatorsSub?.cancel();
    _fadeController.dispose();
    sizeController.dispose();
    weightController.dispose();
    mortalityController.dispose();
    plantHeightController.dispose();
    super.dispose();
  }

  // =======================
  // Save Handlers
  // =======================

  Future<void> _saveUlangLog() async {
    if (_isSavingUlang) return;

    final sizeText = sizeController.text.trim();
    final weightText = weightController.text.trim();

    // Check for empty inputs before proceeding
    if (sizeText.isEmpty || weightText.isEmpty) {
      _showErrorSnackbar("May mga patlang na walang laman. Punan bago magpatuloy.");
      return;
    }

    final sizeNum = double.tryParse(sizeText);
    final weightNum = double.tryParse(weightText);

    if (sizeNum == null || sizeNum < _sizeMin || sizeNum > _sizeMax) {
      _showErrorSnackbar(
        "Ang laki ay dapat numerong nasa pagitan ng ${_sizeMin.toStringAsFixed(1)} at ${_sizeMax.toStringAsFixed(0)} cm.",
      );
      return;
    }

    if (weightNum == null || weightNum < _weightMin || weightNum > _weightMax) {
      _showErrorSnackbar(
        "Ang timbang ay dapat numerong nasa pagitan ng ${_weightMin.toStringAsFixed(1)} at ${_weightMax.toStringAsFixed(0)} g.",
      );
      return;
    }

    setState(() => _isSavingUlang = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final logger = await _currentLoggerIdentity();
      final observedAt = Timestamp.fromDate(DateTime.now());

      await FirebaseFirestore.instance.collection('logs').add({
        'title': 'Ulang Log',
        'description': 'Laki: ${sizeText}cm • Timbang: ${weightText}g',
        'type': 'ulang',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'createdByName': logger.name,
        'createdByEmail': logger.email,
        'size': sizeText,
        'weight': weightText,
        'observedAt': observedAt,
      });

      await FirebaseFirestore.instance.collection('ulang_growth_records').add({
        'size': sizeNum,
        'weight': weightNum,
        'recordedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'observedAt': observedAt,
      });

      await _recalculateAndUpdateGrowthIndicators();

      sizeController.clear();
      weightController.clear();
      _showSuccessSnackbar("Matagumpay na na-save ang tala ng Ulang.");
    } finally {
      if (mounted) setState(() => _isSavingUlang = false);
    }
  }

  Future<void> _saveMortalityLog() async {
    if (_isSavingMortality) return;

    final deathText = mortalityController.text.trim();

    // Check for empty inputs before proceeding
    if (deathText.isEmpty) {
      _showErrorSnackbar("May mga patlang na walang laman. Punan bago magpatuloy.");
      return;
    }

    final deathCount = int.tryParse(deathText);
    if (deathCount == null || deathCount < 0) {
      _showErrorSnackbar(
        "Ang bilang ng namatay ay dapat isang buong numero (0 pataas).",
      );
      return;
    }

    setState(() => _isSavingMortality = true);
    try {
      final indicatorsSnap = await FirebaseFirestore.instance
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (indicatorsSnap.docs.isEmpty) {
        _showErrorSnackbar(
          "Itakda muna ang petsa ng simula ng cycle sa Settings.",
        );
        return;
      }
      final data = indicatorsSnap.docs.first.data() as Map<String, dynamic>;
      final cycleStartTs = data['cycleStart'] as Timestamp?;
      if (cycleStartTs == null) {
        _showErrorSnackbar(
          "Itakda muna ang petsa ng simula ng cycle sa Settings.",
        );
        return;
      }
      final cycleStart = cycleStartTs.toDate();
      final weekNumber = _weekNumberFor(DateTime.now(), cycleStart);

      final existingSnap = await FirebaseFirestore.instance
          .collection('mortality_records')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStart),
          )
          .get();
      final alreadyLogged = existingSnap.docs.any(
        (doc) => (doc.data()['weekNumber'] as num?)?.toInt() == weekNumber,
      );
      if (alreadyLogged) {
        _showErrorSnackbar(
          "May naitala na para sa linggong ito. Hintayin ang susunod na linggo.",
        );
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance.collection('mortality_records').add({
        'deathCount': deathCount,
        'weekNumber': weekNumber,
        'recordedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _recalculateAndUpdateGrowthIndicators();

      mortalityController.clear();
      _showSuccessSnackbar("Matagumpay na na-save ang tala ng namatay.");
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showErrorSnackbar(
        e.code == 'permission-denied'
            ? "Walang pahintulot na i-save ang mortality log. Kontakin ang admin."
            : "Hindi na-save ang mortality log: ${e.message ?? e.code}",
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar("Hindi na-save ang mortality log. Subukan muli.");
    } finally {
      if (mounted) setState(() => _isSavingMortality = false);
    }
  }

  Future<void> _savePlantLog() async {
    if (_isSavingPlant) return;

    final heightText = plantHeightController.text.trim();

    // Check for empty inputs before proceeding
    if (selectedPlantName == null || 
        heightText.isEmpty || 
        selectedPlantStage == null || 
        selectedPlantCondition == null) {
      _showErrorSnackbar("May mga patlang na walang laman. Punan bago magpatuloy.");
      return;
    }

    if (!_plantNames.contains(selectedPlantName)) {
      _showErrorSnackbar("Pumili ng wastong pangalan ng tanim.");
      return;
    }

    final heightNum = double.tryParse(heightText);
    if (heightNum == null || heightNum < _heightMin || heightNum > _heightMax) {
      _showErrorSnackbar(
        "Ang taas ay dapat numerong nasa pagitan ng ${_heightMin.toStringAsFixed(0)} at ${_heightMax.toStringAsFixed(0)} cm.",
      );
      return;
    }

    if (!_plantStages.contains(selectedPlantStage)) {
      _showErrorSnackbar("Pumili ng wastong yugto ng paglaki.");
      return;
    }

    if (!_plantConditions.contains(selectedPlantCondition)) {
      _showErrorSnackbar("Pumili ng wastong kondisyon ng tanim.");
      return;
    }

    setState(() => _isSavingPlant = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final logger = await _currentLoggerIdentity();
      await FirebaseFirestore.instance.collection('logs').add({
        'title': selectedPlantName!,
        'description':
            'Taas: ${heightText}cm • Yugto: $selectedPlantStage • Kondisyon: $selectedPlantCondition',
        'type': 'plant',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'createdByName': logger.name,
        'createdByEmail': logger.email,
        'plantName': selectedPlantName,
        'height': heightText,
        'condition': selectedPlantCondition,
        'stage': selectedPlantStage,
        'observedAt': Timestamp.fromDate(DateTime.now()),
      });
      plantHeightController.clear();
      setState(() {
        selectedPlantName = null;
        selectedPlantStage = null;
        selectedPlantCondition = null;
      });
      _showSuccessSnackbar("Matagumpay na na-save ang tala ng Tanim.");
    } finally {
      if (mounted) setState(() => _isSavingPlant = false);
    }
  }

  // =======================
  // Logic Helpers
  // =======================

  Future<({String name, String email})> _currentLoggerIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    var name = user?.displayName?.trim() ?? '';
    var email = user?.email?.trim() ?? '';

    if (user != null) {
      try {
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = profile.data();
        name = (data?['fullName'] as String?)?.trim() ?? name;
        email = (data?['email'] as String?)?.trim() ?? email;
      } catch (error) {
        debugPrint('Could not load logger profile: $error');
      }
    }

    return (name: name, email: email);
  }

  String _loggerLabel(Map<String, dynamic> data) {
    final name = (data['createdByName'] as String?)?.trim() ?? '';
    final email = (data['createdByEmail'] as String?)?.trim() ?? '';
    final uid = (data['createdBy'] as String?)?.trim() ?? '';

    if (name.isNotEmpty && email.isNotEmpty) return '$name ($email)';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    if (uid.isNotEmpty) return uid;
    return 'Hindi matukoy';
  }

  List<Map<String, dynamic>> getWeeklyGrowthData() {
    if (_ulangGrowthRecords.isEmpty) return [];

    // Determine cycle start baseline
    DateTime? cycleStart = _cycleStart;
    if (cycleStart == null) {
      DateTime? earliest;
      for (final doc in _ulangGrowthRecords) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = (data['observedAt'] ?? data['createdAt']) as Timestamp?;
        if (ts != null) {
          final d = ts.toDate();
          if (earliest == null || d.isBefore(earliest)) {
            earliest = d;
          }
        }
      }
      if (earliest != null) {
        cycleStart = DateTime(earliest.year, earliest.month, earliest.day);
      }
    }

    if (cycleStart == null) return [];

    final Map<int, List<({double weight, DateTime date})>> weekBuckets = {};

    for (final doc in _ulangGrowthRecords) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = (data['observedAt'] ?? data['createdAt']) as Timestamp?;
      if (ts == null) continue;
      final rawDate = ts.toDate();
      final date = DateTime(rawDate.year, rawDate.month, rawDate.day);
      int weekNum = _weekNumberFor(date, cycleStart);
      if (weekNum < 1) weekNum = 1;

      final weight = (data['weight'] as num?)?.toDouble();
      if (weight == null || weight <= 0) continue;

      weekBuckets.putIfAbsent(weekNum, () => []).add((weight: weight, date: date));
    }

    if (weekBuckets.isEmpty) return [];

    final sortedWeekNumbers = weekBuckets.keys.toList()..sort();

    return sortedWeekNumbers.map((weekNum) {
      final records = weekBuckets[weekNum]!;
      final double totalWeight = records.fold(0.0, (acc, r) => acc + r.weight);
      final int count = records.length;
      final double avgWeight = count > 0 ? (totalWeight / count) : 0.0;

      final weekStart = cycleStart!.add(Duration(days: (weekNum - 1) * 7));
      final weekEnd = weekStart.add(const Duration(days: 6));

      DateTime? latestDate;
      for (final r in records) {
        if (latestDate == null || r.date.isAfter(latestDate)) {
          latestDate = r.date;
        }
      }

      return {
        'weekNumber': weekNum,
        'label': 'W$weekNum',
        'longLabel': 'Linggo $weekNum',
        'avgWeight': avgWeight,
        'totalWeight': totalWeight,
        'count': count,
        'dateRange': _formatDateRange(weekStart, weekEnd),
        'latestObservation': latestDate,
      };
    }).toList();
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateRange(DateTime start, DateTime end) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (start.year == end.year && start.month == end.month) {
      return '${months[start.month - 1]} ${start.day}-${end.day}';
    }
    return '${months[start.month - 1]} ${start.day} - '
        '${months[end.month - 1]} ${end.day}';
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: tealDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // =======================
  // UI Build
  // =======================

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.1),
          toolbarHeight: 0,
          bottom: TabBar(
            indicatorColor: teal,
            indicatorWeight: 3,
            labelColor: tealDark,
            unselectedLabelColor: textMuted,
            labelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: "Tala ng Ulang"),
              Tab(text: "Tala ng Tanim"),
            ],
          ),
        ),
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
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 56,
                          color: textMuted,
                        ),
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
                            _logsSub?.cancel();
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            _subscribeLogs();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            "Subukan Muli",
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
              : TabBarView(children: [_buildUlangTab(), _buildPlantTab()]),
        ),
      ),
    );
  }

  // =======================
  // Ulang Tab UI
  // =======================

  Widget _buildUlangTab() {
    final weeklyGrowthData = getWeeklyGrowthData();

    return RefreshIndicator(
      color: teal,
      onRefresh: _refreshAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              "Tala ng Ulang",
              "I-record ang sukat at timbang ng mga ulang.",
            ),
            const SizedBox(height: 24),

            _buildSectionTitle("Lingguhang Paglaki"),
            const SizedBox(height: 12),
            _buildWeeklyGrowthChartCard(weeklyGrowthData),
            const SizedBox(height: 24),

            if (_ulangLogs.isNotEmpty) ...[
              _buildLatestUlangLogSummary(_ulangLogs.first),
              const SizedBox(height: 24),
            ],

          _buildSectionTitle("Magdagdag ng Tala"),
          const SizedBox(height: 12),
          _buildUlangForm(),
          const SizedBox(height: 24),

          _buildSectionTitle("Lingguhang Mortality"),
          const SizedBox(height: 12),
          _buildMortalityForm(),
          const SizedBox(height: 24),

          if (_mortalityRecords.isNotEmpty) ...[
            _buildSectionTitle("Mga Nakaraang Tala ng Mortality"),
            const SizedBox(height: 12),
            ...(_showAllMortality
                    ? _mortalityRecords
                    : _mortalityRecords.take(3))
                .map(_buildMortalityLogCard),
            if (_mortalityRecords.length > 3)
              _buildSeeMoreButton(
                isExpanded: _showAllMortality,
                totalCount: _mortalityRecords.length,
                onTap: () => setState(() => _showAllMortality = !_showAllMortality),
              ),
            const SizedBox(height: 24),
          ],

          if (_ulangLogs.isNotEmpty) ...[
            _buildSectionTitle("Mga Nakaraang Tala ng Ulang"),
            const SizedBox(height: 12),
            ...(_showAllUlangLogs ? _ulangLogs : _ulangLogs.take(3))
                .map(_buildUlangLogCard),
            if (_ulangLogs.length > 3)
              _buildSeeMoreButton(
                isExpanded: _showAllUlangLogs,
                totalCount: _ulangLogs.length,
                onTap: () => setState(() => _showAllUlangLogs = !_showAllUlangLogs),
              ),
          ],
        ],
      ),
    ),
  );
}

  // =======================
  // Plant Tab UI
  // =======================

  Widget _buildPlantTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            "Tala ng Tanim",
            "I-record ang paglaki at kondisyon ng mga halaman.",
          ),
          const SizedBox(height: 24),

          _statCard("Kabuuang Tala", _plantLogs.length.toString(), Icons.eco),
          const SizedBox(height: 24),

          _buildSectionTitle("Magdagdag ng Tala"),
          const SizedBox(height: 12),
          _buildPlantForm(),
          const SizedBox(height: 24),

          if (_plantLogs.isNotEmpty) ...[
            _buildSectionTitle("Mga Nakaraang Tala"),
            const SizedBox(height: 12),
            ...(_showAllPlantLogs ? _plantLogs : _plantLogs.take(3))
                .map(_buildPlantLogCard),
            if (_plantLogs.length > 3)
              _buildSeeMoreButton(
                isExpanded: _showAllPlantLogs,
                totalCount: _plantLogs.length,
                onTap: () =>
                    setState(() => _showAllPlantLogs = !_showAllPlantLogs),
              ),
          ],
        ],
      ),
    );
  }

  // =======================
  // Component Widgets
  // =======================

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: textDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: textMuted,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildSeeMoreButton({
    required bool isExpanded,
    required int totalCount,
    required VoidCallback onTap,
  }) {
    final hiddenCount = totalCount - 3;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(
            isExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: tealDark,
          ),
          label: Text(
            isExpanded
                ? "See Less"
                : "See More (+$hiddenCount)",
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tealDark,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: BorderSide(color: teal.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textDark,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      width: double.infinity,
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tealLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tealDark, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: tealDark,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyGrowthChartCard(List<Map<String, dynamic>> allWeeks) {
    if (allWeeks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tealLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.show_chart_rounded, color: tealDark, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              "Wala pang naitalang lingguhang paglaki",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Magtala ng sukat at timbang ng ulang sa ibaba upang makita ang linya ng paglaki kada linggo.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Show latest 3 weeks by default if there are more than 3 weeks
    final bool hasMoreThanThree = allWeeks.length > 3;
    final List<Map<String, dynamic>> displayedWeeks = (hasMoreThanThree && !_showAllWeeks)
        ? allWeeks.sublist(allWeeks.length - 3)
        : allWeeks;

    final int selectedIndex = (_selectedWeekIndex != null &&
            _selectedWeekIndex! >= 0 &&
            _selectedWeekIndex! < displayedWeeks.length)
        ? _selectedWeekIndex!
        : (displayedWeeks.length - 1);

    final selectedWeek = displayedWeeks[selectedIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title, ABW Subtitle, and Optional Toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tealLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insights_rounded, color: tealDark, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Lingguhang Paglaki",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    Text(
                      "Overall Weight in Grams",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Dedicated Refresh Button
              InkWell(
                onTap: _isRefreshingChart ? null : () => _refreshAllData(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: tealLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: teal.withValues(alpha: 0.3)),
                  ),
                  child: _isRefreshingChart
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tealDark,
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: tealDark,
                        ),
                ),
              ),
              if (hasMoreThanThree) const SizedBox(width: 8),
              if (hasMoreThanThree)
                InkWell(
                  onTap: () {
                    setState(() {
                      _showAllWeeks = !_showAllWeeks;
                      _selectedWeekIndex = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _showAllWeeks ? tealDark : tealLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: teal.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showAllWeeks ? Icons.filter_alt_outlined : Icons.history_rounded,
                          size: 13,
                          color: _showAllWeeks ? Colors.white : tealDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showAllWeeks ? "Huling 3" : "Lahat (${allWeeks.length})",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _showAllWeeks ? Colors.white : tealDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Active Selected Week Badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tealLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: teal.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tealDark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    selectedWeek['label'],
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${selectedWeek['longLabel']} (${selectedWeek['dateRange']})",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "${selectedWeek['count']} ${selectedWeek['count'] == 1 ? 'tala' : 'mga tala'} • Ave: ${(selectedWeek['avgWeight'] as double).toStringAsFixed(1)} g",
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  "${(selectedWeek['totalWeight'] as double).toStringAsFixed(1)} g",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: tealDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Chart Canvas with GestureDetector for interactive touch/tap
          LayoutBuilder(
            builder: (context, constraints) {
              const double chartHeight = 170.0;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  const double leftPad = 38.0;
                  const double rightPad = 24.0;
                  final double usableWidth = constraints.maxWidth - leftPad - rightPad;
                  if (displayedWeeks.length == 1) {
                    setState(() => _selectedWeekIndex = 0);
                  } else if (displayedWeeks.length > 1) {
                    final double step = usableWidth / (displayedWeeks.length - 1);
                    final double localX = details.localPosition.dx - leftPad;
                    final int tappedIndex = (localX / step).round().clamp(0, displayedWeeks.length - 1);
                    setState(() => _selectedWeekIndex = tappedIndex);
                  }
                },
                child: SizedBox(
                  width: double.infinity,
                  height: chartHeight,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, chartHeight),
                    painter: WeeklyGrowthLinePainter(
                      data: displayedWeeks,
                      selectedIndex: selectedIndex,
                      tealColor: teal,
                      tealDarkColor: tealDark,
                      textDarkColor: textDark,
                      textMutedColor: textMuted,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Helpful interactive caption
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, size: 13, color: textMuted),
              const SizedBox(width: 4),
              Text(
                "Pindutin ang mga punto sa linya upang makita ang detalye",
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLatestUlangLogSummary(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final observedAt = data['observedAt'] as Timestamp?;
    final createdAt = data['createdAt'] as Timestamp?;
    final observationDate = observedAt?.toDate();
    final savedDate = createdAt?.toDate();
    final weight = data['weight'] ?? '—';
    final size = data['size'] ?? '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tealLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: teal.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.history_rounded, color: tealDark, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pinakahuling Na-log',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tealDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  observationDate != null
                      ? 'Petsa ng obserbasyon: ${_formatShortDate(observationDate)}'
                      : 'Petsa ng obserbasyon: —',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                ),
                Text(
                  'Laki: $size cm  •  Timbang: $weight g',
                  style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
                ),
                if (savedDate != null)
                  Text(
                    'Na-save: ${_formatShortDate(savedDate)}',
                    style: GoogleFonts.poppins(fontSize: 11, color: textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUlangForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          _buildInputField(
            sizeController,
            "Laki (cm)",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _buildInputField(
            weightController,
            "Bigat (g)",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          _buildSaveButton(
            _isSavingUlang ? "Sine-save..." : "I-save ang Ulang Log",
            _isSavingUlang ? null : () => _saveUlangLog(),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          _buildInputField(
            mortalityController,
            "Ilang namatay ngayong linggo?",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          _buildSaveButton(
            _isSavingMortality ? "Sine-save..." : "I-save ang Mortality Log",
            _isSavingMortality ? null : () => _saveMortalityLog(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          _buildCustomDropdown(
            value: selectedPlantName,
            hint: "Pumili ng uri ng tanim",
            label: "Pangalan ng Tanim",
            items: const [
              DropdownMenuItem(value: 'Mint', child: Text('Mint')),
              DropdownMenuItem(value: 'Oregano', child: Text('Oregano')),
            ],
            onChanged: (value) => setState(() => selectedPlantName = value),
          ),
          const SizedBox(height: 16),
          _buildInputField(
            plantHeightController,
            "Taas (cm)",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _buildCustomDropdown(
            value: selectedPlantCondition,
            hint: "Pumili ng kondisyon",
            label: "Kondisyon",
            items: const [
              DropdownMenuItem(
                value: 'Malusog',
                child: Text('Malusog (Healthy)'),
              ),
              DropdownMenuItem(
                value: 'Dilaw',
                child: Text('Dilaw (Yellowing)'),
              ),
              DropdownMenuItem(
                value: 'Nalalanta',
                child: Text('Nalalanta (Wilting)'),
              ),
              DropdownMenuItem(
                value: 'May Peste',
                child: Text('May Peste/Sakit'),
              ),
            ],
            onChanged: (value) =>
                setState(() => selectedPlantCondition = value),
          ),
          const SizedBox(height: 16),
          _buildCustomDropdown(
            value: selectedPlantStage,
            hint: "Pumili ng yugto ng paglaki",
            label: "Yugto ng Paglaki",
            items: const [
              DropdownMenuItem(
                value: 'Seedling',
                child: Text('Seedling (Punla)'),
              ),
              DropdownMenuItem(
                value: 'Vegetative',
                child: Text('Vegetative (Lumalaki)'),
              ),
              DropdownMenuItem(
                value: 'Pre-Flowering',
                child: Text('Pre-Flowering'),
              ),
              DropdownMenuItem(
                value: 'Harvest',
                child: Text('Harvest (Handa na anihin)'),
              ),
            ],
            onChanged: (value) => setState(() => selectedPlantStage = value),
          ),
          const SizedBox(height: 20),
          _buildSaveButton(
            _isSavingPlant ? "Sine-save..." : "I-save ang Plant Log",
            _isSavingPlant ? null : () => _savePlantLog(),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(String text, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          disabledBackgroundColor: teal.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 15, color: textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: teal, width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildCustomDropdown<T>({
    required T? value,
    required String hint,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: Text(
        hint,
        style: GoogleFonts.poppins(fontSize: 14, color: textMuted),
      ),
      style: GoogleFonts.poppins(fontSize: 15, color: textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: teal, width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      items: items,
      onChanged: onChanged,
      dropdownColor: Colors.white,
    );
  }
  
  Widget _buildMortalityLogCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final deathCount = data['deathCount'] ?? 0;
    final weekNumber = data['weekNumber'] ?? '—';
    final ts = data['createdAt'] as Timestamp?;
    final date = ts?.toDate();
    final formattedDate = date != null
        ? '${date.month}/${date.day}/${date.year}'
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Namatay: $deathCount',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Linggo: $weekNumber',
                  style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildUlangLogCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final size = data['size'] ?? '—';
    final weight = data['weight'] ?? '—';
    final ts = (data['observedAt'] ?? data['createdAt']) as Timestamp?;
    final date = ts?.toDate();
    final formattedDate = date != null
        ? '${date.month}/${date.day}/${date.year}'
        : '—';
        
    // Extract only the name directly, completely ignoring the UID fallback
    final name = (data['createdByName'] as String?)?.trim() ?? '';
    final loggerName = name.isNotEmpty ? name : 'Hindi matukoy';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: seaBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('🦐', style: TextStyle(fontSize: 22, height: 1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Laki: $size cm',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Timbang: $weight g',
                  style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nag-log: $loggerName', // Using the extracted name here
                  style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildPlantLogCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['plantName'] ?? data['title'] ?? 'Tanim';
    final height = data['height'] ?? '—';
    final stage = data['stage'] ?? '-';
    final condition = data['condition'] ?? '';
    final ts = (data['observedAt'] ?? data['createdAt']) as Timestamp?;
    final date = ts?.toDate();
    final formattedDate = date != null
        ? '${date.month}/${date.day}/${date.year}'
        : '—';
        
    // Extract only the name directly, completely ignoring the UID fallback
    final createdByName = (data['createdByName'] as String?)?.trim() ?? '';
    final loggerName = createdByName.isNotEmpty ? createdByName : 'Hindi matukoy';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.eco, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Taas: ${height}cm • Yugto: $stage',
                  style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
                ),
                if (condition.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Kondisyon: $condition',
                    style: GoogleFonts.poppins(fontSize: 13, color: textMuted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Nag-log: $loggerName', // Using the extracted name here
                  style: GoogleFonts.poppins(fontSize: 12, color: textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WeeklyGrowthLinePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final int selectedIndex;
  final Color tealColor;
  final Color tealDarkColor;
  final Color textDarkColor;
  final Color textMutedColor;

  WeeklyGrowthLinePainter({
    required this.data,
    required this.selectedIndex,
    required this.tealColor,
    required this.tealDarkColor,
    required this.textDarkColor,
    required this.textMutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    const double leftPad = 38.0;
    const double rightPad = 24.0;
    const double topPad = 26.0;
    const double bottomPad = 28.0;

    final double chartWidth = size.width - leftPad - rightPad;
    final double chartHeight = size.height - topPad - bottomPad;
    final double chartBottom = topPad + chartHeight;

    // Calculate max weight for Y-axis scale
    double maxVal = 0.0;
    for (final d in data) {
      final w = (d['totalWeight'] as num).toDouble();
      if (w > maxVal) maxVal = w;
    }

    double maxY = maxVal > 0 ? maxVal * 1.3 : 20.0;
    if (maxY <= 10) {
      maxY = 10.0;
    } else if (maxY <= 50) {
      maxY = (maxY / 10).ceil() * 10.0;
    } else {
      maxY = (maxY / 25).ceil() * 25.0;
    }

    // Horizontal guidelines at 3 levels: 0, maxY/2, maxY
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1.0;

    final double midY = topPad + (chartHeight / 2);
    canvas.drawLine(Offset(leftPad, topPad), Offset(size.width - rightPad, topPad), gridPaint);
    canvas.drawLine(Offset(leftPad, midY), Offset(size.width - rightPad, midY), gridPaint);
    canvas.drawLine(Offset(leftPad, chartBottom), Offset(size.width - rightPad, chartBottom), gridPaint);

    // Y-Axis numeric labels
    _drawYAxisLabel(canvas, "${maxY.toStringAsFixed(0)}g", Offset(leftPad - 6, topPad));
    _drawYAxisLabel(canvas, "${(maxY / 2).toStringAsFixed(0)}g", Offset(leftPad - 6, midY));
    _drawYAxisLabel(canvas, "0g", Offset(leftPad - 6, chartBottom));

    // Compute coordinate points
    final List<Offset> points = [];
    if (data.length == 1) {
      final double x = leftPad + (chartWidth / 2);
      final double weight = (data[0]['totalWeight'] as num).toDouble();
      final double y = chartBottom - ((weight / maxY) * chartHeight).clamp(0.0, chartHeight);
      points.add(Offset(x, y));
    } else {
      final double step = chartWidth / (data.length - 1);
      for (int i = 0; i < data.length; i++) {
        final double x = leftPad + (i * step);
        final double weight = (data[i]['totalWeight'] as num).toDouble();
        final double y = chartBottom - ((weight / maxY) * chartHeight).clamp(0.0, chartHeight);
        points.add(Offset(x, y));
      }
    }

    // Multiple points: draw smooth Bezier curve and subtle gradient fill
    if (points.length >= 2) {
      final path = Path();
      path.moveTo(points[0].dx, points[0].dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final cp1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
        final cp2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
      }

      // Gradient area fill
      final fillPath = Path.from(path)
        ..lineTo(points.last.dx, chartBottom)
        ..lineTo(points.first.dx, chartBottom)
        ..close();

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, topPad),
          Offset(0, chartBottom),
          [
            tealColor.withValues(alpha: 0.28),
            tealColor.withValues(alpha: 0.0),
          ],
        );
      canvas.drawPath(fillPath, fillPaint);

      // Smooth line stroke
      final linePaint = Paint()
        ..color = tealColor
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);
    }

    // Draw individual nodes and X-axis week titles
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isSelected = (i == selectedIndex);
      final labelText = data[i]['label'] as String; // "W1", "W2", "W3"

      // X-Axis Week Title
      _drawXAxisLabel(canvas, labelText, Offset(p.dx, chartBottom + 6), isSelected);

      if (isSelected) {
        // Glowing halo for selected active node
        canvas.drawCircle(p, 12, Paint()..color = tealColor.withValues(alpha: 0.20));
        canvas.drawCircle(p, 7, Paint()..color = Colors.white);
        canvas.drawCircle(p, 4.5, Paint()..color = tealDarkColor);

        // Value text bubble above node
        final double total = (data[i]['totalWeight'] as num).toDouble();
        _drawValueBubble(canvas, "${total.toStringAsFixed(1)}g", Offset(p.dx, p.dy - 12));
      } else {
        // Inactive standard node
        canvas.drawCircle(p, 5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3.5, Paint()..color = tealColor);
      }
    }
  }

  void _drawYAxisLabel(Canvas canvas, String text, Offset rightCenter) {
    final span = TextSpan(
      text: text,
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textMutedColor,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout();
    tp.paint(canvas, Offset(rightCenter.dx - tp.width, rightCenter.dy - (tp.height / 2)));
  }

  void _drawXAxisLabel(Canvas canvas, String text, Offset topCenter, bool isSelected) {
    final span = TextSpan(
      text: text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? tealDarkColor : textMutedColor,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, Offset(topCenter.dx - (tp.width / 2), topCenter.dy));
  }

  void _drawValueBubble(Canvas canvas, String text, Offset bottomCenter) {
    final span = TextSpan(
      text: text,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    const double hPad = 6.0;
    const double vPad = 2.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(bottomCenter.dx, bottomCenter.dy - (tp.height / 2)),
        width: tp.width + (hPad * 2),
        height: tp.height + (vPad * 2),
      ),
      const Radius.circular(6),
    );

    canvas.drawRRect(rrect, Paint()..color = tealDarkColor);
    tp.paint(canvas, Offset(bottomCenter.dx - (tp.width / 2), bottomCenter.dy - tp.height - vPad));
  }

  @override
  bool shouldRepaint(covariant WeeklyGrowthLinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.tealColor != tealColor;
  }
}