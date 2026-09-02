import 'package:flutter/foundation.dart';

class WebNotificationServiceImpl {
  static Future<bool> requestPermission() async => true;
  static void showIncomingCallNotification({
    required String callerName,
    required String callType,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) {}
  static void closeActiveNotification() {}
}
