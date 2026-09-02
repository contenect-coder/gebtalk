import 'package:flutter/foundation.dart';
import 'web_notification_service_stub.dart'
    if (dart.library.js_interop) 'web_notification_service_web.dart';

/// Service for handling system/browser desktop incoming call notifications
class WebNotificationService {
  static Future<bool> requestPermission() => WebNotificationServiceImpl.requestPermission();
  
  static void showIncomingCallNotification({
    required String callerName,
    required String callType,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) => WebNotificationServiceImpl.showIncomingCallNotification(
    callerName: callerName,
    callType: callType,
    onAnswer: onAnswer,
    onDecline: onDecline,
  );

  static void closeActiveNotification() => WebNotificationServiceImpl.closeActiveNotification();
}
