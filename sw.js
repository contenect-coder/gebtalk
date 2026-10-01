// GEBTALK Background Web Push Service Worker
// Handles background incoming call alerts, push notifications, and app focus when closed/minimized

self.addEventListener('install', function(event) {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function(event) {
  console.log('[GEBTALK SW] Push event received:', event);
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'GEBTALK', body: event.data ? event.data.text() : 'New Notification' };
  }

  const type = data.type || 'message';
  let title = data.title || 'GEBTALK';
  let options = {
    body: data.body || 'You have a new update.',
    icon: 'icons/Icon-192.png',
    badge: 'favicon.png',
    tag: data.call_id ? 'call_' + data.call_id : 'gebtalk_push',
    data: data,
    requireInteraction: true,
    vibrate: [200, 100, 200, 100, 200, 100, 400]
  };

  if (type === 'incoming_call') {
    title = '📞 Incoming Call: ' + (data.caller_name || 'GebTalk User');
    options.body = 'Incoming ' + (data.call_type || 'Voice') + ' Call. Tap to answer.';
    options.actions = [
      { action: 'answer', title: '✅ Answer' },
      { action: 'decline', title: '❌ Decline' }
    ];
  } else if (type === 'test_push') {
    title = '🔔 GEBTALK TEST';
    options.body = data.body || 'Push notifications are working properly.';
  } else if (type === 'call_cancelled' || type === 'call_answered_elsewhere') {
    // Dismiss ringing notification immediately on all other devices
    event.waitUntil(
      self.registration.getNotifications({ tag: 'call_' + data.call_id }).then(function(notifications) {
        for (let n of notifications) {
          n.close();
        }
      })
    );
    return;
  }

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const data = event.notification.data || {};
  const action = event.action;

  let urlToOpen = '/';
  if (data.call_id) {
    urlToOpen = '/?call_id=' + encodeURIComponent(data.call_id) + (action ? '&action=' + encodeURIComponent(action) : '');
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (let client of clientList) {
        if (client.url && client.url.includes(self.location.origin) && 'focus' in client) {
          client.postMessage({ type: 'NOTIFICATION_CLICK', data: data, action: action });
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(urlToOpen);
      }
    })
  );
});
