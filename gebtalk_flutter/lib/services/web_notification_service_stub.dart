import 'package:flutter/foundation.dart';
import 'background_service.dart';

class WebNotificationServiceImpl {
  static Future<bool> requestPermission() async => true;

  static void showIncomingCallNotification({
    required String callerName,
    required String callType,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) {
    debugPrint('[WebNotificationStub] Native notification handled by GebtalkBackgroundService');
  }

  static void closeActiveNotification() {
    BackgroundService.setAppForeground(true);
  }
}

