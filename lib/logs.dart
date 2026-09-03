import 'dart:async';
import 'dart:math';
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

  List<Map<String, dynamic>> getWeeklyWeightData() {
    final current = DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    return List.generate(4, (i) {
      final weekEnd = today.subtract(Duration(days: (3 - i) * 7));
      final weekStart = weekEnd.subtract(const Duration(days: 6));
      double total = 0;
      int count = 0;
      DateTime? latestObservation;
      for (final doc in _ulangGrowthRecords) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = (data['observedAt'] ?? data['createdAt']) as Timestamp?;
        if (ts == null) continue;
        final rawDate = ts.toDate();
        final date = DateTime(rawDate.year, rawDate.month, rawDate.day);
        if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
          total += (data['weight'] as num?)?.toDouble() ?? 0;
          count++;
          if (latestObservation == null || date.isAfter(latestObservation)) {
            latestObservation = date;
          }
        }
      }
      return {
        'label': _formatDateRange(weekStart, weekEnd),
        'total': total,
        'count': count,
        'latestObservation': latestObservation,
      };
    });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              message,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
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
    final weeklyData = getWeeklyWeightData();
    final maxWeight = weeklyData
        .map((e) => e['total'] as double)
        .fold(0.0, max);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            "Tala ng Ulang",
            "I-record ang sukat at timbang ng mga ulang.",
          ),
          const SizedBox(height: 24),

          _statCard("Kabuuang Tala", _ulangLogs.length.toString(), Icons.pets),
          const SizedBox(height: 24),

          if (_ulangLogs.isNotEmpty) ...[
            _buildLatestUlangLogSummary(_ulangLogs.first),
            const SizedBox(height: 24),
          ],

          _buildSectionTitle("Lingguhang Timbang"),
          const SizedBox(height: 12),
          _buildChartCard(weeklyData, maxWeight),
          const SizedBox(height: 24),

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
            ..._mortalityRecords.map(_buildMortalityLogCard),
            const SizedBox(height: 24),
          ],

          if (_ulangLogs.isNotEmpty) ...[
            _buildSectionTitle("Mga Nakaraang Tala ng Ulang"),
            const SizedBox(height: 12),
            ..._ulangLogs.map(_buildUlangLogCard),
          ],
        ],
      ),
    );
  }

  // =======================
  // Plant Tab UI
  // =======================

  Widget _buildPlantTab() {
    return SingleChildScrollView(
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
            ..._plantLogs.map(_buildPlantLogCard),
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

  Widget _buildChartCard(
    List<Map<String, dynamic>> weeklyData,
    double maxWeight,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: weeklyData.map((d) {
          final pct = maxWeight > 0 ? d['total'] / maxWeight : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d['label'],
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                      Text(
                        '${d['count']} tala',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct > 0 ? pct : 0.01,
                      child: Container(
                        decoration: BoxDecoration(
                          color: pct > 0 ? teal : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: Text(
                    "${(d['total'] as double).toStringAsFixed(1)} g",
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tealDark,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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