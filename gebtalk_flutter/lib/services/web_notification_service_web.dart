import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebNotificationServiceImpl {
  static web.Notification? _activeCallNotification;

  static Future<bool> requestPermission() async {
    try {
      final permission = await web.Notification.requestPermission().toDart;
      return permission.toDart == 'granted';
    } catch (e) {
      debugPrint('[WebNotification] Error requesting permission: $e');
      return false;
    }
  }

  static void showIncomingCallNotification({
    required String callerName,
    required String callType,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) {
    try {
      if (web.Notification.permission != 'granted') return;
      
      closeActiveNotification();

      final options = web.NotificationOptions(
        body: 'Incoming $callType call from $callerName. Click to answer.',
        icon: 'assets/images/logo_icon.png',
        tag: 'gebtalk_incoming_call',
        requireInteraction: true,
      );

      _activeCallNotification = web.Notification('📞 $callerName is Calling', options);
      
      _activeCallNotification?.onclick = ((web.Event event) {
        try {
          web.window.focus();
          closeActiveNotification();
          onAnswer();
        } catch (_) {}
      }).toJS;
    } catch (e) {
      debugPrint('[WebNotification] Error showing notification: $e');
    }
  }

  static void closeActiveNotification() {
    try {
      _activeCallNotification?.close();
      _activeCallNotification = null;
    } catch (_) {}
  }
}
