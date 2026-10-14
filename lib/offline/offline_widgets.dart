import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../landing_page.dart';
import '../login.dart';
import '../notification_service.dart';
import 'offline_services.dart';
import 'session_controller.dart';

class SessionEntry extends StatefulWidget {
  const SessionEntry({super.key, this.dashboardBuilder});
  final WidgetBuilder? dashboardBuilder;
  @override
  State<SessionEntry> createState() => _SessionEntryState();
}

class _SessionEntryState extends State<SessionEntry> {
  bool _openedDashboard = false;
  @override
  Widget build(BuildContext context) {
    final service = OfflineServices.current;
    if (service == null) return const LoginPage();
    return AnimatedBuilder(
      animation: service.session,
      builder: (context, _) {
        final session = service.session;
        if (!session.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (session.canAccess) {
          // Login replaces the entire stack. Do not start a second dashboard
          // underneath the sign-in route while that replacement is pending.
          if (!_openedDashboard && ModalRoute.of(context)?.isCurrent == false) {
            return const SizedBox.shrink();
          }
          _openedDashboard = true;
          return KeyedSubtree(
            key: ValueKey(session.uid),
            child:
                widget.dashboardBuilder?.call(context) ?? const DashboardPage(),
          );
        }
        _openedDashboard = false;
        if (session.message == null) return const LoginPage();
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 16),
                    Text(session.message!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await session.refresh();
                      },
                      child: const Text('Check connection'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await service.logout();
                      },
                      child: const Text('Return to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Removes *all* protected routes when a lease is revoked, including a profile
/// page pushed with MaterialPageRoute on top of the dashboard.
class SessionNavigationGuard extends StatefulWidget {
  const SessionNavigationGuard({super.key, required this.child});
  final Widget child;
  @override
  State<SessionNavigationGuard> createState() => _SessionNavigationGuardState();
}

class _SessionNavigationGuardState extends State<SessionNavigationGuard> {
  bool _wasAllowed = false;
  bool _redirecting = false;
  @override
  void initState() {
    super.initState();
    _wasAllowed = OfflineServices.current?.session.canAccess ?? false;
    OfflineServices.current?.session.addListener(_changed);
  }

  void _changed() {
    final allowed = OfflineServices.current?.session.canAccess ?? false;
    if (_wasAllowed && !allowed) {
      setState(() => _redirecting = true);
      NotificationService.instance.onNavigateToTasks = null;
      NotificationService.instance.consumePendingNavigationToTasks();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (OfflineServices.current?.session.canAccess != true) {
          NotificationService.navigatorKey.currentState
              ?.pushNamedAndRemoveUntil('/session', (_) => false);
        }
        setState(() => _redirecting = false);
      });
    }
    _wasAllowed = allowed;
  }

  @override
  void dispose() {
    OfflineServices.current?.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(offstage: _redirecting, child: widget.child),
      if (_redirecting) const ColoredBox(color: Colors.white),
    ],
  );
}

/// One temporary notice per allowed offline period, shared by all routes.
class SessionOfflineNotice extends StatefulWidget {
  const SessionOfflineNotice({super.key, required this.child});
  final Widget child;
  @override
  State<SessionOfflineNotice> createState() => _SessionOfflineNoticeState();
}

class _SessionOfflineNoticeState extends State<SessionOfflineNotice> {
  SessionController? _session;
  Timer? _dismissTimer;
  bool _offlinePeriod = false;
  bool _visible = false;
  String? _owner;
  int? _epoch;
  int _noticeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _session = OfflineServices.current?.session;
    _session?.addListener(_changed);
    _updateNotice();
  }

  void _changed() {
    setState(_updateNotice);
  }

  void _updateNotice() {
    final session = _session;
    final offline =
        session != null &&
        session.ready &&
        session.canAccess &&
        !session.online;
    if (!offline) {
      ++_noticeGeneration;
      _dismissTimer?.cancel();
      _offlinePeriod = false;
      _visible = false;
      _owner = null;
      _epoch = null;
      return;
    }
    if (_offlinePeriod &&
        _owner == session.uid &&
        _epoch == session.accessEpoch) {
      return;
    }
    _offlinePeriod = true;
    _owner = session.uid;
    _epoch = session.accessEpoch;
    _visible = true;
    _dismissTimer?.cancel();
    final generation = ++_noticeGeneration;
    // Slow startup work must not consume the notice's display time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_visible || generation != _noticeGeneration) return;
      _dismissTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && generation == _noticeGeneration) {
          setState(() => _visible = false);
        }
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _session?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_visible)
        Positioned(
          left: 16,
          right: 16,
          bottom: 88 + MediaQuery.viewInsetsOf(context).bottom,
          child: IgnorePointer(
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Material(
                    color: const Color(0xFF0F766E),
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'This session is in offline mode.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CacheStatus extends ChangeNotifier {
  CacheStatus(this.source) : services = OfflineServices.current {
    owner = services?.session.uid;
    epoch = services?.session.accessEpoch;
    services?.session.addListener(_sessionChanged);
    if (services != null && owner != null) {
      loaded = services!.store
          .lastConfirmed(owner!, source)
          .then((time) {
            if (isCurrent && lastConfirmed == null) {
              lastConfirmed = time;
              notifyListeners();
            }
          })
          .catchError((Object _) {});
    }
  }
  final String source;
  final OfflineServices? services;
  late final String? owner;
  late final int? epoch;
  bool get isCurrent =>
      !_disposed &&
      (services == null ||
          identical(services, OfflineServices.current) &&
              services!.session.canAccess &&
              services!.session.uid == owner &&
              services!.session.accessEpoch == epoch);

  void _sessionChanged() {
    if (_disposed) return;
    if (!isCurrent) {
      hasData = false;
      lastConfirmed = null;
    }
    if (services?.session.online != true) fromCache = true;
    notifyListeners();
  }

  void reportError(Object error) {
    if (!isCurrent) return;
    unawaited(services?.reportReadError(error, owner, epoch));
  }

  Future<void> loaded = Future<void>.value();
  bool fromCache = true;
  bool hasData = false;
  DateTime? lastConfirmed;
  DateTime? _lastPersist;
  bool _disposed = false;
  bool canUse(SnapshotMetadata metadata) =>
      isCurrent && (!metadata.isFromCache || lastConfirmed != null);
  void observe(SnapshotMetadata metadata, {required bool hasData}) {
    if (!isCurrent) return;
    fromCache = metadata.isFromCache;
    this.hasData = hasData;
    if (!fromCache && !metadata.hasPendingWrites) {
      lastConfirmed = DateTime.now();
      if (services != null &&
          owner != null &&
          (_lastPersist == null ||
              lastConfirmed!.difference(_lastPersist!) >=
                  const Duration(minutes: 1))) {
        _lastPersist = lastConfirmed;
        unawaited(
          services!.store
              .confirmCache(owner!, source, lastConfirmed!)
              .catchError((Object _) {}),
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    services?.session.removeListener(_sessionChanged);
    super.dispose();
  }
}
