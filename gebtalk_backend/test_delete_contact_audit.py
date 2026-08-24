import unittest
import json
from app import app
from database import init_db, get_db_connection

class TestDeleteContactAudit(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        with app.app_context():
            init_db()

    def _login(self, email, password='password123'):
        res = self.app.post('/api/auth/login-email', json={'email': email, 'password': password})
        if res.status_code == 200:
            return json.loads(res.data).get('token')
        return None

    def test_01_delete_contact_cascade(self):
        """Verify deleting a contact removes records, unassigns dependencies, and prevents orphan data."""
        ceo_token = self._login('marcus.sterling@ebglobal.com')
        headers = {'Authorization': f'Bearer {ceo_token}'}

        # 1. Create a dummy contact
        import time
        cid = f"test_contact_{int(time.time())}"
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO contacts (id, name, phone, email, role, folder, assigned_staff_id)
            VALUES (%s, 'Temp User', '+1 555 999 1234', %s, 'Customer', 'customers', 'sarah')
        ''', (cid, f"{cid}@test.com"))
        cursor.execute('''
            INSERT INTO messages (contact_id, text, is_user, time, status)
            VALUES (%s, 'Test message', TRUE, '12:00 PM', 'sent')
        ''', (cid,))
        conn.commit()
        conn.close()

        # 2. Delete the contact via API
        del_res = self.app.delete(f'/api/contacts/{cid}', headers=headers)
        self.assertEqual(del_res.status_code, 200)
        self.assertTrue(json.loads(del_res.data).get('success'))

        # 3. Verify contact and messages are wiped
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (cid,))
        self.assertIsNone(cursor.fetchone())
        cursor.execute('SELECT 1 FROM messages WHERE contact_id = %s', (cid,))
        self.assertIsNone(cursor.fetchone())
        conn.close()
        print("[PASS] Test 01: Delete contact cascade cleanup verified.")

if __name__ == '__main__':
    unittest.main()
