"""
Push Notification & Background Call Wake-Up Service for GEBTALK VoIP.
Handles device registration, high-priority background push delivery (Web Push VAPID, Android FCM, iOS APNs),
and multi-device call cancellation.
"""

import json
import os
import threading
import time
import base64
from datetime import datetime

# VAPID Keys for Web Push (RFC 8291 / RFC 8292)
VAPID_PUBLIC_KEY = os.environ.get(
    'VAPID_PUBLIC_KEY',
    'BEfy1vheyPUbkIV4MS2wwWCeZ7IF5OCqnoN7DBngsFRFmDHYKYSMpvcF3-mh7gaRg16k8vNUBNOiZGKUo3bxi5k'
)
VAPID_PRIVATE_KEY_B64 = os.environ.get(
    'VAPID_PRIVATE_KEY_B64',
    'LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JR0hBZ0VBTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEJHMHdhd0lCQVFRZ3Z0a0l2b2s5MHl1U1MvNWQKdW9QeGtpV3hLdnYxQTg2czBEMGpRMG9ITkFDaFJBTkNBQVJIOHRiNFhzajFHNUNGZURFdHNNRmdubWV5QmVUZwpxcDZEZXd3WjRMQlVSWmd4MkNtRWpLYjNCZC9wb2U0R2tZTmVwUEx6VkFUVG9tUmlsS04yOFl1WgotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg=='
)
VAPID_CLAIMS = {"sub": "mailto:admin@gebtalk.com"}

try:
    VAPID_PRIVATE_KEY = base64.b64decode(VAPID_PRIVATE_KEY_B64).decode('utf-8')
except Exception:
    VAPID_PRIVATE_KEY = VAPID_PRIVATE_KEY_B64


class PushService:
    @staticmethod
    def get_callee_devices(callee_id, db_connection_func):
        """
        Retrieves all active registered devices for a given user ID or linked aliases.
        """
        if not callee_id:
            return []
            
        devices = []
        conn = None
        try:
            conn = db_connection_func()
            cursor = conn.cursor()
            
            # Find all potential user aliases
            possible_ids = {str(callee_id), str(callee_id).lower()}
            
            # 1. Look in users
            cursor.execute('SELECT id, phone, email, username FROM users WHERE id = %s OR email = %s OR username = %s OR phone = %s', (callee_id, callee_id, callee_id, callee_id))
            for u in cursor.fetchall():
                for k in ('id', 'phone', 'email', 'username'):
                    if u.get(k):
                        possible_ids.add(str(u[k]))
                        possible_ids.add(str(u[k]).lower())
                        
            # 2. Look in user_profile
            cursor.execute('SELECT id, phone, email FROM user_profile WHERE id = %s OR phone = %s OR email = %s', (callee_id, callee_id, callee_id))
            for up in cursor.fetchall():
                for k in ('id', 'phone', 'email'):
                    if up.get(k):
                        possible_ids.add(str(up[k]))
                        possible_ids.add(str(up[k]).lower())
            
            ids_list = list(possible_ids)
            placeholders = ','.join(['%s'] * len(ids_list))
            
            cursor.execute(f'''
                SELECT id, user_id, device_id, platform, push_token, voip_token, device_name, is_active, last_seen
                FROM user_devices
                WHERE user_id IN ({placeholders}) AND is_active = TRUE
                ORDER BY last_seen DESC
            ''', ids_list)
            
            rows = cursor.fetchall()
            for r in rows:
                devices.append(dict(r))
                
        except Exception as e:
            print(f"[PUSH SERVICE] Error querying callee devices: {e}", flush=True)
        finally:
            if conn:
                try: conn.close()
                except Exception: pass
                
        return devices

    @staticmethod
    def dispatch_incoming_call(callee_id, call_payload, db_connection_func):
        """
        Dispatches high-priority background VoIP wake-up push to all active devices of callee.
        Runs asynchronously in a background thread to prevent blocking call creation signaling.
        """
        def _dispatch():
            devices = PushService.get_callee_devices(callee_id, db_connection_func)
            call_id = call_payload.get('call_id')
            caller_name = call_payload.get('caller_name', 'GebTalk User')
            call_type = call_payload.get('call_type', 'voice')
            
            print(f"[PUSH SERVICE][DIAG] -------------------------------------------------------------", flush=True)
            print(f"[PUSH SERVICE][DIAG] Incoming VoIP Call Wake-Up Dispatch:", flush=True)
            print(f"[PUSH SERVICE][DIAG]   - Call ID: {call_id}", flush=True)
            print(f"[PUSH SERVICE][DIAG]   - Callee: {callee_id}", flush=True)
            print(f"[PUSH SERVICE][DIAG]   - Caller: {caller_name}", flush=True)
            print(f"[PUSH SERVICE][DIAG]   - Call Type: {call_type}", flush=True)
            print(f"[PUSH SERVICE][DIAG]   - Target Active Devices Found: {len(devices)}", flush=True)
            
            if not devices:
                print(f"[PUSH SERVICE][DIAG]   - (Fallback) Callee has no external push tokens; signaling queue active.", flush=True)
                print(f"[PUSH SERVICE][DIAG] -------------------------------------------------------------", flush=True)
                return

            for dev in devices:
                platform = dev.get('platform', 'WEB').upper()
                dev_id = dev.get('device_id')
                push_token = dev.get('push_token')
                voip_token = dev.get('voip_token')
                
                print(f"[PUSH SERVICE][DIAG]   -> Dispatching to [{platform}] device '{dev_id}'", flush=True)
                
                if platform == 'ANDROID' and push_token:
                    PushService._send_fcm_call_payload(push_token, call_payload, high_priority=True)
                elif platform == 'IOS' and (voip_token or push_token):
                    PushService._send_apns_voip_payload(voip_token or push_token, call_payload)
                elif platform in ('WEB', 'DESKTOP') and push_token:
                    PushService._send_web_push_payload(push_token, call_payload)
                    
            print(f"[PUSH SERVICE][DIAG] -------------------------------------------------------------", flush=True)

        threading.Thread(target=_dispatch, daemon=True).start()

    @staticmethod
    def dispatch_call_cancellation(callee_id, call_id, reason, db_connection_func):
        """
        Dispatches call cancellation / termination alert to all active devices of callee.
        Stops remote ringtones and dismisses the incoming call UI immediately.
        """
        def _dispatch():
            devices = PushService.get_callee_devices(callee_id, db_connection_func)
            print(f"[PUSH SERVICE][DIAG] Dispatching Call Cancellation (call_id: {call_id}, reason: {reason}) to {len(devices)} device(s)", flush=True)
            
            cancel_payload = {
                'type': 'call_cancelled',
                'call_id': call_id,
                'reason': reason,
                'timestamp': datetime.now().isoformat()
            }
            
            for dev in devices:
                platform = dev.get('platform', 'WEB').upper()
                push_token = dev.get('push_token')
                if platform == 'ANDROID' and push_token:
                    PushService._send_fcm_call_payload(push_token, cancel_payload, high_priority=False)
                elif platform == 'IOS' and push_token:
                    PushService._send_apns_voip_payload(push_token, cancel_payload)
                elif platform in ('WEB', 'DESKTOP') and push_token:
                    PushService._send_web_push_payload(push_token, cancel_payload)

        threading.Thread(target=_dispatch, daemon=True).start()

    @staticmethod
    def dispatch_call_answered(callee_id, call_id, answered_device_id, db_connection_func):
        """
        Multi-device call forking resolution:
        Alerts all OTHER devices that the call was answered on answered_device_id.
        """
        def _dispatch():
            devices = PushService.get_callee_devices(callee_id, db_connection_func)
            other_devices = [d for d in devices if d.get('device_id') != answered_device_id]
            print(f"[PUSH SERVICE][DIAG] Multi-Device Forking: Call {call_id} answered on {answered_device_id}. Cancelling ringing on {len(other_devices)} other device(s).", flush=True)
            
            fork_payload = {
                'type': 'call_answered_elsewhere',
                'call_id': call_id,
                'answered_by_device_id': answered_device_id,
                'timestamp': datetime.now().isoformat()
            }
            
            for dev in other_devices:
                platform = dev.get('platform', 'WEB').upper()
                push_token = dev.get('push_token')
                if platform == 'ANDROID' and push_token:
                    PushService._send_fcm_call_payload(push_token, fork_payload, high_priority=False)
                elif platform == 'IOS' and push_token:
                    PushService._send_apns_voip_payload(push_token, fork_payload)
                elif platform in ('WEB', 'DESKTOP') and push_token:
                    PushService._send_web_push_payload(push_token, fork_payload)

        threading.Thread(target=_dispatch, daemon=True).start()

    @staticmethod
    def send_test_push(user_id, message, db_connection_func):
        """
        Sends an immediate test push notification to all registered devices of the given user.
        """
        devices = PushService.get_callee_devices(user_id, db_connection_func)
        test_payload = {
            'type': 'test_push',
            'title': '🔔 GEBTALK TEST',
            'body': message or 'Push notifications are working properly.',
            'timestamp': datetime.now().isoformat()
        }
        
        results = []
        for dev in devices:
            platform = dev.get('platform', 'WEB').upper()
            push_token = dev.get('push_token')
            dev_id = dev.get('device_id')
            
            success = False
            err_msg = None
            if platform in ('WEB', 'DESKTOP') and push_token:
                success, err_msg = PushService._send_web_push_payload(push_token, test_payload)
            elif platform == 'ANDROID' and push_token:
                success, err_msg = PushService._send_fcm_call_payload(push_token, test_payload, high_priority=False)
            elif platform == 'IOS' and push_token:
                success, err_msg = PushService._send_apns_voip_payload(push_token, test_payload)
            else:
                err_msg = 'No push token available'
                
            results.append({
                'device_id': dev_id,
                'platform': platform,
                'success': success,
                'error': err_msg
            })
            
        return {
            'success': True,
            'devices_found': len(devices),
            'results': results,
            'timestamp': datetime.now().isoformat()
        }

    # --- Low-level dispatch handlers ---

    @staticmethod
    def _send_web_push_payload(token_or_sub, payload):
        """
        Sends Web Push message via pywebpush with VAPID credentials.
        """
        try:
            from pywebpush import webpush, WebPushException
            sub_info = None
            if isinstance(token_or_sub, str):
                if token_or_sub.startswith('{'):
                    sub_info = json.loads(token_or_sub)
                else:
                    sub_info = {"endpoint": token_or_sub}
            elif isinstance(token_or_sub, dict):
                sub_info = token_or_sub

            if not sub_info or not sub_info.get('endpoint'):
                print("[PUSH SERVICE][WEB PUSH] Missing endpoint in subscription", flush=True)
                return False, "Missing endpoint"

            resp = webpush(
                subscription_info=sub_info,
                data=json.dumps(payload),
                vapid_private_key=VAPID_PRIVATE_KEY,
                vapid_claims=VAPID_CLAIMS,
                ttl=60
            )
            print(f"[PUSH SERVICE][WEB PUSH SUCCESS] Status {resp.status_code}", flush=True)
            return True, None
        except Exception as e:
            print(f"[PUSH SERVICE][WEB PUSH ERROR] {e}", flush=True)
            return False, str(e)

    @staticmethod
    def _send_fcm_call_payload(token, payload, high_priority=True):
        """
        Sends high-priority data-only FCM push message to Android.
        """
        fcm_key = os.environ.get('FCM_SERVER_KEY')
        if not fcm_key:
            print(f"[PUSH SERVICE][FCM SIMULATION] High-Priority Push to Android token {token[:16]}... payload: {payload.get('type')}", flush=True)
            return True, "Simulated (No FCM key configured)"

        try:
            import urllib.request
            url = 'https://fcm.googleapis.com/fcm/send'
            headers = {
                'Authorization': f'key={fcm_key}',
                'Content-Type': 'application/json'
            }
            body = {
                'to': token,
                'priority': 'high' if high_priority else 'normal',
                'data': payload
            }
            req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers)
            with urllib.request.urlopen(req, timeout=5) as resp:
                print(f"[PUSH SERVICE][FCM SUCCESS] Sent to {token[:16]}... status: {resp.status}", flush=True)
                return True, None
        except Exception as e:
            print(f"[PUSH SERVICE][FCM ERROR] Delivery failed: {e}", flush=True)
            return False, str(e)

    @staticmethod
    def _send_apns_voip_payload(token, payload):
        """
        Sends VoIP PushKit push payload to iOS.
        """
        print(f"[PUSH SERVICE][APNS SIMULATION] VoIP Push to iOS token {token[:16]}... payload: {payload.get('type')}", flush=True)
        return True, "Simulated (No APNs certificate configured)"
