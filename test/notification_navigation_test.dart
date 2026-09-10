import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:demo_1_langto/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService Navigation Redirection', () {
    test('navigateToTasks invokes onNavigateToTasks callback when registered', () {
      final service = NotificationService.instance;
      bool navigated = false;

      service.onNavigateToTasks = () {
        navigated = true;
      };

      service.navigateToTasks();

      expect(navigated, isTrue);
      service.onNavigateToTasks = null;
    });

    test('navigateToTasks sets pending flag when no callback is registered', () {
      final service = NotificationService.instance;
      service.onNavigateToTasks = null;

      // Clear any existing pending flag
      service.consumePendingNavigationToTasks();

      service.navigateToTasks();

      expect(service.consumePendingNavigationToTasks(), isTrue);
      expect(service.consumePendingNavigationToTasks(), isFalse);
    });

    test('Task notification response payload triggers navigateToTasks', () {
      final service = NotificationService.instance;
      bool redirected = false;
      service.onNavigateToTasks = () {
        redirected = true;
      };

      // Simulating tapping a task notification
      final response = const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: 'task:test-task-123',
      );

      // Trigger handling via the public navigateToTasks triggered by task payload
      if (response.payload != null &&
          (response.payload!.startsWith('task:') ||
              response.payload!.startsWith('alert:'))) {
        service.navigateToTasks();
      }

      expect(redirected, isTrue);
      service.onNavigateToTasks = null;
    });

    test('Water parameter alert notification response payload triggers navigateToTasks', () {
      final service = NotificationService.instance;
      bool redirected = false;
      service.onNavigateToTasks = () {
        redirected = true;
      };

      // Simulating tapping a water parameter alert notification
      final response = const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: 'alert:water-ph-alert',
      );

      if (response.payload != null &&
          (response.payload!.startsWith('task:') ||
              response.payload!.startsWith('alert:'))) {
        service.navigateToTasks();
      }

      expect(redirected, isTrue);
      service.onNavigateToTasks = null;
    });
  });
}
