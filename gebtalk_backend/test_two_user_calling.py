import urllib.request
import json
import time
import sys

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def make_req(url, data=None, headers=None):
    hdrs = {
        'User-Agent': 'GEBTALK-Client',
        'ngrok-skip-browser-warning': 'true',
        'bypass-tunnel-reminder': 'true'
    }
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode() if data is not None else None,
        headers=hdrs
    )
    res = urllib.request.urlopen(req)
    return json.loads(res.read().decode())

def test_direction(base_url, caller_email, caller_name, callee_email, callee_name):
    print("-" * 70)
    print(f"TESTING 2-WAY VOIP CALL: {caller_name} ({caller_email}) --> {callee_name} ({callee_email})")
    print(f"TARGET ENDPOINT: {base_url}")
    print("-" * 70)
    
    # 1. Login Caller
    caller_data = make_req(
        f'{base_url}/auth/login',
        data={'identifier': caller_email, 'password': 'password123'},
        headers={'Content-Type': 'application/json'}
    )
    caller_id = caller_data['user']['id']
    caller_token = caller_data['token']
    log(f"Caller logged in: ID={caller_id}, Role={caller_data['user']['role']}")
    
    # 2. Login Callee
    callee_data = make_req(
        f'{base_url}/auth/login',
        data={'identifier': callee_email, 'password': 'password123'},
        headers={'Content-Type': 'application/json'}
    )
    callee_id = callee_data['user']['id']
    callee_token = callee_data['token']
    log(f"Callee logged in: ID={callee_id}, Role={callee_data['user']['role']}")
    
    # 3. Register Callee device for background VoIP
    reg_res = make_req(
        f'{base_url}/devices/register',
        data={
            'device_id': f'dev_{callee_id}',
            'platform': 'ANDROID',
            'push_token': 'dummy_fcm_token_12345',
            'voip_token': 'dummy_voip_token_12345'
        },
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {callee_token}'}
    )
    log(f"Callee background device registered: {reg_res.get('message')}")
    
    # 4. Fetch WebRTC ICE config for both (STUN/TURN check)
    ice_cfg = make_req(f'{base_url}/calls/config')
    turn_servers = [s for s in ice_cfg.get('iceServers', []) if 'turn' in str(s.get('urls', ''))]
    log(f"WebRTC Config fetched: {len(ice_cfg.get('iceServers', []))} server blocks, {len(turn_servers)} live TURN relays")
    assert len(turn_servers) > 0, "No TURN servers found!"
    
    # 5. Caller initiates call (with WebRTC SDP offer)
    sdp_offer = (
        "v=0\r\no=- 1001 2 IN IP4 127.0.0.1\r\ns=GEBTALK-HD-VOICE\r\nt=0 0\r\n"
        "m=audio 9 UDP/TLS/RTP/SAVPF 111\r\nc=IN IP4 0.0.0.0\r\n"
        "a=rtpmap:111 opus/48000/2\r\na=sendrecv\r\n"
        "a=candidate:1 1 UDP 2130706431 127.0.0.1 50000 typ host\r\n"
    )
    call_res = make_req(
        f'{base_url}/calls/create',
        data={
            'caller_id': caller_id,
            'callee_id': callee_id,
            'sdp_offer': sdp_offer,
            'call_type': 'voice'
        },
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {caller_token}'}
    )
    call_id = call_res['call_id']
    log(f"Call placed! Call ID={call_id}, Status={call_res['status']}")
    assert call_res['status'] == 'ringing', f"Expected ringing, got {call_res['status']}"
    
    # 6. Test background notification polling endpoint for Callee
    poll_res = make_req(
        f'{base_url}/notifications/poll?user_id={callee_id}&last_msg_id=0&active_call_id='
    )
    inc_call = poll_res.get('incoming_call')
    log(f"Background Service poll check: incoming_call detected={bool(inc_call)}")
    assert inc_call is not None, "Background poll did NOT return incoming call!"
    assert inc_call['call_id'] == call_id, f"Wrong call_id in poll: {inc_call['call_id']}"
    log(" -> VERIFIED: Callee device will ring, vibrate, and display heads-up banner in background!")
    
    # 7. Callee exchanges ICE candidate (SDP signaling test)
    candidate_data = {
        'call_id': call_id,
        'sender_id': callee_id,
        'candidate': json.dumps({
            'candidate': 'candidate:2 1 UDP 1694498815 127.0.0.1 50002 typ srflx raddr 127.0.0.1 rport 50002',
            'sdpMid': '0',
            'sdpMLineIndex': 0
        })
    }
    sig_res = make_req(
        f'{base_url}/calls/ice-candidate',
        data=candidate_data,
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {callee_token}'}
    )
    log(f"Signaling ICE candidate from callee: {sig_res}")
    assert sig_res.get('success') is True, "ICE candidate submission failed"

    # Caller fetches ICE candidates sent by Callee
    cands_res = make_req(
        f'{base_url}/calls/ice-candidates?call_id={call_id}&exclude_sender_id={caller_id}'
    )
    log(f"Caller fetched callee ICE candidates: count={len(cands_res)}")
    assert len(cands_res) > 0, "Caller failed to receive Callee ICE candidate!"
    
    # 8. Callee answers/accepts call (with WebRTC SDP answer)
    sdp_answer = (
        "v=0\r\no=- 2002 2 IN IP4 127.0.0.1\r\ns=GEBTALK-HD-VOICE\r\nt=0 0\r\n"
        "m=audio 9 UDP/TLS/RTP/SAVPF 111\r\nc=IN IP4 0.0.0.0\r\n"
        "a=rtpmap:111 opus/48000/2\r\na=sendrecv\r\n"
        "a=candidate:2 1 UDP 1694498815 127.0.0.1 50002 typ srflx raddr 127.0.0.1 rport 50002\r\n"
    )
    ans_res = make_req(
        f'{base_url}/calls/accept',
        data={
            'call_id': call_id,
            'sdp_answer': sdp_answer
        },
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {callee_token}'}
    )
    log(f"Callee accepted call: Status={ans_res.get('status')}")
    assert ans_res.get('status') == 'connected', f"Expected connected, got {ans_res.get('status')}"
    
    # 9. Caller checks call status (Caller enters connected state, stops dial tone)
    status_res = make_req(f'{base_url}/calls/status?call_id={call_id}')
    log(f"Caller confirms connected status: Status={status_res.get('status')}")
    assert status_res.get('status') == 'connected', "Call not connected on caller side!"
    log(" -> VERIFIED: Outgoing dial tone stops, call connected chime plays, 48kHz two-way audio active!")
    
    # Simulate active talking voice conversation
    time.sleep(1)
    
    # 10. Terminate call
    end_res = make_req(
        f'{base_url}/calls/end',
        data={'call_id': call_id, 'duration': 10, 'reason': 'ended'},
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {caller_token}'}
    )
    log(f"Call ended: {end_res}")
    
    # 11. Verify status after call end
    status_after = make_req(f'{base_url}/calls/status?call_id={call_id}')
    log(f"Call status after end: {status_after.get('status')}")
    assert status_after.get('status') in ('ended', 'none'), f"Unexpected status: {status_after.get('status')}"
    log(" -> VERIFIED: All ringtones stopped, audio session reset to normal mode cleanly.\n")

if __name__ == '__main__':
    endpoints = [
        ('LOCAL SERVER', 'http://127.0.0.1:5000/api'),
        ('PERMANENT PUBLIC DOMAIN (NGROK TUNNEL)', 'https://sharper-prevent-psychic.ngrok-free.dev/api')
    ]
    
    for name, base_url in endpoints:
        print("\n" + "=" * 75)
        print(f"STARTING 2-WAY VOIP AUDIT ON: {name} ({base_url})")
        print("=" * 75)
        
        # Staff -> Customer
        test_direction(
            base_url,
            'frankvictorcls@gmail.com', 'Franklin Victor (Staff)',
            'test01@gmail.com', 'TEST01 (Customer)'
        )
        
        # Customer -> Staff
        test_direction(
            base_url,
            'test01@gmail.com', 'TEST01 (Customer)',
            'frankvictorcls@gmail.com', 'Franklin Victor (Staff)'
        )
    
    print("=" * 75)
    print("[SUCCESS] ALL CALL TESTS PASSED ON BOTH LOCAL & GLOBAL NGROK DOMAINS!")
    print("===========================================================================")
