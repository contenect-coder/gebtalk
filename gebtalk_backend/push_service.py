"""
Push Notification & Background Call Wake-Up Service for GEBTALK VoIP.
Handles device registration, high-priority background push delivery, and multi-device call cancellation.
"""

import json
import os
import threading
import time
from datetime import datetime

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
                
                print(f"[PUSH SERVICE][DIAG]   -> Dispatching to [{platform}] device '{dev_id}' (token: {push_token[:15] if push_token else 'N/A'}...)", flush=True)
                
                if platform == 'ANDROID' and push_token:
                    PushService._send_fcm_call_payload(push_token, call_payload, high_priority=True)
                elif platform == 'IOS' and (voip_token or push_token):
                    PushService._send_apns_voip_payload(voip_token or push_token, call_payload)
                elif platform in ('WEB', 'DESKTOP'):
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
                elif platform in ('WEB', 'DESKTOP'):
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
                elif platform in ('WEB', 'DESKTOP'):
                    PushService._send_web_push_payload(push_token, fork_payload)

        threading.Thread(target=_dispatch, daemon=True).start()

    # --- Low-level dispatch handlers ---

    @staticmethod
    def _send_fcm_call_payload(token, payload, high_priority=True):
        """
        Sends high-priority data-only FCM push message to Android.
        Data-only messages wake Android Background Services directly without showing default chat popups.
        """
        # Checks for FCM Server Key or Google Application Credentials
        fcm_key = os.environ.get('FCM_SERVER_KEY')
        if not fcm_key:
            # Simulated environment logging
            print(f"[PUSH SERVICE][FCM SIMULATION] High-Priority Push to Android token {token[:16]}... payload: {payload.get('type')}", flush=True)
            return

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
        except Exception as e:
            print(f"[PUSH SERVICE][FCM ERROR] Delivery failed: {e}", flush=True)

    @staticmethod
    def _send_apns_voip_payload(token, payload):
        """
        Sends VoIP PushKit push payload to iOS.
        """
        print(f"[PUSH SERVICE][APNS SIMULATION] VoIP Push to iOS token {token[:16]}... payload: {payload.get('type')}", flush=True)

    @staticmethod
    def _send_web_push_payload(token, payload):
        """
        Sends Web Push message for Desktop / Web browser background tabs.
        """
        print(f"[PUSH SERVICE][WEB PUSH SIMULATION] Web Push to device token {token[:16] if token else 'local_web'}... payload: {payload.get('type')}", flush=True)
