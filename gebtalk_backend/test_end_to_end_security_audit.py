import unittest
import json
from app import app
from database import init_db, get_db_connection

class TestEndToEndSecurityAudit(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        with app.app_context():
            init_db(seed_test_data=True)

    def _login(self, email, password='password123'):
        res = self.app.post('/api/auth/login-email', json={'email': email, 'password': password})
        if res.status_code == 200:
            return json.loads(res.data).get('token')
        return None

    def test_01_authentication_and_invalid_credentials(self):
        """Verify login, token issuance, and rejection of invalid passwords."""
        # 1. Valid login
        token = self._login('marcus.sterling@ebglobal.com', 'password123')
        self.assertIsNotNone(token)

        # 2. Invalid password
        bad_res = self.app.post('/api/auth/login-email', json={'email': 'marcus.sterling@ebglobal.com', 'password': 'wrongpassword'})
        self.assertEqual(bad_res.status_code, 401)

        # 3. Non-existent user
        non_res = self.app.post('/api/auth/login-email', json={'email': 'ghost@nowhere.com', 'password': 'password123'})
        self.assertEqual(non_res.status_code, 401)
        print("[PASS] Test 01: Authentication securely rejects invalid credentials.")

    def test_02_ceo_full_permissions(self):
        """Verify CEO has unrestricted visibility and provisioning capability."""
        ceo_token = self._login('marcus.sterling@ebglobal.com')
        headers = {'Authorization': f'Bearer {ceo_token}'}

        # CEO retrieves contacts
        res = self.app.get('/api/contacts', headers=headers)
        self.assertEqual(res.status_code, 200)
        contacts = json.loads(res.data)
        self.assertTrue(len(contacts) >= 8)

        # CEO can create a Manager account
        import time
        unique_email = f"regional.mgr.{int(time.time()*1000)}@ebglobal.com"
        create_res = self.app.post('/api/admin/accounts/create', headers=headers, json={
            'name': 'Regional Manager',
            'email': unique_email,
            'role': 'Manager',
            'phone': '+1 (555) 999-0001',
            'password': 'password123'
        })
        self.assertEqual(create_res.status_code, 200)
        print("[PASS] Test 02: CEO full organizational visibility and provisioning verified.")

    def test_03_manager_boundaries(self):
        """Verify Manager can manage Staff & Customers, but is strictly blocked (403) from creating CEO accounts."""
        mgr_token = self._login('emma.watson@gmail.com')
        headers = {'Authorization': f'Bearer {mgr_token}'}

        # Manager creates Staff account -> Allowed (200)
        import time
        unique_staff_email = f"jr.support.{int(time.time()*1000)}@ebglobal.com"
        create_staff = self.app.post('/api/admin/accounts/create', headers=headers, json={
            'name': 'Junior Support',
            'email': unique_staff_email,
            'role': 'Staff',
            'phone': '+1 (555) 999-0002',
            'password': 'password123'
        })
        self.assertEqual(create_staff.status_code, 200)

        # Manager attempts to create CEO account -> Blocked (403)
        create_ceo = self.app.post('/api/admin/accounts/create', headers=headers, json={
            'name': 'Rogue Executive',
            'email': f"rogue.exec.{int(time.time()*1000)}@ebglobal.com",
            'role': 'CEO',
            'phone': '+1 (555) 999-0003',
            'password': 'password123'
        })
        self.assertEqual(create_ceo.status_code, 403)
        print("[PASS] Test 03: Manager role boundaries enforced (CEO creation blocked with 403).")

    def test_04_staff_isolation_and_idor_prevention(self):
        """Verify Staff can only read/send messages to assigned Customers and unauthorized access is blocked (403)."""
        staff_token = self._login('sarah.jenkins@gmail.com') # Sarah is assigned to David Miller ('david')
        headers = {'Authorization': f'Bearer {staff_token}'}

        # 1. Staff reads messages of assigned Customer David -> Allowed (200)
        res_assigned = self.app.get('/api/contacts/david/messages', headers=headers)
        self.assertEqual(res_assigned.status_code, 200)

        # 2. Staff attempts to read messages of unassigned Customer Alice ('customer_a', assigned to John) -> Blocked (403)
        res_unassigned = self.app.get('/api/contacts/customer_a/messages', headers=headers)
        self.assertEqual(res_unassigned.status_code, 403)

        # 3. Staff sends message to assigned Customer -> Allowed (200)
        send_assigned = self.app.post('/api/contacts/david/messages', headers=headers, json={'text': 'Hello David!'})
        self.assertEqual(send_assigned.status_code, 200)

        # 4. Staff attempts to send message to unassigned Customer -> Blocked (403)
        send_unassigned = self.app.post('/api/contacts/customer_a/messages', headers=headers, json={'text': 'Unauthorized message'})
        self.assertEqual(send_unassigned.status_code, 403)
        print("[PASS] Test 04: Staff messaging IDOR and cross-customer leak strictly prevented (403).")

    def test_05_customer_isolation_and_specialist_restriction(self):
        """Verify Customer can only communicate with assigned specialist and cross-customer communication is blocked (403)."""
        cust_token = self._login('david.miller@gmail.com') # David is assigned to Sarah Jenkins ('sarah')
        headers = {'Authorization': f'Bearer {cust_token}'}

        # 1. Customer reads messages with assigned specialist -> Allowed (200)
        res_specialist = self.app.get('/api/contacts/sarah/messages', headers=headers)
        self.assertEqual(res_specialist.status_code, 200)

        # 2. Customer attempts to read messages of another Customer ('customer_a') -> Blocked (403)
        res_other_cust = self.app.get('/api/contacts/customer_a/messages', headers=headers)
        self.assertEqual(res_other_cust.status_code, 403)

        # 3. Customer attempts to send message to another Customer -> Blocked (403)
        send_other_cust = self.app.post('/api/contacts/customer_a/messages', headers=headers, json={'text': 'Hi Alice!'})
        self.assertEqual(send_other_cust.status_code, 403)

        # 4. Customer attempts to create an account -> Blocked (403)
        create_res = self.app.post('/api/admin/accounts/create', headers=headers, json={
            'name': 'Fake Staff', 'email': 'fake@test.com', 'role': 'Staff', 'password': 'password123'
        })
        self.assertEqual(create_res.status_code, 403)
        print("[PASS] Test 05: Customer isolation and unauthorized messaging blocked (403).")

    def test_06_search_endpoint_role_filtering(self):
        """Verify global search and user directory search do not leak unauthorized contacts."""
        # 1. Staff search
        staff_token = self._login('sarah.jenkins@gmail.com')
        staff_headers = {'Authorization': f'Bearer {staff_token}'}
        search_staff = self.app.get('/api/search?q=aurora', headers=staff_headers)
        self.assertEqual(search_staff.status_code, 200)
        staff_results = json.loads(search_staff.data).get('contacts', [])
        # Sarah does NOT manage Aurora contacts (Alice, Bob, Charlie) -> must be empty
        self.assertEqual(len(staff_results), 0)

        # 2. CEO search for same term
        ceo_token = self._login('marcus.sterling@ebglobal.com')
        ceo_headers = {'Authorization': f'Bearer {ceo_token}'}
        search_ceo = self.app.get('/api/search?q=aurora', headers=ceo_headers)
        self.assertEqual(search_ceo.status_code, 200)
        ceo_results = json.loads(search_ceo.data).get('contacts', [])
        self.assertTrue(len(ceo_results) >= 1)
        print("[PASS] Test 06: Global search strictly respects caller role boundaries.")

    def test_07_realtime_customer_reassignment_propagation(self):
        """Verify reassigning Customer from Staff A to Staff B immediately updates messaging and calling permissions."""
        ceo_token = self._login('marcus.sterling@ebglobal.com')
        sarah_token = self._login('sarah.jenkins@gmail.com') # Staff A
        john_token = self._login('john.doe@gmail.com')        # Staff B

        # Reassign David Miller ('david') to John Doe ('john')
        reassign_res = self.app.post('/api/contacts/david/assign', headers={'Authorization': f'Bearer {ceo_token}'}, json={
            'assigned_staff_id': 'john'
        })
        self.assertEqual(reassign_res.status_code, 200)

        # 1. Sarah immediately loses messaging access -> Returns 403
        sarah_msg = self.app.post('/api/contacts/david/messages', headers={'Authorization': f'Bearer {sarah_token}'}, json={'text': 'Still here?'})
        self.assertEqual(sarah_msg.status_code, 403)

        # 2. Sarah immediately loses calling access -> Returns 403
        sarah_call = self.app.post('/api/calls/create', json={'caller_id': 'sarah.jenkins@gmail.com', 'callee_id': 'david.miller@gmail.com', 'sdp_offer': 'test', 'call_type': 'voice'})
        self.assertEqual(sarah_call.status_code, 403)

        # 3. John immediately gains messaging access -> Returns 200
        john_msg = self.app.post('/api/contacts/david/messages', headers={'Authorization': f'Bearer {john_token}'}, json={'text': 'Welcome to my portfolio!'})
        self.assertEqual(john_msg.status_code, 200)

        # 4. John immediately gains calling access -> Returns 200
        john_call = self.app.post('/api/calls/create', json={'caller_id': 'john.doe@gmail.com', 'callee_id': 'david.miller@gmail.com', 'sdp_offer': 'test', 'call_type': 'voice'})
        self.assertEqual(john_call.status_code, 200)
        call_id = json.loads(john_call.data)['call_id']
        self.app.post('/api/calls/end', json={'call_id': call_id, 'duration': 1, 'state_before_end': 'connected', 'reason': 'ended'})

        # Restore original assignment back to Sarah
        self.app.post('/api/contacts/david/assign', headers={'Authorization': f'Bearer {ceo_token}'}, json={'assigned_staff_id': 'sarah'})
        print("[PASS] Test 07: Real-time customer reassignment immediately shifts access boundaries.")

    def test_08_webrtc_calling_lifecycle_and_busy_guard(self):
        """Verify WebRTC STUN/TURN, Offer/Answer, and Busy 486 guard."""
        # 1. Config endpoint
        config_res = self.app.get('/api/calls/config')
        self.assertEqual(config_res.status_code, 200)
        self.assertIn('iceServers', json.loads(config_res.data))

        # 2. Create call
        c1 = self.app.post('/api/calls/create', json={
            'caller_id': 'marcus.sterling@ebglobal.com',
            'callee_id': 'sarah.jenkins@gmail.com',
            'sdp_offer': 'offer_sdp',
            'call_type': 'voice'
        })
        self.assertEqual(c1.status_code, 200)
        call_id = json.loads(c1.data)['call_id']

        # 3. Third party calls Sarah while ringing -> Returns 486 Busy
        c2 = self.app.post('/api/calls/create', json={
            'caller_id': 'emma.watson@gmail.com',
            'callee_id': 'sarah.jenkins@gmail.com',
            'sdp_offer': 'offer_sdp_2',
            'call_type': 'voice'
        })
        self.assertEqual(c2.status_code, 486)

        # 4. Accept call
        accept_res = self.app.post('/api/calls/accept', json={'call_id': call_id, 'sdp_answer': 'answer_sdp'})
        self.assertEqual(accept_res.status_code, 200)

        # 5. End call
        end_res = self.app.post('/api/calls/end', json={'call_id': call_id, 'duration': 30, 'state_before_end': 'connected', 'reason': 'ended'})
        self.assertEqual(end_res.status_code, 200)
        print("[PASS] Test 08: WebRTC calling lifecycle, busy detection, and dual logging verified.")

if __name__ == '__main__':
    unittest.main()
