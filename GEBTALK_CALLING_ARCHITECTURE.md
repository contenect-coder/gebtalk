# GEBTALK — A to Z Calling Architecture & Background VoIP System Specification

## 1. Executive Summary
GEBTALK is an enterprise real-time business communication system. This document defines the complete end-to-end architecture for **Background & Closed-App Incoming VoIP Calling**, decoupling **Push / Wake-Up (Layer 2)** and **Authoritative Call Signaling (Layer 1)** from **WebRTC Real-Time Audio Transport (Layer 3)**.

---

## 2. 3-Layer Core Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           1. CALL SIGNALING                             │
│  - Authoritative Call Service & State Machine on GEBTALK Backend       │
│  - Generates Unique Call ID: CALL-XXXXXXXX                              │
│  - Enforces Role Permissions (Universal CEO, Assigned Staff, Isolated)  │
│  - Endpoints: /calls/create, /calls/accept, /calls/cancel, /calls/decline│
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    2. PUSH / BACKGROUND CALL WAKE-UP                    │
│  - Device Registration: user_devices table tracks userId, deviceId,    │
│    platform (ANDROID / IOS / WEB), pushToken, voipToken, is_active      │
│  - PushService (Push = Doorbell 🔔): High-priority data-only wake-up    │
│    payload (call_id, caller_name, call_type, timestamp)                 │
│  - Multi-Device Forking: Answer on Device A cancels ringing on B & C   │
│  - Cancellation & Decline: Synchronous teardown across all devices      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           3. WEBRTC MEDIA                               │
│  - Pure VoIP Encrypted Real-Time Audio (SRTP / DTLS)                   │
│  - Mobile: MODE_IN_COMMUNICATION + TYPE_BUILTIN_EARPIECE (Top Receiver)│
│  - Desktop: HTMLMediaElement.setSinkId (Selected Headphones / Headset)  │
│  - STUN / TURN dynamic ICE infrastructure                               │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Authoritative Call Lifecycle & State Machine

```text
[IDLE] ───(create call)───► [RINGING] ───(accept)───► [CONNECTING] ───(media up)───► [CONNECTED]
   ▲                            │                           │                           │
   │                     (caller cancels)            (network drop)                 (hang up)
   │                            ▼                           ▼                           ▼
   └───────────────────── [CANCELLED] / [REJECTED] / [MISSED] / [FAILED] / [ENDED] ─────┘
                                ▲
                         (callee in call)
                                │
                            [BUSY 486]
```

---

## 4. Database Schema (Supabase / PostgreSQL)

### 4.1. `user_devices`
Stores registered devices for push wake-up dispatch.
```sql
CREATE TABLE IF NOT EXISTS user_devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    platform TEXT NOT NULL,               -- 'ANDROID', 'IOS', 'WEB', 'DESKTOP'
    push_token TEXT,
    voip_token TEXT,
    device_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, device_id)
);
```

### 4.2. `webrtc_calls`
Authoritative call session state.
```sql
CREATE TABLE IF NOT EXISTS webrtc_calls (
    id SERIAL PRIMARY KEY,
    caller_id TEXT NOT NULL,
    callee_id TEXT NOT NULL,
    call_type TEXT DEFAULT 'voice',
    sdp_offer TEXT,
    sdp_answer TEXT,
    status TEXT DEFAULT 'ringing',
    answered_by_device_id TEXT,
    answered_at TIMESTAMP,
    ended_at TIMESTAMP,
    duration_seconds INTEGER DEFAULT 0,
    cancel_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 4.3. `call_logs`
Historical call records for user call history screens.
```sql
CREATE TABLE IF NOT EXISTS call_logs (
    id SERIAL PRIMARY KEY,
    contact_id TEXT NOT NULL,
    contact_name TEXT,
    contact_avatar TEXT,
    call_type TEXT DEFAULT 'voice',
    direction TEXT,                       -- 'incoming', 'outgoing', 'missed', 'declined'
    time_str TEXT,
    duration TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## 5. Platform Call Handling Flow

### 5.1. Android Native Flow
1. Backend sends high-priority FCM data payload (`type: "incoming_call"`).
2. Android Background Service receives payload and requests `USE_FULL_SCREEN_INTENT`.
3. System shows full-screen incoming call UI on locked/unlocked screen.
4. User presses Answer:
   - Sets `AudioManager.MODE_IN_COMMUNICATION`.
   - Acquires `AudioDeviceInfo.TYPE_BUILTIN_EARPIECE`.
   - Initializes WebRTC peer connection and establishes SRTP voice.

### 5.2. iOS Flow
1. Backend sends APNs VoIP push to target `voip_token`.
2. iOS receives `PKPushRegistry` notification in background/terminated state.
3. App immediately reports call to `CallKit` (`CXProvider.reportNewIncomingCall`).
4. System presents native iOS call interface on lock screen.
5. User presses Answer:
   - Configures `AVAudioSessionCategoryPlayAndRecord` (voiceChat mode).
   - Establishes WebRTC media track.

### 5.3. Desktop & Web Flow
1. Active Tab: Real-time signaling displays animated incoming call overlay.
2. Background Tab: W3C HTML5 `Notification` displays desktop toast with click-to-answer action.
3. Output Sink: `webrtc_audio_sink_web.dart` automatically selects connected headphones via `HTMLMediaElement.setSinkId()`.

---

## 6. Security & Authorization

- **Token Validation**: Caller identity is strictly resolved from validated JWT session headers (`get_authenticated_phone()`). Client cannot spoof `caller_id`.
- **Role Isolation**:
  - `CEO`: Universal dialing access.
  - `Staff`: Can only initiate calls to assigned customer contacts.
  - `Customer`: Can only call their dedicated assigned specialist.
- **Data Protection**: Push notification payloads contain zero voice/audio data and zero credentials.

---

## 7. Known Operating System Limitations & Guidelines

1. **Fully Terminated Web Browser**: Standard browsers (Chrome, Edge, Safari) cannot execute JavaScript when all tabs/windows are closed. PWA service workers handle background notifications when the browser engine is loaded.
2. **Apple CallKit Mandate**: All PushKit notifications on iOS must immediately report a CallKit call; non-compliance triggers revocation by iOS.
3. **Android Battery Optimizations**: OEM battery savers (Xiaomi, Samsung) may delay normal notifications; high-priority data FCM with full-screen intent is required for instantaneous wake-up.
