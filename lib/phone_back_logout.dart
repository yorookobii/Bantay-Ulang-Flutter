import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logout_confirmation_dialog.dart';
import 'offline/session_controller.dart';

/// Counts platform Back events without counting on-screen navigation actions.
class PhoneBackLogoutCoordinator extends NavigatorObserver
    with WidgetsBindingObserver {
  PhoneBackLogoutCoordinator({
    required this.navigatorKey,
    required this.messengerKey,
    required this.session,
    required this.logout,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final SessionController? session;
  final Future<void> Function() logout;

  final Set<bool Function()> _overlayDismissals = {};
  Route<dynamic>? _topRoute;
  Timer? _backWindow;
  String? _owner;
  int? _epoch;
  bool _allowed = false;
  bool _navigatorCanHandlePop = false;
  bool _delegatingBack = false;
  bool _confirmationOpen = false;
  bool _logoutInProgress = false;
  bool _gestureActive = false;
  bool _started = false;
  bool _disposed = false;

  // Register before MaterialApp creates WidgetsApp's navigation observer.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    session?.addListener(_sessionChanged);
    _sessionChanged();
  }

  void reset() {
    _backWindow?.cancel();
    _backWindow = null;
  }

  VoidCallback registerOverlayDismissal(bool Function() dismiss) {
    _overlayDismissals.add(dismiss);
    return () => _overlayDismissals.remove(dismiss);
  }

  void _sessionChanged() {
    final allowed = session?.canAccess ?? false;
    if (_owner != session?.uid ||
        _epoch != session?.accessEpoch ||
        _allowed != allowed) {
      reset();
      _gestureActive = false;
    }
    _owner = session?.uid;
    _epoch = session?.accessEpoch;
    _allowed = allowed;
    _updatePlatformBack();
  }

  bool onNavigationNotification(NavigationNotification notification) {
    _navigatorCanHandlePop = notification.canHandlePop;
    _updatePlatformBack();
    return true;
  }

  void _updatePlatformBack() {
    if (_disposed) return;
    unawaited(
      SystemNavigator.setFrameworkHandlesBack(
        (session?.canAccess ?? false) || _navigatorCanHandlePop,
      ),
    );
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _topRoute = topRoute;
    if (!_delegatingBack) reset();
  }

  @override
  Future<bool> didPopRoute() => handleSystemBack();

  Future<bool> handleSystemBack() async {
    if (_disposed) return false;
    if (_logoutInProgress || _delegatingBack) return true;
    if (session?.canAccess != true) return false;
    final nav = navigatorKey.currentState;
    if (nav == null) return false;

    if (WidgetsBinding.instance.platformDispatcher.views.any(
      (view) => view.viewInsets.bottom > 0,
    )) {
      reset();
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      return true;
    }

    if (_topRoute is PopupRoute ||
        (_topRoute?.willHandlePopInternally ?? false)) {
      reset();
      await _navigateBack(nav);
      return true;
    }
    for (final dismiss in List<bool Function()>.of(_overlayDismissals)) {
      if (dismiss()) {
        reset();
        return true;
      }
    }
    if (_confirmationOpen) return true;

    if (_backWindow?.isActive == true) {
      reset();
      final context = nav.overlay?.context;
      if (context != null) unawaited(requestLogout(context));
      return true;
    }

    _backWindow = Timer(const Duration(seconds: 2), reset);
    if (!await _navigateBack(nav)) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Press Back again to log out'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  Future<bool> _navigateBack(NavigatorState nav) async {
    _delegatingBack = true;
    try {
      return await nav.maybePop();
    } finally {
      _delegatingBack = false;
    }
  }

  /// Profile uses this directly, without requiring a preceding Back press.
  Future<void> requestLogout(BuildContext context) async {
    reset();
    if (_disposed || _confirmationOpen || _logoutInProgress) return;
    if (session != null && !session!.canAccess) return;
    final owner = session?.uid;
    final epoch = session?.accessEpoch;
    _confirmationOpen = true;
    try {
      final confirmed = await showLogoutConfirmationDialog(context);
      if (confirmed != true || _disposed) return;
      if (session != null &&
          (!session!.canAccess ||
              session!.uid != owner ||
              session!.accessEpoch != epoch)) {
        return;
      }
      _logoutInProgress = true;
      try {
        await logout();
        // With a session service, SessionNavigationGuard clears protected routes.
        if (session == null && !_disposed) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/login',
            (_) => false,
          );
        }
      } catch (_) {
        if (!_disposed) {
          _showLogoutFailure();
        }
      } finally {
        _logoutInProgress = false;
      }
    } finally {
      _confirmationOpen = false;
      reset();
    }
  }

  void _showLogoutFailure() {
    // The session guard may replace the protected scaffold on the next frame.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (_disposed) return;
      binding.addPostFrameCallback((_) {
        if (_disposed) return;
        messengerKey.currentState?.clearSnackBars();
        messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Unable to finish logging out. Please try again.'),
          ),
        );
      });
      binding.scheduleFrame();
    });
    binding.scheduleFrame();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _gestureActive = !_disposed && (session?.canAccess == true);
    return _gestureActive;
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    unawaited(handleSystemBack());
  }

  @override
  void handleCancelBackGesture() {
    _gestureActive = false;
  }

  @override
  void didChangeMetrics() => reset();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      reset();
      _gestureActive = false;
    } else {
      _updatePlatformBack();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reset();
    _overlayDismissals.clear();
    session?.removeListener(_sessionChanged);
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}

class PhoneBackLogoutScope extends InheritedWidget {
  const PhoneBackLogoutScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final PhoneBackLogoutCoordinator coordinator;

  static PhoneBackLogoutCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PhoneBackLogoutScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(PhoneBackLogoutScope oldWidget) =>
      coordinator != oldWidget.coordinator;
}
