import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef OnAnswerCallCallback = void Function(String callId, String callerId, String callerName);
typedef OnOpenChatCallback = void Function(String contactId);

class BackgroundService {
  static const MethodChannel _channel = MethodChannel('gebtalk/background_service');

  static OnAnswerCallCallback? onAnswerCall;
  static OnOpenChatCallback? onOpenChat;
  static bool _isInitialized = false;

  static void initialize() {
    if (kIsWeb || _isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAnswerCall':
          try {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final callId = args['call_id']?.toString() ?? '';
            final callerId = args['caller_id']?.toString() ?? '';
            final callerName = args['caller_name']?.toString() ?? callerId;
            if (callId.isNotEmpty) {
              debugPrint('[BackgroundService] onAnswerCall received: $callId from $callerName');
              onAnswerCall?.call(callId, callerId, callerName);
            }
          } catch (e) {
            debugPrint('[BackgroundService] Error handling onAnswerCall: $e');
          }
          break;

        case 'onOpenChat':
          try {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final contactId = args['contact_id']?.toString() ?? '';
            if (contactId.isNotEmpty) {
              debugPrint('[BackgroundService] onOpenChat received: $contactId');
              onOpenChat?.call(contactId);
            }
          } catch (e) {
            debugPrint('[BackgroundService] Error handling onOpenChat: $e');
          }
          break;
      }
    });
  }

  static Future<void> start(String userId, String baseUrl, {String? authToken}) async {
    if (kIsWeb) return;
    initialize();
    try {
      await _channel.invokeMethod('startService', {
        'user_id': userId,
        'base_url': baseUrl,
        'auth_token': authToken ?? '',
      });
      debugPrint('[BackgroundService] Native background service started for $userId');
    } catch (e) {
      debugPrint('[BackgroundService] Failed to start native background service: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopService');
      debugPrint('[BackgroundService] Native background service stopped');
    } catch (e) {
      debugPrint('[BackgroundService] Failed to stop native background service: $e');
    }
  }

  static Future<void> setAppForeground(bool isForeground) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setAppForeground', {
        'is_foreground': isForeground,
      });
    } catch (_) {}
  }

  static Future<Map<String, String>?> checkInitialCall() async {
    if (kIsWeb) return null;
    initialize();
    try {
      final res = await _channel.invokeMethod('checkInitialCall');
      if (res is Map) {
        return Map<String, String>.from(res);
      }
    } catch (e) {
      debugPrint('[BackgroundService] checkInitialCall error: $e');
    }
    return null;
  }

  static Future<Map<String, String>?> checkInitialChat() async {
    if (kIsWeb) return null;
    initialize();
    try {
      final res = await _channel.invokeMethod('checkInitialChat');
      if (res is Map) {
        return Map<String, String>.from(res);
      }
    } catch (e) {
      debugPrint('[BackgroundService] checkInitialChat error: $e');
    }
    return null;
  }
}
