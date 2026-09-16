import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  VoidCallback? onNavigateToTasks;
  bool _pendingNavigationToTasks = false;

  bool consumePendingNavigationToTasks() {
    if (_pendingNavigationToTasks) {
      _pendingNavigationToTasks = false;
      return true;
    }
    return false;
  }

  static const AndroidNotificationChannel _alertsChannel =
      AndroidNotificationChannel(
        'bantay_ulang_alerts',
        'Bantay Ulang Alerts',
        description: 'Important water quality and farm alerts.',
        importance: Importance.max,
      );

  static const AndroidNotificationChannel _tasksChannel =
      AndroidNotificationChannel(
        'bantay_ulang_tasks',
        'Assigned Tasks',
        description: 'Notifications for new actions assigned to you.',
        importance: Importance.high,
      );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  late SharedPreferences _preferences;
  final Set<String> _shownNotificationKeys = <String>{};

  static const String _shownKeysPreference = 'shown_notification_keys';
  static const String _seenKeysPreference = 'seen_notification_keys';

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _shownNotificationKeys.addAll(
      _preferences.getStringList(_shownKeysPreference) ?? const <String>[],
    );

    if (kIsWeb) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null &&
          (payload.startsWith('task:') || payload.startsWith('alert:'))) {
        _pendingNavigationToTasks = true;
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_alertsChannel);
      await android?.createNotificationChannel(_tasksChannel);
      await android?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    if (payload.startsWith('task:') || payload.startsWith('alert:')) {
      navigateToTasks();
    }
  }

  void navigateToTasks() {
    if (onNavigateToTasks != null) {
      onNavigateToTasks!();
      return;
    }

    _pendingNavigationToTasks = true;
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/dashboard', (route) => false);
    }
  }

  Future<void> showAlert({
    required String id,
    required String title,
    required String message,
    required bool isUrgent,
  }) async {
    if (kIsWeb) return;
    final notificationKey = 'alert:$id';
    if (_shownNotificationKeys.contains(notificationKey)) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertsChannel.id,
        _alertsChannel.name,
        channelDescription: _alertsChannel.description,
        importance: isUrgent ? Importance.max : Importance.high,
        priority: isUrgent ? Priority.max : Priority.high,
        category: AndroidNotificationCategory.alarm,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      notificationKey.hashCode & 0x7fffffff,
      title,
      message,
      details,
      payload: notificationKey,
    );
    await _rememberShown(notificationKey);
  }

  Future<void> showTask({
    required String id,
    required String title,
    required String description,
  }) async {
    if (kIsWeb) return;
    final notificationKey = 'task:$id';
    if (_shownNotificationKeys.contains(notificationKey)) return;

    final body = description.trim().isEmpty
        ? 'May bago kang nakatalagang gawain.'
        : description.trim();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _tasksChannel.id,
        _tasksChannel.name,
        channelDescription: _tasksChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      notificationKey.hashCode & 0x7fffffff,
      'Bagong Gawain: $title',
      body,
      details,
      payload: notificationKey,
    );
    await _rememberShown(notificationKey);
  }

  Set<String> getSeenNotificationKeys() {
    return (_preferences.getStringList(_seenKeysPreference) ?? const <String>[])
        .toSet();
  }

  Future<void> markNotificationsSeen(Iterable<String> keys) async {
    final seen = getSeenNotificationKeys()..addAll(keys);
    await _preferences.setStringList(_seenKeysPreference, seen.toList());
  }

  Future<void> cancelNotification(String notificationKey) async {
    if (kIsWeb) return;
    await _plugin.cancel(notificationKey.hashCode & 0x7fffffff);
  }

  Future<void> resolveNotification(String notificationKey) async {
    await cancelNotification(notificationKey);
    _shownNotificationKeys.remove(notificationKey);
    await _preferences.setStringList(
      _shownKeysPreference,
      _shownNotificationKeys.toList(),
    );
    final seen = getSeenNotificationKeys()..remove(notificationKey);
    await _preferences.setStringList(_seenKeysPreference, seen.toList());
  }

  Future<void> _rememberShown(String key) async {
    _shownNotificationKeys.add(key);
    await _preferences.setStringList(
      _shownKeysPreference,
      _shownNotificationKeys.toList(),
    );
  }
}
