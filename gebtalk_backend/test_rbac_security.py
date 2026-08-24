import sys
import unittest
import json
from app import app
from database import init_db

class TestRBACSecurity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        init_db(seed_test_data=True)
        cls.client = app.test_client()

    def test_01_ceo_login_and_full_visibility(self):
        # 1. CEO Login
        res = self.client.post('/api/auth/login-email', json={
            'email': 'marcus.sterling@ebglobal.com',
            'password': 'password123'
        })
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertEqual(data['user']['role'], 'CEO')
        token = data['token']

        # 2. Get contacts with CEO token
        res = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {token}'})
        self.assertEqual(res.status_code, 200)
        contacts = res.get_json()
        
        contact_ids = [c['id'] for c in contacts]
        # CEO should see all staff and customers
        self.assertIn('sarah', contact_ids)
        self.assertIn('john', contact_ids)
        self.assertIn('david', contact_ids)
        self.assertIn('customer_a', contact_ids)
        print("[PASS] Test 1: CEO has full visibility across all contacts.")

    def test_02_manager_privileges_and_boundaries(self):
        # 1. Manager Login
        res = self.client.post('/api/auth/login-email', json={
            'email': 'emma.watson@gmail.com',
            'password': 'password123'
        })
        self.assertEqual(res.status_code, 200)
        manager_token = res.get_json()['token']

        # 2. Manager creates a Staff account -> Allowed
        import time
        dynamic_email = f"lucas_{int(time.time()*1000)}@gebtalk.com"
        res = self.client.post('/api/admin/accounts/create', 
            headers={'Authorization': f'Bearer {manager_token}'},
            json={
                'name': 'Lucas Vance',
                'email': dynamic_email,
                'role': 'Staff',
                'password': 'password123'
            }
        )
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.get_json()['success'])

        # 3. Manager tries to create a CEO account -> Forbidden (403)
        res = self.client.post('/api/admin/accounts/create', 
            headers={'Authorization': f'Bearer {manager_token}'},
            json={
                'name': 'Hacker Boss',
                'email': 'hacker@gebtalk.com',
                'role': 'CEO',
                'password': 'password123'
            }
        )
        self.assertEqual(res.status_code, 403)
        print("[PASS] Test 2: Manager can create Staff, but is blocked (403) from creating CEO.")

    def test_03_staff_isolation_and_restriction(self):
        # 1. Staff Sarah Login
        res = self.client.post('/api/auth/login-email', json={
            'email': 'sarah.jenkins@gmail.com',
            'password': 'password123'
        })
        self.assertEqual(res.status_code, 200)
        staff_token = res.get_json()['token']

        # 2. Staff views contacts -> Should ONLY see self, support, and assigned customers (david, customer_d, customer_e)
        res = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {staff_token}'})
        self.assertEqual(res.status_code, 200)
        contacts = res.get_json()
        contact_ids = [c['id'] for c in contacts]

        self.assertIn('sarah', contact_ids)
        self.assertIn('david', contact_ids) # Assigned to Sarah
        self.assertNotIn('john', contact_ids) # Other staff -> Hidden
        self.assertNotIn('customer_a', contact_ids) # Assigned to John -> Hidden
        self.assertNotIn('customer_b', contact_ids) # Assigned to John -> Hidden

        # 3. Staff attempts to create an account -> Forbidden (403)
        res = self.client.post('/api/admin/accounts/create',
            headers={'Authorization': f'Bearer {staff_token}'},
            json={'name': 'Fake Client', 'email': 'fake@client.com', 'role': 'Customer'}
        )
        self.assertEqual(res.status_code, 403)

        # 4. Staff attempts to reassign a customer -> Forbidden (403)
        res = self.client.post('/api/contacts/customer_a/assign',
            headers={'Authorization': f'Bearer {staff_token}'},
            json={'assigned_staff_id': 'sarah'}
        )
        self.assertEqual(res.status_code, 403)
        print("[PASS] Test 3: Staff visibility is strictly isolated and admin actions return 403.")

    def test_04_customer_isolation_and_restriction(self):
        # 1. Customer David Login
        res = self.client.post('/api/auth/login-email', json={
            'email': 'david.miller@gmail.com',
            'password': 'password123'
        })
        self.assertEqual(res.status_code, 200)
        customer_token = res.get_json()['token']

        # 2. Customer views contacts -> Should ONLY see self, support, and assigned specialist (Sarah)
        res = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {customer_token}'})
        self.assertEqual(res.status_code, 200)
        contacts = res.get_json()
        contact_ids = [c['id'] for c in contacts]

        self.assertIn('sarah', contact_ids) # Designated specialist
        self.assertNotIn('john', contact_ids) # Other staff -> Hidden
        self.assertNotIn('customer_a', contact_ids) # Other customer -> Hidden
        self.assertNotIn('customer_b', contact_ids) # Other customer -> Hidden

        # 3. Customer attempts to create an account -> Forbidden (403)
        res = self.client.post('/api/admin/accounts/create',
            headers={'Authorization': f'Bearer {customer_token}'},
            json={'name': 'Unauthorized', 'email': 'unauth@test.com', 'role': 'Staff'}
        )
        self.assertEqual(res.status_code, 403)
        print("[PASS] Test 4: Customer visibility is strictly isolated to assigned specialist only.")

    def test_05_customer_reassignment_flow(self):
        # 1. CEO logs in
        res = self.client.post('/api/auth/login-email', json={
            'email': 'marcus.sterling@ebglobal.com',
            'password': 'password123'
        })
        ceo_token = res.get_json()['token']

        # 2. Reassign Customer David from Sarah to John
        res = self.client.post('/api/contacts/david/assign',
            headers={'Authorization': f'Bearer {ceo_token}'},
            json={'assigned_staff_id': 'john'}
        )
        self.assertEqual(res.status_code, 200)

        # 3. Verify Sarah no longer sees David
        res_sarah = self.client.post('/api/auth/login-email', json={'email': 'sarah.jenkins@gmail.com', 'password': 'password123'})
        sarah_contacts = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {res_sarah.get_json()["token"]}'}).get_json()
        sarah_cids = [c['id'] for c in sarah_contacts]
        self.assertNotIn('david', sarah_cids)

        # 4. Verify John now sees David
        res_john = self.client.post('/api/auth/login-email', json={'email': 'john.doe@gmail.com', 'password': 'password123'})
        john_contacts = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {res_john.get_json()["token"]}'}).get_json()
        john_cids = [c['id'] for c in john_contacts]
        self.assertIn('david', john_cids)

        # 5. Verify Customer David now sees John as their assigned specialist
        res_david = self.client.post('/api/auth/login-email', json={'email': 'david.miller@gmail.com', 'password': 'password123'})
        david_contacts = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {res_david.get_json()["token"]}'}).get_json()
        david_cids = [c['id'] for c in david_contacts]
        self.assertIn('john', david_cids)

        # Reassign back to Sarah for clean state
        self.client.post('/api/contacts/david/assign',
            headers={'Authorization': f'Bearer {ceo_token}'},
            json={'assigned_staff_id': 'sarah'}
        )
        print("[PASS] Test 5: Customer reassignment updates visibility across all roles in real-time.")

if __name__ == '__main__':
    unittest.main()
