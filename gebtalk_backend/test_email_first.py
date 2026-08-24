import unittest
import json
from app import app
import database

class TestEmailFirstSystem(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        database.init_db(seed_test_data=True)
        cls.client = app.test_client()

    def test_search_users_by_email(self):
        resp = self.client.get('/api/users/search?q=sarah')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertIn('users', data)
        self.assertTrue(len(data['users']) > 0)
        self.assertTrue(any('sarah' in u['email'].lower() for u in data['users']))

    def test_contact_request_lifecycle(self):
        # 1. Send Request
        resp = self.client.post('/api/contacts/request', json={
            'target_email': 'sarah.jenkins@gmail.com',
            'message': 'Hi Sarah, let us connect!'
        })
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data.get('success'))

        # 2. Get Requests
        resp = self.client.get('/api/contacts/requests')
        self.assertEqual(resp.status_code, 200)
        req_data = json.loads(resp.data)
        self.assertIn('incoming', req_data)
        self.assertTrue(len(req_data['incoming']) > 0)

        # 3. Respond (Accept)
        first_req_id = req_data['incoming'][0]['id']
        resp = self.client.post('/api/contacts/respond', json={
            'request_id': first_req_id,
            'action': 'accept'
        })
        self.assertEqual(resp.status_code, 200)
        resp_data = json.loads(resp.data)
        self.assertEqual(resp_data.get('status'), 'accepted')

    def test_emails_inbox_and_detail(self):
        # 1. Get Inbox
        resp = self.client.get('/api/emails?folder=inbox')
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertIn('emails', data)
        self.assertIn('counts', data)
        self.assertTrue(len(data['emails']) > 0)

        # 2. Get Email Detail
        first_email_id = data['emails'][0]['id']
        resp = self.client.get(f'/api/emails/{first_email_id}')
        self.assertEqual(resp.status_code, 200)
        detail = json.loads(resp.data)
        self.assertEqual(detail['id'], first_email_id)

    def test_email_send(self):
        resp = self.client.post('/api/emails/send', json={
            'to_email': 'test.partner@example.com',
            'subject': 'Test Architecture Sync',
            'body_text': 'Testing the GEBTALK Email-first engine.'
        })
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data.get('success'))

    def test_email_to_chat_conversion(self):
        resp = self.client.post('/api/emails/convert-to-chat', json={
            'email_id': 'em_1'
        })
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data.get('success'))
        self.assertIn('contact', data)
        self.assertIn('message', data)

    def test_chat_forward_to_email(self):
        resp = self.client.post('/api/chat/forward-to-email', json={
            'to_email': 'sarah.jenkins@gmail.com',
            'contact_id': 'sarah',
            'subject': 'Sprint Decisions Summary'
        })
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertTrue(data.get('success'))

if __name__ == '__main__':
    unittest.main()
