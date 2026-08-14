import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const AndroidNotificationChannel _alertsChannel =
      AndroidNotificationChannel(
        'bantay_ulang_alerts',
        'Bantay Ulang Alerts',
        description: 'Important water quality and farm alerts.',
        importance: Importance.max,
      );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_alertsChannel);
      await android?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> showAlert({
    required String id,
    required String title,
    required String message,
    required bool isUrgent,
  }) async {
    if (kIsWeb) return;

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
      id.hashCode & 0x7fffffff,
      title,
      message,
      details,
      payload: id,
    );
  }
}
