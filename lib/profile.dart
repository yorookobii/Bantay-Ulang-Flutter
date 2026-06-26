import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'landing_page.dart';
import 'tasks.dart';
import 'yield.dart';
import 'logs.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  // Aquatic Color Palette
  final Color tealLight = const Color(0xFF5EEAD4);
  final Color teal = const Color(0xFF0D9488);
  final Color tealDark = const Color(0xFF0F766E);
  final Color seaBlue = const Color(0xFF0369A1);
  final Color deepsea = const Color(0xFF001F3F);

  late GlobalKey<ScaffoldState> _scaffoldKey;
  late AnimationController _fadeController;

  File? _profileImage;
  late TextEditingController _addressController;
  late TextEditingController _fullNameController;
  bool _isEditingAddress = false;
  bool _isEditingFullName = false;

  String _fullName = '';
  String _email = '';
  String _role = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  String get _initials {
    final parts = _fullName.trim().split(' ');
    if (parts.isEmpty || _fullName.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _scaffoldKey = GlobalKey<ScaffoldState>();
    _addressController = TextEditingController();
    _fullNameController = TextEditingController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      final data = doc.data() ?? {};
      setState(() {
        _fullName = data['fullName'] ?? '';
        _email = user.email ?? '';
        _role = data['role'] ?? 'user';
        _fullNameController.text = data['fullName'] ?? '';
        _addressController.text = data['address'] ?? '';
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('Failed to load user data: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Hindi ma-load ang profile. Subukan muli.';
      });
    }
  }

  Future<void> _updateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fullName': _fullNameController.text.trim(),
        'address': _addressController.text.trim(),
      });

      if (!mounted) return;

      setState(() {
        _fullName = _fullNameController.text.trim();
        _isSaving = false;
        _isEditingFullName = false;
        _isEditingAddress = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile updated.', style: GoogleFonts.poppins()),
          backgroundColor: teal,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hindi ma-update ang profile. Subukan muli.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _fullNameController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: _buildSidebar(context),
      appBar: _buildTopBar(context),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: teal))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 56, color: const Color(0xFF6B7280)),
                        const SizedBox(height: 16),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _loadError = null;
                            });
                            _loadUserData();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            "Subukan Muli",
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
              : FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "My Profile",
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F766E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 32),

              // Profile Picture Section
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(60),
                      border: Border.all(
                        color: teal.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: _profileImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(60),
                            child: Image.file(
                              _profileImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Center(
                            child: Text(
                              _initials,
                              style: GoogleFonts.poppins(
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                                color: teal,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: teal,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white,
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // User Information Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: teal.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: teal.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFullNameField(),
                    const SizedBox(height: 16),
                    _buildInfoField("Role", _role),
                    const SizedBox(height: 16),
                    _buildInfoField("Email Address", _email),
                    const SizedBox(height: 16),
                    _buildAddressField(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Update Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSaving ? null : _updateProfile,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [teal, tealDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: teal.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              "Update Account Information",
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Log Out Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: teal.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout, color: tealDark, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "Log Out",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: tealDark,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickImage() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          "Upload Image",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          "Note: Are you sure you want to use this picture?.",
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: teal,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Profile picture updated successfully!',
                      style: GoogleFonts.poppins(),
                    ),
                    backgroundColor: teal,
                    duration: const Duration(seconds: 2),
                  ),
                );
              });
            },
            child: Text(
              "Use Image",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Full Name",
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
                letterSpacing: 0.3,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isEditingFullName = !_isEditingFullName),
              child: Text(
                _isEditingFullName ? "Kanselahin" : "Edit",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: teal,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _isEditingFullName
            ? TextField(
                controller: _fullNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              )
            : Text(
                _fullNameController.text.isNotEmpty ? _fullNameController.text : _fullName,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              ),
      ],
    );
  }

  Widget _buildAddressField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Address",
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
                letterSpacing: 0.3,
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isEditingAddress = !_isEditingAddress;
                });
              },
              child: Text(
                "Edit",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: teal,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _isEditingAddress
            ? TextField(
                controller: _addressController,
                maxLines: 3,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: teal, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              )
            : Text(
                _addressController.text,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              ),
      ],
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7280),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Drawer _buildSidebar(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF15212E),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/img/logo_BU.png',
                      width: 28,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 28,
                        height: 24,
                        decoration: BoxDecoration(
                          color: teal,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.water_drop,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Bantay Ulang",
                    style: TextStyle(
                      color: Color(0xFFECF0F1),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Color(0xFF9CA3AF),
                      size: 16,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildNavLink(
                    Icons.home,
                    "Home",
                    context,
                    page: const DashboardPage(),
                  ),
                  _buildNavLink(
                    Icons.assignment_turned_in,
                    "Tasks",
                    context,
                    page: const TasksPage(),
                  ),
                  _buildNavLink(
                    Icons.show_chart,
                    "Yield",
                    context,
                    page: const YieldEstimationPage(),
                  ),
                  _buildNavLink(
                    Icons.list,
                    "Logs",
                    context,
                    page: const LogsPage(),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
              child: _buildNavLink(
                Icons.logout,
                "Log out",
                context,
                isLogout: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavLink(
    IconData icon,
    String title,
    BuildContext context, {
    Widget? page,
    bool isActive = false,
    bool isLogout = false,
  }) {
    return Material(
      color: isActive ? const Color(0x40859356) : Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          if (isLogout) {
            FirebaseAuth.instance.signOut();
            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
          } else if (page != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => page),
            );
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isActive ? const Color(0xFF10B981) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isLogout
                    ? const Color(0xFFF87171)
                    : (isActive
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFFBDC3C7)),
                size: 16,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isLogout
                      ? const Color(0xFFF87171)
                      : (isActive
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFFBDC3C7)),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
