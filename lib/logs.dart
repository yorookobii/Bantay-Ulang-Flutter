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

class _LogsPageState extends State<LogsPage> with SingleTickerProviderStateMixin {
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

  // Ulang form controllers
  final sizeController = TextEditingController();
  final weightController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  // Plant form controllers
  final plantHeightController = TextEditingController();
  final plantConditionController = TextEditingController();
  String? selectedPlantStage;
  String? selectedPlantName;
  DateTime plantDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _subscribeLogs();
    _subscribeGrowthRecords();
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
      onError: (error) => debugPrint('Growth records subscription error: $error'),
    );
  }

  Future<void> _recalculateAndUpdateGrowthIndicators() async {
    try {
      final recordsSnap = await FirebaseFirestore.instance
          .collection('ulang_growth_records')
          .get();

      if (recordsSnap.docs.isEmpty) return;

      double totalWeight = 0;
      for (final doc in recordsSnap.docs) {
        totalWeight += (doc.data()['weight'] as num?)?.toDouble() ?? 0;
      }
      final avgWeight = totalWeight / recordsSnap.docs.length;

      final indicatorsSnap = await FirebaseFirestore.instance
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (indicatorsSnap.docs.isEmpty) return;

      final indicatorDoc = indicatorsSnap.docs.first;
      final data = indicatorDoc.data() as Map<String, dynamic>;
      final initialStock = (data['initialStock'] as num?)?.toDouble() ?? 0;
      final survivalRate = (data['survivalRate'] as num?)?.toDouble() ?? 0;

      final updates = <String, dynamic>{'avgWeightPerPiece': avgWeight};
      if (initialStock > 0 && survivalRate > 0) {
        updates['expectedYield'] =
            initialStock * (survivalRate / 100) * (avgWeight / 1000);
      }

      await indicatorDoc.reference.update(updates);
    } catch (e) {
      debugPrint('Failed to recalculate growth indicators: $e');
    }
  }

  @override
  void dispose() {
    _logsSub?.cancel();
    _growthRecordsSub?.cancel();
    _fadeController.dispose();
    sizeController.dispose();
    weightController.dispose();
    plantHeightController.dispose();
    plantConditionController.dispose();
    super.dispose();
  }

  // =======================
  // Save Handlers
  // =======================

  Future<void> _saveUlangLog() async {
    if (_isSavingUlang) return;
    if (sizeController.text.trim().isEmpty || weightController.text.trim().isEmpty) return;
    setState(() => _isSavingUlang = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final sizeNum = double.tryParse(sizeController.text.trim()) ?? 0;
      final weightNum = double.tryParse(weightController.text.trim()) ?? 0;

      await FirebaseFirestore.instance.collection('logs').add({
        'title': 'Ulang Log',
        'description': 'Laki: ${sizeController.text.trim()}cm • Timbang: ${weightController.text.trim()}g',
        'type': 'ulang',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'size': sizeController.text.trim(),
        'weight': weightController.text.trim(),
        'observedAt': Timestamp.fromDate(selectedDate),
      });

      await FirebaseFirestore.instance.collection('ulang_growth_records').add({
        'size': sizeNum,
        'weight': weightNum,
        'recordedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _recalculateAndUpdateGrowthIndicators();

      sizeController.clear();
      weightController.clear();
      _showSuccessSnackbar("Matagumpay na na-save ang tala ng Ulang.");
    } finally {
      if (mounted) setState(() => _isSavingUlang = false);
    }
  }

  Future<void> _savePlantLog() async {
    if (_isSavingPlant) return;
    if (selectedPlantName == null ||
        plantHeightController.text.trim().isEmpty ||
        plantConditionController.text.trim().isEmpty ||
        selectedPlantStage == null) return;
    setState(() => _isSavingPlant = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance.collection('logs').add({
        'title': selectedPlantName!,
        'description':
            'Taas: ${plantHeightController.text.trim()}cm • Yugto: $selectedPlantStage • Kondisyon: ${plantConditionController.text.trim()}',
        'type': 'plant',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'plantName': selectedPlantName,
        'height': plantHeightController.text.trim(),
        'condition': plantConditionController.text.trim(),
        'stage': selectedPlantStage,
        'observedAt': Timestamp.fromDate(plantDate),
      });
      plantHeightController.clear();
      plantConditionController.clear();
      setState(() {
        selectedPlantName = null;
        selectedPlantStage = null;
      });
      _showSuccessSnackbar("Matagumpay na na-save ang tala ng Tanim.");
    } finally {
      if (mounted) setState(() => _isSavingPlant = false);
    }
  }

  // =======================
  // Logic Helpers
  // =======================

  double parseWeight(String weight) {
    return double.tryParse(weight.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
  }

  List<Map<String, dynamic>> getWeeklyWeightData() {
    final now = DateTime.now();
    return List.generate(4, (i) {
      final weekEnd = now.subtract(Duration(days: (3 - i) * 7));
      final weekStart = weekEnd.subtract(const Duration(days: 6));
      double total = 0;
      for (final doc in _ulangGrowthRecords) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['createdAt'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate();
        if (date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
            date.isBefore(weekEnd.add(const Duration(days: 1)))) {
          total += (data['weight'] as num?)?.toDouble() ?? 0;
        }
      }
      return {
        'label': "${weekStart.month}/${weekStart.day}",
        'total': total,
      };
    });
  }

  Future<void> _selectDate(BuildContext context, bool isUlang) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isUlang ? selectedDate : plantDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: teal,
            onPrimary: Colors.white,
            onSurface: textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isUlang) {
          selectedDate = picked;
        } else {
          plantDate = picked;
        }
      });
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ],
        ),
        backgroundColor: tealDark,
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
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
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
                            Icon(Icons.cloud_off_rounded, size: 56, color: textMuted),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontSize: 15, color: textMuted, fontWeight: FontWeight.w500),
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
                              label: Text("Subukan Muli", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TabBarView(
                  children: [
                    _buildUlangTab(),
                    _buildPlantTab(),
                  ],
                ),
        ),
      ),
    );
  }

  // =======================
  // Ulang Tab UI
  // =======================

  Widget _buildUlangTab() {
    final weeklyData = getWeeklyWeightData();
    final maxWeight = weeklyData.map((e) => e['total'] as double).fold(0.0, max);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Tala ng Ulang", "I-record ang sukat at timbang ng mga ulang."),
          const SizedBox(height: 24),

          _statCard("Kabuuang Tala", _ulangLogs.length.toString(), Icons.pets),
          const SizedBox(height: 24),

          _buildSectionTitle("Lingguhang Timbang"),
          const SizedBox(height: 12),
          _buildChartCard(weeklyData, maxWeight),
          const SizedBox(height: 24),

          _buildSectionTitle("Magdagdag ng Tala"),
          const SizedBox(height: 12),
          _buildUlangForm(),
          const SizedBox(height: 24),

          if (_ulangLogs.isNotEmpty) ...[
            _buildSectionTitle("Mga Nakaraang Tala"),
            const SizedBox(height: 12),
            ..._ulangLogs.map((doc) => _buildUlangLogCard(doc)),
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
          _buildHeader("Tala ng Tanim", "I-record ang paglaki at kondisyon ng mga halaman."),
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
            ..._plantLogs.map((doc) => _buildPlantLogCard(doc)),
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
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tealLight, borderRadius: BorderRadius.circular(12)),
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
                style: GoogleFonts.poppins(fontSize: 14, color: textMuted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(List<Map<String, dynamic>> weeklyData, double maxWeight) {
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
                  width: 50,
                  child: Text(
                    d['label'],
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textMuted),
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
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: tealDark),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Petsa: ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}",
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: textDark),
              ),
              TextButton.icon(
                onPressed: () => _selectDate(context, true),
                icon: Icon(Icons.calendar_month, color: teal, size: 20),
                label: Text("Palitan", style: GoogleFonts.poppins(color: teal, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInputField(sizeController, "Laki (cm)", keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          _buildInputField(weightController, "Bigat (g)", keyboardType: TextInputType.number),
          const SizedBox(height: 20),
          _buildSaveButton(
            _isSavingUlang ? "Sine-save..." : "I-save ang Ulang Log",
            _isSavingUlang ? null : () => _saveUlangLog(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Petsa: ${plantDate.month}/${plantDate.day}/${plantDate.year}",
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: textDark),
              ),
              TextButton.icon(
                onPressed: () => _selectDate(context, false),
                icon: Icon(Icons.calendar_month, color: teal, size: 20),
                label: Text("Palitan", style: GoogleFonts.poppins(color: teal, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCustomDropdown(
            value: selectedPlantName,
            hint: "Pumili ng uri ng tanim",
            label: "Pangalan ng Tanim",
            items: const [
              DropdownMenuItem(value: 'Mint', child: Text('Mint')),
              DropdownMenuItem(value: 'Oregano', child: Text('Oregano')),
              DropdownMenuItem(value: 'Kangkong', child: Text('Kangkong')),
            ],
            onChanged: (value) => setState(() => selectedPlantName = value),
          ),
          const SizedBox(height: 16),
          _buildInputField(plantHeightController, "Taas (cm)", keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          _buildInputField(plantConditionController, "Kondisyon (hal. Malusog, Dilaw)"),
          const SizedBox(height: 16),
          _buildCustomDropdown(
            value: selectedPlantStage,
            hint: "Pumili ng yugto ng paglaki",
            label: "Yugto ng Paglaki",
            items: const [
              DropdownMenuItem(value: 'Seedling', child: Text('Seedling (Punla)')),
              DropdownMenuItem(value: 'Vegetative', child: Text('Vegetative (Lumalaki)')),
              DropdownMenuItem(value: 'Pre-Flowering', child: Text('Pre-Flowering')),
              DropdownMenuItem(value: 'Harvest', child: Text('Harvest (Handa na anihin)')),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
      hint: Text(hint, style: GoogleFonts.poppins(fontSize: 14, color: textMuted)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      items: items,
      onChanged: onChanged,
      dropdownColor: Colors.white,
    );
  }

  Widget _buildUlangLogCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final size = data['size'] ?? '—';
    final weight = data['weight'] ?? '—';
    final ts = data['observedAt'] as Timestamp?;
    final date = ts?.toDate();
    final formattedDate = date != null
        ? "${date.month}/${date.day}/${date.year}"
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
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: seaBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.pets, color: seaBlue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Laki: $size cm",
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: teal),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Timbang: $weight g",
                  style: GoogleFonts.poppins(fontSize: 14, color: textMuted),
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
    final ts = data['observedAt'] as Timestamp?;
    final date = ts?.toDate();
    final formattedDate = date != null
        ? "${date.month}/${date.day}/${date.year}"
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
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.eco, color: Color(0xFF10B981), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Taas: ${height}cm • Yugto: $stage",
                  style: GoogleFonts.poppins(fontSize: 14, color: textMuted),
                ),
                if (condition.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "Kondisyon: $condition",
                      style: GoogleFonts.poppins(fontSize: 14, color: textMuted),
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
