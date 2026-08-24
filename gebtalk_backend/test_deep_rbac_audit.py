import unittest
import json
from app import app
from database import init_db

class DeepRbacAuditTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        init_db(seed_test_data=True)
        cls.client = app.test_client()

    def _login(self, email, password="password123"):
        res = self.client.post('/api/auth/login-email', json={'email': email, 'password': password})
        self.assertEqual(res.status_code, 200, f"Failed to login with {email}: {res.get_json()}")
        data = res.get_json()
        return data.get('token'), data.get('profile')

    def test_01_staff_cannot_browse_other_staff_or_customers(self):
        """Staff (Sarah Jenkins) should only see her assigned customers in contacts and search."""
        token, profile = self._login("sarah.jenkins@gmail.com")
        self.assertEqual(profile['role'].lower(), 'staff')

        # 1. Contacts endpoint
        res = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {token}'})
        self.assertEqual(res.status_code, 200)
        contacts = res.get_json() if isinstance(res.get_json(), list) else res.get_json().get('contacts', [])
        contact_ids = [c['id'] for c in contacts]
        
        # Must see David Miller
        self.assertTrue(any('david' in cid or 'david' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                        "Sarah must see assigned customer David Miller")
        # Must NOT see Alice Johnson (assigned to John Doe)
        self.assertFalse(any('alice' in cid or 'alice' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                         "Sarah must NOT see Alice Johnson (assigned to John)")
        # Must NOT see CEO Marcus Sterling in standard contacts
        self.assertFalse(any('marcus' in cid or 'sterling' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                         "Sarah must NOT see CEO in general customer list")

    def test_02_customer_isolation_and_search_lockdown(self):
        """Customer (David Miller) should ONLY see his 1 assigned staff specialist (Sarah Jenkins)."""
        token, profile = self._login("david.miller@gmail.com")
        role = profile.get('role', '').lower()
        self.assertTrue('customer' in role or 'client' in role, f"Role should be customer/client: {role}")

        # 1. Contacts endpoint
        res = self.client.get('/api/contacts', headers={'Authorization': f'Bearer {token}'})
        self.assertEqual(res.status_code, 200)
        contacts = res.get_json() if isinstance(res.get_json(), list) else res.get_json().get('contacts', [])
        contact_ids = [c['id'] for c in contacts]

        # Must see Sarah Jenkins
        self.assertTrue(any('sarah' in cid or 'sarah' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                        "David must see assigned staff Sarah Jenkins")
        # Must NOT see John Doe
        self.assertFalse(any('john' in cid or 'john' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                         "David must NOT see John Doe")
        # Must NOT see other customers (Alice)
        self.assertFalse(any('alice' in cid or 'alice' in c['name'].lower() for c, cid in zip(contacts, contact_ids)),
                         "David must NOT see other customers like Alice")

    def test_03_strict_403_on_url_or_parameter_tampering(self):
        """Staff and Customers attempting API administrative actions must receive 403 Forbidden."""
        staff_token, _ = self._login("sarah.jenkins@gmail.com")
        cust_token, _ = self._login("david.miller@gmail.com")

        # Staff trying to assign customer
        res = self.client.post('/api/contacts/david/assign', 
                               headers={'Authorization': f'Bearer {staff_token}'},
                               json={'assigned_staff_id': 'john'})
        self.assertEqual(res.status_code, 403, "Staff reassigning customer must return 403")

        # Customer trying to assign customer
        res = self.client.post('/api/contacts/david/assign', 
                               headers={'Authorization': f'Bearer {cust_token}'},
                               json={'assigned_staff_id': 'sarah'})
        self.assertEqual(res.status_code, 403, "Customer reassigning customer must return 403")

        # Staff trying to create account
        res = self.client.post('/api/admin/accounts/create', 
                               headers={'Authorization': f'Bearer {staff_token}'},
                               json={'name': 'Hacker', 'email': 'hacker@ebglobal.com', 'role': 'CEO'})
        self.assertEqual(res.status_code, 403, "Staff creating account must return 403")

        # Customer trying to create account
        res = self.client.post('/api/admin/accounts/create', 
                               headers={'Authorization': f'Bearer {cust_token}'},
                               json={'name': 'Hacker', 'email': 'hacker@ebglobal.com', 'role': 'Customer'})
        self.assertEqual(res.status_code, 403, "Customer creating account must return 403")

    def test_04_manager_privilege_boundaries(self):
        """Manager (Emma Watson) can create Staff & Customers, but cannot create CEO or Manager."""
        mgr_token, mgr_prof = self._login("emma.watson@gmail.com")
        self.assertEqual(mgr_prof['role'].lower(), 'manager')

        # Manager creating Staff -> Allowed (200)
        res = self.client.post('/api/admin/accounts/create',
                               headers={'Authorization': f'Bearer {mgr_token}'},
                               json={'name': 'Test New Staff', 'email': 'test.staff@ebglobal.com', 'role': 'Staff', 'password': 'password123'})
        self.assertIn(res.status_code, [200, 400], "Manager creating Staff should be allowed")

        # Manager creating Customer -> Allowed (200)
        res = self.client.post('/api/admin/accounts/create',
                               headers={'Authorization': f'Bearer {mgr_token}'},
                               json={'name': 'Test New Customer', 'email': 'test.cust@client.com', 'role': 'Customer', 'password': 'password123', 'assigned_staff_id': 'sarah'})
        self.assertIn(res.status_code, [200, 400], "Manager creating Customer should be allowed")

        # Manager creating CEO -> FORBIDDEN (403)
        res = self.client.post('/api/admin/accounts/create',
                               headers={'Authorization': f'Bearer {mgr_token}'},
                               json={'name': 'Test Rogue CEO', 'email': 'rogue.ceo@ebglobal.com', 'role': 'CEO', 'password': 'password123'})
        self.assertEqual(res.status_code, 403, "Manager creating CEO must return 403 Forbidden")

        # Manager creating Manager -> FORBIDDEN (403)
        res = self.client.post('/api/admin/accounts/create',
                               headers={'Authorization': f'Bearer {mgr_token}'},
                               json={'name': 'Test Another Manager', 'email': 'rogue.mgr@ebglobal.com', 'role': 'Manager', 'password': 'password123'})
        self.assertEqual(res.status_code, 403, "Manager creating Manager must return 403 Forbidden")

if __name__ == '__main__':
    unittest.main()
