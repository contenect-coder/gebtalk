import urllib.request
import urllib.parse
import urllib.error
import json
import traceback

BASE_URL = 'http://127.0.0.1:5000/api'
PHONE = '+94771234567'
HEADERS = {
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {PHONE}',
    'x-user-phone': PHONE
}

def api_call(method, path, body=None, custom_headers=None):
    url = f"{BASE_URL}{path}"
    headers = custom_headers if custom_headers is not None else HEADERS
    data = json.dumps(body).encode('utf-8') if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            status = resp.status
            content = resp.read().decode('utf-8')
            try:
                parsed = json.loads(content)
            except Exception:
                parsed = content
            return status, parsed, None
    except urllib.error.HTTPError as e:
        err_content = e.read().decode('utf-8')
        try:
            parsed = json.loads(err_content)
        except Exception:
            parsed = err_content
        return e.code, parsed, err_content
    except Exception as e:
        return 0, None, str(e)

results = []

def run_test(name, method, path, body=None, expected_statuses=[200]):
    status, data, err = api_call(method, path, body)
    passed = status in expected_statuses
    results.append({
        'name': name,
        'method': method,
        'path': path,
        'status': status,
        'passed': passed,
        'error': err if not passed else None,
        'data_sample': str(data)[:150] if data else None
    })
    status_str = 'PASS' if passed else f'FAIL ({status})'
    print(f"[{status_str}] {method} {path}")
    if not passed:
        print(f"   Error: {err or data}")

print("=== Starting End-to-End Backend Verification ===")

# 1. Auth Flow
run_test("Send OTP", "POST", "/auth/send-otp", {"phone": PHONE, "name": "Victor Tester"})
run_test("Verify OTP (Debug 1234)", "POST", "/auth/verify-otp", {"phone": PHONE, "otp": "1234", "name": "Victor Tester"})
run_test("Login Email", "POST", "/auth/login-email", {"email": "victor@gebtalk.com", "password": "password123", "name": "Victor Corporate"})

# 2. Init & System Info
run_test("Init Batch Data", "GET", "/init")
run_test("Folders", "GET", "/folders")
run_test("Get Tags", "GET", "/tags")
run_test("Create Tag", "POST", "/tags", {"id": "vip_test", "name": "VIP Test", "color": "#00FFCC"})

# 3. Profile & Settings
run_test("Get Profile", "GET", "/profile")
run_test("Update Profile", "POST", "/profile", {"name": "Victor Updated", "about": "Building with GebTalk", "role": "CEO"})
run_test("Privacy Settings", "POST", "/profile/privacy", {"lastSeen": "everyone", "profilePhoto": "contacts", "readReceipts": True})
run_test("App Lock Settings", "POST", "/profile/app-lock", {"enabled": True, "pin": "1234"})
status, email_otp_res, _ = api_call("POST", "/profile/email/send-otp", {"email": "test@gebtalk.com"})
print(f"[Send Profile Email OTP] {email_otp_res}")
run_test("Send Profile Email OTP", "POST", "/profile/email/send-otp", {"email": "test@gebtalk.com"})

# 4. Contacts & Chats
run_test("Get Contacts", "GET", "/contacts")
run_test("Create Contact", "POST", "/contacts", {"id": "alice_partner", "name": "Alice Partner", "phone": "+94770000001", "folder": "customers"})
run_test("Create Staff", "POST", "/contacts/staff", {"name": "Staff Bob", "phone": "+94770000002", "role": "Support Lead"})
run_test("Search Global", "GET", "/search?q=Alice")

# 5. Messaging & Actions
status, contacts_data, _ = api_call("GET", "/contacts")
contact_id = "sarah"
if isinstance(contacts_data, list) and len(contacts_data) > 0:
    contact_id = contacts_data[0].get('id', 'sarah')

run_test("Get Contact Messages", "GET", f"/contacts/{contact_id}/messages")
run_test("Send Message", "POST", f"/contacts/{contact_id}/messages", {
    "text": "Hello from automated test!",
    "type": "text",
    "status": "sent"
})

status, msg_resp, _ = api_call("GET", f"/contacts/{contact_id}/messages")
msg_id = None
if isinstance(msg_resp, list) and len(msg_resp) > 0:
    msg_id = msg_resp[-1].get('id')

if msg_id:
    run_test("React Message", "POST", f"/contacts/{contact_id}/messages/{msg_id}/react", {"emoji": "🔥"})
    run_test("Star Message", "POST", f"/messages/{msg_id}/star", {"starred": True})
    run_test("Pin Message", "POST", f"/messages/{msg_id}/pin", {"pinned": True})
    run_test("Get Pinned Messages", "GET", f"/chats/{contact_id}/pinned")
    run_test("Get Starred Messages", "GET", "/messages/starred")
    run_test("Get Receipts", "GET", f"/messages/{msg_id}/receipts")
    run_test("Edit Message", "POST", "/messages/edit", {"message_id": msg_id, "contact_id": contact_id, "text": "Edited text"})
    run_test("Forward Message", "POST", "/messages/forward", {"msg_ids": [msg_id], "target_contact_ids": [contact_id]})
    run_test("Mark View Once", "POST", f"/messages/{msg_id}/view-once", {})

# 6. Polls
run_test("Create Poll", "POST", "/polls/create", {
    "chat_id": contact_id,
    "question": "Which feature do you like most?",
    "options": ["Fast Chat", "Audio/Video Calls", "Communities", "All of them"],
    "multiple_answers": False
})

# 7. Disappearing Messages & Chat Preferences
run_test("Set Disappearing Timer", "POST", f"/contacts/{contact_id}/disappearing", {"timer": 86400})
run_test("Set Wallpaper", "POST", f"/chats/{contact_id}/wallpaper", {"wallpaper": "nebula_dark"})
run_test("Toggle Pin Chat", "POST", f"/chats/{contact_id}/pin", {"pinned": True})
run_test("Toggle Mute Chat", "POST", f"/chats/{contact_id}/mute", {"muted": True})
run_test("Toggle Archive Chat", "POST", f"/chats/{contact_id}/archive", {"archived": True})
run_test("Get Archived Chats", "GET", "/chats/archived")
run_test("Get Chat Preferences", "GET", "/chats/preferences")
run_test("Get Chat Media", "GET", f"/chats/{contact_id}/media")
run_test("Export Chat", "GET", f"/chats/{contact_id}/export")

# 8. Typing & Presence
run_test("Set Typing", "POST", "/typing", {"contact_id": contact_id, "is_typing": True})
run_test("Get Typing", "GET", f"/typing/{contact_id}")
run_test("Update Presence", "POST", "/presence/update", {"status": "online"})
run_test("Get Presence", "GET", f"/presence/{PHONE}")

# 9. Status / Stories
run_test("Get Statuses", "GET", "/statuses")
run_test("Create Status", "POST", "/status/create", {
    "type": "text",
    "text": "Excited for GebTalk updates!",
    "bgColor": "#00FFCC"
})

# 10. Groups & Broadcasts
run_test("Create Group", "POST", "/groups/create", {
    "name": "GebTalk Alpha Testers",
    "members": [PHONE, "+94770000001"],
    "description": "Group for testing all features"
})
run_test("Broadcast Lists Get", "GET", "/broadcast/lists")
run_test("Broadcast List Create", "POST", "/broadcast/lists", {
    "name": "Product Announcements",
    "recipients": ["+94770000001", "+94770000002"]
})
run_test("Send Broadcast", "POST", "/broadcast", {
    "recipients": ["+94770000001"],
    "text": "Broadcast update message!"
})
run_test("Get Broadcast History", "GET", "/broadcast/history")

# 11. Calls & WebRTC
run_test("Get Call Logs", "GET", "/calls")
run_test("Log Call", "POST", "/calls/log", {
    "caller_id": PHONE,
    "receiver_id": contact_id,
    "type": "video",
    "status": "completed",
    "duration": 45
})
run_test("Create Call", "POST", "/calls/create", {
    "caller_id": PHONE,
    "receiver_id": contact_id,
    "call_type": "video",
    "offer": {"type": "offer", "sdp": "v=0..."}
})
run_test("Get Incoming Calls", "GET", f"/calls/incoming?callee_id={PHONE}")
run_test("Create Call Link", "POST", "/calls/link", {"title": "Team Standup"})
run_test("Start Email Call", "POST", "/calls/email/start", {"recipient_email": "client@example.com", "caller_name": "Victor"})
run_test("Get Email Call History", "GET", "/calls/email/history")

# 12. Channels, Communities, Newsletters, Wallet
run_test("Get Channels", "GET", "/channels")
run_test("Get Communities", "GET", "/communities")
run_test("Create Community", "POST", "/communities", {"name": "Tech Innovators", "description": "Community for devs"})
run_test("Get Newsletters", "GET", "/newsletters")
run_test("Get Wallet Balance", "GET", "/wallet/balance")
run_test("Send Payment", "POST", "/payments/send", {"receiver_id": contact_id, "amount": 10.0, "currency": "USD", "note": "Lunch"})
run_test("Get Payment History", "GET", "/payments/history")
run_test("Get Linked Devices", "GET", "/devices")
run_test("Link Device", "POST", "/devices/link", {"device_name": "MacBook Pro", "device_type": "desktop"})
run_test("Get Storage Summary", "GET", "/storage/summary")
run_test("Get Stickers Packs", "GET", "/stickers/packs")
run_test("Search GIFs", "GET", "/gifs/search?q=happy")

# 13. AI Features
run_test("AI Translate", "POST", "/ai/translate", {"text": "Hello, how are you?", "target_lang": "es"})
run_test("AI Summarize", "POST", "/ai/summarize", {"contact_id": contact_id})

# 14. Report & Block
run_test("Report Contact", "POST", "/report", {"reported_id": contact_id, "reason": "spam"})
run_test("Toggle Block Contact", "POST", f"/contacts/{contact_id}/block", {"blocked": True})
run_test("Get Blocked Contacts", "GET", "/contacts/blocked")
run_test("Unblock Contact", "POST", f"/contacts/{contact_id}/block", {"blocked": False})

print("\n=== Verification Summary ===")
total = len(results)
passed_count = sum(1 for r in results if r['passed'])
failed_count = total - passed_count
print(f"Total Tests: {total} | Passed: {passed_count} | Failed: {failed_count}")
if failed_count > 0:
    print("\nFailed Endpoints:")
    for r in results:
        if not r['passed']:
            print(f"- {r['method']} {r['path']} -> Code {r['status']}: {r['error']}")
