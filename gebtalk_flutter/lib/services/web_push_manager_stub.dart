import 'web_push_manager.dart';

WebPushManager createWebPushManager() => WebPushManagerStub();

class WebPushManagerStub implements WebPushManager {
  @override
  Future<String?> getNotificationPermission() async => 'not_supported';

  @override
  Future<String?> getExistingSubscription() async => null;

  @override
  Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey) async => {
    'error': 'Web Push is only supported on Web browsers / PWAs'
  };

  @override
  Future<bool> isServiceWorkerActive() async => false;
}
