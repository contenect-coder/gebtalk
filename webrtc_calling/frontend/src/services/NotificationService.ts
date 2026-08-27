import { NotificationPayload } from '../types/calling.js';

export interface PushNotificationService {
  requestPermission(): Promise<boolean>;
  showIncomingCall(payload: NotificationPayload): void;
  cancelNotification(callId: string): void;
}

export class MockPushNotificationService implements PushNotificationService {
  private activeNotifications: Map<string, Notification> = new Map();

  public async requestPermission(): Promise<boolean> {
    if (!('Notification' in window)) {
      console.warn('[PushNotification] Browser notifications not supported in this environment');
      return false;
    }
    if (Notification.permission === 'granted') return true;
    if (Notification.permission !== 'denied') {
      const permission = await Notification.requestPermission();
      return permission === 'granted';
    }
    return false;
  }

  public showIncomingCall(payload: NotificationPayload): void {
    console.log(`[PushNotification] Incoming call push simulated:`, payload);

    if ('Notification' in window && Notification.permission === 'granted') {
      try {
        const notif = new Notification(`Incoming Call from ${payload.callerName}`, {
          body: `User ID: ${payload.callerId} is calling you via GEBTALK Internet Voice`,
          tag: payload.callId,
          requireInteraction: true,
        });

        this.activeNotifications.set(payload.callId, notif);
      } catch (e) {
        console.warn('[PushNotification] Failed to trigger native notification:', e);
      }
    }
  }

  public cancelNotification(callId: string): void {
    const notif = this.activeNotifications.get(callId);
    if (notif) {
      notif.close();
      this.activeNotifications.delete(callId);
    }
  }
}
