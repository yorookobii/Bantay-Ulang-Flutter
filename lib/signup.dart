import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AuthMessageKind { success, error, warning, info }

class SignupPage extends StatefulWidget {
  const SignupPage({
    super.key,
    this.initialMessage,
    this.initialMessageKind = AuthMessageKind.info,
    this.showResendOption = false,
  });

  final String? initialMessage;
  final AuthMessageKind initialMessageKind;
  final bool showResendOption;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage>
    with SingleTickerProviderStateMixin {
  static const Color _teal = Color(0xFF0D9488);
  static const Color _tealDark = Color(0xFF0F766E);
  static const Color _seaBlue = Color(0xFF0369A1);
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AnimationController _rippleController;

  bool _isSignIn = true;
  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _showResendOption = false;
  String? _message;
  AuthMessageKind _messageKind = AuthMessageKind.info;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
    _message = widget.initialMessage;
    _messageKind = widget.initialMessageKind;
    _showResendOption = widget.showResendOption;
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _setMode(bool signIn) {
    if (_isLoading || signIn == _isSignIn) return;
    setState(() {
      _isSignIn = signIn;
      _message = null;
      _showResendOption = false;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
    _formKey.currentState?.reset();
  }

  void _setMessage(String message, AuthMessageKind kind) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageKind = kind;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _message = null;
      _showResendOption = false;
    });
    if (_isSignIn) {
      await _signIn();
    } else {
      await _signUp();
    }
  }

  Future<void> _signIn() async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = credential.user!;
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (data['role'] != 'user') {
        await FirebaseAuth.instance.signOut();
        _setMessage(
          'Ang mobile app ay para lamang sa farm users. Gamitin ang web portal para sa admin o technician account.',
          AuthMessageKind.error,
        );
        return;
      }
      if (refreshed == null || !refreshed.emailVerified) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _showResendOption = true);
        _setMessage(
          'Hindi pa verified ang iyong email. Tingnan ang verification link sa iyong inbox.',
          AuthMessageKind.info,
        );
        return;
      }
      if (data['emailVerified'] != true) {
        await doc.reference.update({'emailVerified': true});
      }
      if (data['status'] != 'active') {
        await FirebaseAuth.instance.signOut();
        _setMessage(
          'Verified na ang email mo. Hinihintay pa ang pag-apruba ng administrator.',
          AuthMessageKind.warning,
        );
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } on FirebaseAuthException catch (error) {
      _setMessage(_authErrorMessage(error.code), AuthMessageKind.error);
    } catch (_) {
      _setMessage(
        'Hindi makapag-log in ngayon. Subukan muli.',
        AuthMessageKind.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      await credential.user!.sendEmailVerification();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'email': _emailController.text.trim(),
            'fullName': _nameController.text.trim(),
            'role': 'user',
            'status': 'pending',
            'emailVerified': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final registeredEmail = _emailController.text.trim();
      setState(() {
        _isSignIn = true;
        _nameController.clear();
        _emailController.text = registeredEmail;
        _passwordController.clear();
        _confirmPasswordController.clear();
        _showResendOption = false;
      });
      _formKey.currentState?.reset();
      _setMessage(
        'Nagawa na ang account. I-verify ang email at hintayin ang pag-apruba ng administrator bago mag-log in.',
        AuthMessageKind.success,
      );
    } on FirebaseAuthException catch (error) {
      _setMessage(_authErrorMessage(error.code), AuthMessageKind.error);
    } catch (_) {
      _setMessage(
        'Hindi magawa ang account ngayon. Subukan muli.',
        AuthMessageKind.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _setMessage(
        'Ilagay ang email at password para maipadala muli ang verification link.',
        AuthMessageKind.info,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await credential.user!.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
      _setMessage(
        'Naipadala muli ang verification email. Tingnan ang iyong inbox.',
        AuthMessageKind.success,
      );
    } on FirebaseAuthException catch (error) {
      _setMessage(_authErrorMessage(error.code), AuthMessageKind.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      _setMessage(
        'Maglagay muna ng wastong email address.',
        AuthMessageKind.info,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _setMessage(
        'Naipadala ang password reset link. Tingnan ang iyong inbox.',
        AuthMessageKind.success,
      );
    } on FirebaseAuthException catch (error) {
      _setMessage(_authErrorMessage(error.code), AuthMessageKind.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mali ang email o password.';
      case 'email-already-in-use':
        return 'May account nang gumagamit ng email na ito.';
      case 'weak-password':
        return 'Masyadong mahina ang password.';
      case 'invalid-email':
        return 'Hindi wastong email address.';
      case 'too-many-requests':
        return 'Masyadong maraming attempt. Subukan muli mamaya.';
      case 'network-request-failed':
        return 'Walang maayos na koneksyon sa internet.';
      default:
        return 'May hindi inaasahang error. Subukan muli.';
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Kinakailangan ang $label.';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final required = _requiredValidator(value, 'email address');
    if (required != null) return required;
    if (!_isValidEmail(value!.trim())) return 'Hindi wastong email address.';
    return null;
  }

  String? _passwordValidator(String? value) {
    final required = _requiredValidator(value, 'password');
    if (required != null) return required;
    if (!_isSignIn && value!.length < 8) {
      return 'Gumamit ng hindi bababa sa 8 character.';
    }
    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    final required = _requiredValidator(value, 'kumpirmasyon ng password');
    if (required != null) return required;
    if (value != _passwordController.text) {
      return 'Hindi magkatugma ang mga password.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _rippleController,
            builder: (context, _) => WaterRippleBackground(
              animation: _rippleController.value,
              tealLight: const Color(0xFF5EEAD4),
              teal: _teal,
              deepsea: const Color(0xFF001F3F),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _teal.withValues(alpha: 0.05),
                  _seaBlue.withValues(alpha: 0.03),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildAuthCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard() {
    return GlassmorphicCard(
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeControl(),
              const SizedBox(height: 32),
              Text(
                _isSignIn ? 'Welcome Back' : 'Create Account',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: _tealDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isSignIn
                    ? 'Log in to your Bantay Ulang account'
                    : 'Join Bantay Ulang today',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _textMuted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 32),
              if (!_isSignIn) ...[
                _buildTextField(
                  controller: _nameController,
                  label: 'Buong Pangalan',
                  icon: Icons.person_outline,
                  validator: (value) =>
                      _requiredValidator(value, 'buong pangalan'),
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 22),
              ],
              _buildTextField(
                controller: _emailController,
                label: 'Email Address',
                icon: Icons.email_outlined,
                validator: _emailValidator,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 22),
              _buildPasswordField(
                controller: _passwordController,
                label: 'Password',
                visible: _passwordVisible,
                onVisibilityChanged: () {
                  setState(() => _passwordVisible = !_passwordVisible);
                },
                validator: _passwordValidator,
                autofillHint: _isSignIn
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
                textInputAction: _isSignIn
                    ? TextInputAction.done
                    : TextInputAction.next,
                onFieldSubmitted: _isSignIn ? (_) => _submit() : null,
              ),
              if (!_isSignIn) ...[
                const SizedBox(height: 7),
                Text(
                  'Gumamit ng hindi bababa sa 8 character.',
                  style: GoogleFonts.poppins(fontSize: 12, color: _textMuted),
                ),
                const SizedBox(height: 22),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: 'Kumpirmahin ang Password',
                  visible: _confirmPasswordVisible,
                  onVisibilityChanged: () {
                    setState(
                      () => _confirmPasswordVisible = !_confirmPasswordVisible,
                    );
                  },
                  validator: _confirmPasswordValidator,
                  autofillHint: AutofillHints.newPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              if (_isSignIn) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text('Nakalimutan ang Password?'),
                  ),
                ),
              ] else
                const SizedBox(height: 28),
              if (_message != null) ...[
                _buildMessagePanel(),
                const SizedBox(height: 14),
              ],
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_teal, _tealDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _teal.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _teal.withValues(alpha: 0.55),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isSignIn ? 'Mag-log in' : 'Gumawa ng Account',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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

  Widget _buildModeControl() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.8),
            Colors.white.withValues(alpha: 0.6),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        children: [
          _modeButton('Mag-log in', true),
          _modeButton('Gumawa ng Account', false),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool signIn) {
    final selected = _isSignIn == signIn;
    return Expanded(
      child: InkWell(
        onTap: () => _setMode(signIn),
        borderRadius: BorderRadius.circular(50),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [_teal, _tealDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(50),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _teal.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    required Iterable<String> autofillHints,
    required TextInputAction textInputAction,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 10),
        Container(
          decoration: _fieldShadow(),
          child: TextFormField(
            controller: controller,
            validator: validator,
            enabled: !_isLoading,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            style: GoogleFonts.poppins(fontSize: 15, color: _textDark),
            decoration: _inputDecoration(label, icon),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onVisibilityChanged,
    required String? Function(String?) validator,
    required String autofillHint,
    required TextInputAction textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 10),
        Container(
          decoration: _fieldShadow(),
          child: TextFormField(
            controller: controller,
            validator: validator,
            enabled: !_isLoading,
            obscureText: !visible,
            autofillHints: [autofillHint],
            textInputAction: textInputAction,
            onFieldSubmitted: onFieldSubmitted,
            style: GoogleFonts.poppins(fontSize: 15, color: _textDark),
            decoration: _inputDecoration(label, Icons.lock_outline).copyWith(
              suffixIcon: IconButton(
                tooltip: visible
                    ? 'Itago ang password'
                    : 'Ipakita ang password',
                onPressed: _isLoading ? null : onVisibilityChanged,
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _tealDark,
        letterSpacing: 0.3,
      ),
    );
  }

  BoxDecoration _fieldShadow() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: _teal.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    const borderColor = Color(0xFFD1D5DB);
    return InputDecoration(
      hintText: switch (label) {
        'Buong Pangalan' => 'John Doe',
        'Email Address' => 'you@example.com',
        'Kumpirmahin ang Password' => 'Confirm your password',
        _ => 'Enter your password',
      },
      prefixIcon: Icon(icon, color: _teal, size: 21),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.95),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: borderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _teal, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
    );
  }

  Widget _buildMessagePanel() {
    final (background, border, foreground, icon) = switch (_messageKind) {
      AuthMessageKind.success => (
        const Color(0xFFECFDF5),
        const Color(0xFFA7F3D0),
        const Color(0xFF047857),
        Icons.check_circle_outline,
      ),
      AuthMessageKind.warning => (
        const Color(0xFFFFFBEB),
        const Color(0xFFFDE68A),
        const Color(0xFFB45309),
        Icons.schedule_outlined,
      ),
      AuthMessageKind.info => (
        const Color(0xFFEFF6FF),
        const Color(0xFFBFDBFE),
        _seaBlue,
        Icons.info_outline,
      ),
      AuthMessageKind.error => (
        const Color(0xFFFEF2F2),
        const Color(0xFFFECACA),
        const Color(0xFFB91C1C),
        Icons.error_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _message!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    height: 1.4,
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (_showResendOption) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isLoading ? null : _resendVerification,
                icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
                label: const Text('Ipadala muli ang verification email'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GlassmorphicCard extends StatelessWidget {
  const GlassmorphicCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.85),
                Colors.white.withValues(alpha: 0.75),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
                spreadRadius: 2,
              ),
              BoxShadow(
                color: const Color(0xFF001F3F).withValues(alpha: 0.05),
                blurRadius: 60,
                offset: const Offset(0, 30),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class WaterRippleBackground extends StatelessWidget {
  const WaterRippleBackground({
    super.key,
    required this.animation,
    required this.tealLight,
    required this.teal,
    required this.deepsea,
  });

  final double animation;
  final Color tealLight;
  final Color teal;
  final Color deepsea;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            teal.withValues(alpha: 0.08),
            tealLight.withValues(alpha: 0.05),
          ],
          stops: const [0, 0.6, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 60,
            right: 40,
            child: _ripple(
              80 + (animation * 40),
              (1 - animation) * 0.1,
              tealLight,
            ),
          ),
          Positioned(
            bottom: 100,
            left: 30,
            child: _ripple(
              120 + (animation * 50),
              (1 - animation) * 0.08,
              teal,
            ),
          ),
          Positioned(
            top: 200,
            left: 100,
            child: _ripple(
              60 + (animation * 30),
              (1 - animation) * 0.06,
              deepsea,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ripple(double radius, double opacity, Color color) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: 40,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}
