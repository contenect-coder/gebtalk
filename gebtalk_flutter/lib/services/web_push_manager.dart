import 'package:flutter/foundation.dart';
import 'web_push_manager_stub.dart'
    if (dart.library.js_interop) 'web_push_manager_web.dart';

abstract class WebPushManager {
  static WebPushManager? _instance;
  static WebPushManager get instance => _instance ??= createWebPushManager();

  Future<String?> getNotificationPermission();
  Future<String?> getExistingSubscription();
  Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey);
  Future<bool> isServiceWorkerActive();
}
