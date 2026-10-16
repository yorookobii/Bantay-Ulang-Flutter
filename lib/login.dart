import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'offline/offline_widgets.dart';

/// Branding shown once at full app launch, before the existing session gate.
class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key, this.sessionEntryBuilder});

  /// Optional builder lets navigation tests exercise the real session gate
  /// without opening a Firebase-backed dashboard.
  final WidgetBuilder? sessionEntryBuilder;

  static const displayDuration = Duration(milliseconds: 2500);
  static const fadeDuration = Duration(milliseconds: 350);

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  ModalRoute<dynamic>? _route;
  AppLifecycleState? _lifecycle;
  bool _elapsed = false;
  bool _finishScheduled = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(StartupSplashPage.displayDuration, () {
        _elapsed = true;
        _scheduleFinish();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of subscribes to current-route changes, including dialogs.
    _route = ModalRoute.of(context);
    _scheduleFinish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _scheduleFinish();
  }

  void _scheduleFinish() {
    if (!mounted || !_elapsed || _navigating || _finishScheduled) return;
    if (_lifecycle != null && _lifecycle != AppLifecycleState.resumed) return;
    if (_route?.isCurrent == false) return;
    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishScheduled = false;
      if (!mounted || _navigating || _route?.isCurrent == false) return;
      if (_lifecycle != null && _lifecycle != AppLifecycleState.resumed) return;
      _navigating = true;
      Navigator.of(context).pushReplacement<void, void>(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/session'),
          transitionDuration: StartupSplashPage.fadeDuration,
          reverseTransitionDuration: StartupSplashPage.fadeDuration,
          pageBuilder: (context, _, _) =>
              widget.sessionEntryBuilder?.call(context) ?? const SessionEntry(),
          transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
            child: child,
          ),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFF0F766E),
              BlendMode.color,
            ),
            child: Image.asset('assets/img/3.png', fit: BoxFit.cover),
          ),
          ColoredBox(color: Colors.white.withValues(alpha: 0.72)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.85,
                colors: [
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final logoSize = (constraints.maxHeight * 0.3).clamp(
                      104.0,
                      184.0,
                    );
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: logoSize,
                            height: logoSize,
                            padding: EdgeInsets.all(logoSize * 0.08),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0B274C,
                                  ).withValues(alpha: 0.12),
                                  blurRadius: 28,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/img/logo_BU.png',
                                fit: BoxFit.contain,
                                semanticLabel: 'Bantay Ulang logo',
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Bantay Ulang',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F766E),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              'Keep track of your ulang and plants',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6B7280),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
