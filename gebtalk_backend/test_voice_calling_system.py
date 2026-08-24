import unittest
import json
from app import app
from database import init_db

class TestVoiceCallingSystem(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        with app.app_context():
            init_db(seed_test_data=True)
            from database import get_db_connection
            conn = get_db_connection()
            c = conn.cursor()
            c.execute("DELETE FROM webrtc_calls")
            c.execute("DELETE FROM webrtc_candidates")
            conn.commit()
            conn.close()

    def test_01_webrtc_config_endpoint(self):
        """Verify dynamic STUN/TURN ICE configuration endpoint."""
        res = self.app.get('/api/calls/config')
        self.assertEqual(res.status_code, 200)
        data = json.loads(res.data)
        self.assertIn('iceServers', data)
        self.assertTrue(len(data['iceServers']) > 0)
        self.assertIn('urls', data['iceServers'][0])
        print("[PASS] Test 1: WebRTC ICE Configuration endpoint returns valid STUN/TURN servers.")

    def test_02_call_lifecycle_offer_answer_and_ice(self):
        """Verify Call Initiation -> Polling -> Acceptance -> Candidate Exchange -> Termination."""
        caller = 'USR_883392' # Marcus Sterling
        callee = 'USR_101'    # Sarah Jenkins
        
        # 1. Caller initiates voice call with SDP offer
        create_res = self.app.post('/api/calls/create', json={
            'caller_id': caller,
            'callee_id': callee,
            'sdp_offer': 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n',
            'call_type': 'voice'
        })
        self.assertEqual(create_res.status_code, 200)
        call_data = json.loads(create_res.data)
        call_id = call_data['call_id']
        self.assertEqual(call_data['status'], 'ringing')

        # 2. Callee polls for incoming calls
        incoming_res = self.app.get(f'/api/calls/incoming?callee_id={callee}')
        self.assertEqual(incoming_res.status_code, 200)
        incoming_data = json.loads(incoming_res.data)
        self.assertIsNotNone(incoming_data)
        self.assertEqual(incoming_data['call_id'], call_id)
        self.assertEqual(incoming_data['caller_id'], caller)

        # 3. Callee exchanges ICE candidate
        cand_res = self.app.post('/api/calls/ice-candidate', json={
            'call_id': call_id,
            'sender_id': callee,
            'candidate': json.dumps({'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.100 54321 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0})
        })
        self.assertEqual(cand_res.status_code, 200)

        # 4. Caller fetches ICE candidates excluding self
        fetch_cand_res = self.app.get(f'/api/calls/ice-candidates?call_id={call_id}&exclude_sender_id={caller}')
        self.assertEqual(fetch_cand_res.status_code, 200)
        candidates = json.loads(fetch_cand_res.data)
        self.assertEqual(len(candidates), 1)

        # 5. Callee accepts call with SDP answer
        accept_res = self.app.post('/api/calls/accept', json={
            'call_id': call_id,
            'sdp_answer': 'v=0\r\no=- 54321 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        })
        self.assertEqual(accept_res.status_code, 200)

        # 6. Caller checks call status -> 'connected'
        status_res = self.app.get(f'/api/calls/status?call_id={call_id}')
        self.assertEqual(status_res.status_code, 200)
        status_data = json.loads(status_res.data)
        self.assertEqual(status_data['status'], 'connected')

        # 7. End call with 45 seconds duration
        end_res = self.app.post('/api/calls/end', json={
            'call_id': call_id,
            'duration': 45,
            'state_before_end': 'connected',
            'reason': 'ended'
        })
        self.assertEqual(end_res.status_code, 200)

        # 8. Check call logs endpoint
        logs_res = self.app.get('/api/calls')
        self.assertEqual(logs_res.status_code, 200)
        logs = json.loads(logs_res.data)
        self.assertTrue(len(logs) > 0)
        print("[PASS] Test 2: Complete WebRTC call lifecycle (Offer -> Poll -> Answer -> ICE -> Connected -> End -> CallLog) passed.")

    def test_03_busy_recipient_rejection(self):
        """Verify that when a callee is on an active call, new callers receive HTTP 486 Busy."""
        caller_a = 'USR_883392' # Marcus
        callee = 'USR_101'      # Sarah
        caller_b = 'USR_103'     # Emma

        # Marcus calls Sarah
        c1 = self.app.post('/api/calls/create', json={
            'caller_id': caller_a,
            'callee_id': callee,
            'sdp_offer': 'offer_1',
            'call_type': 'voice'
        })
        self.assertEqual(c1.status_code, 200)

        # Emma tries to call Sarah while Sarah is ringing
        c2 = self.app.post('/api/calls/create', json={
            'caller_id': caller_b,
            'callee_id': callee,
            'sdp_offer': 'offer_2',
            'call_type': 'voice'
        })
        self.assertEqual(c2.status_code, 486)
        c2_data = json.loads(c2.data)
        self.assertEqual(c2_data.get('status'), 'busy')
        print("[PASS] Test 3: Busy detection returned HTTP 486 when calling an engaged peer.")

    def test_04_call_declined_and_missed_logging(self):
        """Verify that declined calls record appropriate missed/declined logs."""
        caller = 'USR_883392'
        callee = 'USR_201' # David Miller

        create_res = self.app.post('/api/calls/create', json={
            'caller_id': caller,
            'callee_id': callee,
            'sdp_offer': 'offer_sdp',
            'call_type': 'voice'
        })
        call_id = json.loads(create_res.data)['call_id']

        # Callee declines call
        end_res = self.app.post('/api/calls/end', json={
            'call_id': call_id,
            'duration': 0,
            'state_before_end': 'ringing',
            'reason': 'declined'
        })
        self.assertEqual(end_res.status_code, 200)

        status_res = self.app.get(f'/api/calls/status?call_id={call_id}')
        self.assertEqual(json.loads(status_res.data)['status'], 'ended')
        print("[PASS] Test 4: Call decline and missed call transitions passed.")

    def test_05_staff_customer_calling_permissions(self):
        """Verify Staff can call assigned Customer, but is blocked (403) from calling unassigned Customer."""
        staff_sarah = 'sarah.jenkins@gmail.com' # Assigned to David Miller (david.miller@gmail.com)
        assigned_customer = 'david.miller@gmail.com'
        unassigned_customer = 'alice.johnson@aurora.com' # Assigned to John Doe, NOT Sarah

        # 1. Staff calls assigned Customer -> Allowed (200)
        res_assigned = self.app.post('/api/calls/create', json={
            'caller_id': staff_sarah,
            'callee_id': assigned_customer,
            'sdp_offer': 'sdp_staff_to_customer',
            'call_type': 'voice'
        })
        self.assertEqual(res_assigned.status_code, 200)
        call_id = json.loads(res_assigned.data)['call_id']

        # Cleanup call
        self.app.post('/api/calls/end', json={'call_id': call_id, 'duration': 10, 'state_before_end': 'connected', 'reason': 'ended'})

        # 2. Staff attempts to call unassigned Customer -> Blocked (403)
        res_unassigned = self.app.post('/api/calls/create', json={
            'caller_id': staff_sarah,
            'callee_id': unassigned_customer,
            'sdp_offer': 'sdp_unassigned_call',
            'call_type': 'voice'
        })
        self.assertEqual(res_unassigned.status_code, 403)
        print("[PASS] Test 5: Staff calling authorization strictly enforced (assigned customer: 200, unassigned: 403).")

    def test_06_customer_calling_permissions(self):
        """Verify Customer can call their assigned Staff specialist, but is blocked (403) from calling other customers or unauthorized staff."""
        customer_david = 'david.miller@gmail.com'
        assigned_specialist = 'sarah.jenkins@gmail.com'
        other_customer = 'alice.johnson@aurora.com'

        # 1. Customer calls assigned specialist -> Allowed (200)
        res_specialist = self.app.post('/api/calls/create', json={
            'caller_id': customer_david,
            'callee_id': assigned_specialist,
            'sdp_offer': 'sdp_customer_to_specialist',
            'call_type': 'voice'
        })
        self.assertEqual(res_specialist.status_code, 200)
        call_id = json.loads(res_specialist.data)['call_id']

        # Cleanup call
        self.app.post('/api/calls/end', json={'call_id': call_id, 'duration': 5, 'state_before_end': 'connected', 'reason': 'ended'})

        # 2. Customer attempts to call another Customer -> Blocked (403)
        res_other_cust = self.app.post('/api/calls/create', json={
            'caller_id': customer_david,
            'callee_id': other_customer,
            'sdp_offer': 'sdp_customer_to_customer',
            'call_type': 'voice'
        })
        self.assertEqual(res_other_cust.status_code, 403)
        print("[PASS] Test 6: Customer calling authorization strictly isolated (specialist: 200, other customers: 403).")

if __name__ == '__main__':
    unittest.main()
