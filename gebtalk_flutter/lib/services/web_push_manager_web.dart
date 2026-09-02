import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'web_push_manager.dart';

@JS('getWebPushSubscription')
external JSPromise<JSString?> _jsGetWebPushSubscription();

@JS('subscribeWebPush')
external JSPromise<JSString?> _jsSubscribeWebPush(JSString vapidPublicKey);

WebPushManager createWebPushManager() => WebPushManagerWeb();

class WebPushManagerWeb implements WebPushManager {
  @override
  Future<String?> getNotificationPermission() async {
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  Future<String?> getExistingSubscription() async {
    try {
      final res = await _jsGetWebPushSubscription().toDart;
      return res?.toDart;
    } catch (e) {
      debugPrint('[WebPushManagerWeb] Error getting existing subscription: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey) async {
    try {
      final res = await _jsSubscribeWebPush(vapidPublicKey.toJS).toDart;
      if (res != null) {
        final str = res.toDart;
        final decoded = jsonDecode(str);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return {'error': 'No response from browser push manager'};
    } catch (e) {
      debugPrint('[WebPushManagerWeb] Subscribe error: $e');
      return {'error': e.toString()};
    }
  }

  @override
  Future<bool> isServiceWorkerActive() async {
    try {
      return web.window.navigator.serviceWorker != null;
    } catch (_) {
      return false;
    }
  }
}
