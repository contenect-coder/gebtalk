# GEBTALK WebRTC | Pure Internet Audio Calling MVP

A production-ready, peer-to-peer VoIP audio calling application operating entirely over the internet using **WebRTC** and a **Node.js + TypeScript WebSocket Signaling Server**.

This system **does not use traditional telephone networks (PSTN)** and does not depend on phone numbers, SMS, cellular minutes, or paid telecom SDKs (Twilio/Agora/Vonage).

---

## 🏗️ Architecture

```text
  [ Client A (React + TS) ]                       [ Client B (React + TS) ]
             |                                                |
             |------------- WebSocket Signaling ------------->|
             |       (Register, Ringing, Offer, Answer, ICE)  |
             |                       |                        |
             |                       v                        |
             |            [ Node.js + TS Server ]             |
             |             (Port 8080 - ws, HTTP)             |
             |                                                |
             |<=============== WebRTC Audio =================>|
             |            Direct P2P (Opus Codec)             |
```

### Components

1. **Signaling Server (`backend/`)**:
   * **Node.js + TypeScript + WebSocket (`ws`)**
   * Manages client registration, live presence directory (`online`, `offline`, `busy`, `calling`), and secure message routing.
   * Enforces message authentication: prevents spoofing/impersonation of User IDs.
   * Exposes HTTP `/health` and `/ice-config` endpoints.

2. **WebRTC Call Client (`frontend/`)**:
   * **React 18 + Vite + TypeScript**
   * `WebRTCCallManager`: Manages `RTCPeerConnection`, `getUserMedia({ audio: true, video: false })`, dynamic ICE candidate queuing, and audio playback via HTMLAudioElement.
   * `SignalingClient`: WebSocket client with automatic reconnection and heartbeat ping-pong.
   * `useWebRTCCall`: React state hook orchestrating call states, duration timers, and microphone muting.

3. **NAT Traversal**:
   * Pre-configured with public **Google & Cloudflare STUN** servers.
   * Fully configurable with custom **TURN servers** via `.env`.

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# In the webrtc_calling directory:
npm install --prefix backend
npm install --prefix frontend
```

### 2. Start the Backend Signaling Server

```bash
npm run dev:backend
```
* Signaling WebSocket server will start on `ws://localhost:8080`
* HTTP Health Check: `http://localhost:8080/health`
* ICE Configuration: `http://localhost:8080/ice-config`

### 3. Start the Frontend React Web App

```bash
npm run dev:frontend
```
* Vite Dev Server will launch on `http://localhost:3000`

---

## 🧪 Testing with Two Clients

1. Open **two separate browser windows** (or one normal and one incognito tab):
   * Window 1: `http://localhost:3000?user=alice`
   * Window 2: `http://localhost:3000?user=bob`
2. In Window 1 (Alice), you will see **Bob** listed in the Active Network Directory.
3. Click **Call** on Bob (or type `bob` in the Direct Call input).
4. Window 2 (Bob) will display the **Incoming Call modal** with Answer & Decline options.
5. Click **Answer** on Bob:
   * Both clients establish a real WebRTC audio connection.
   * Call duration timer starts (`00:00`, `00:01`, `00:02`...).
   * Audio wave visualizer displays active media streaming.
6. Test **Mute**: Click the microphone button to disable audio track without dropping connection.
7. Click **Hang Up**: Both clients cleanly tear down WebRTC streams and return to `IDLE`.

---

## ⚙️ Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8080` | Signaling server port |
| `HOST` | `0.0.0.0` | Binding host address |
| `VITE_WS_SERVER_URL` | `ws://localhost:8080` | Frontend signaling server address |
| `STUN_SERVER_URL` | `stun:stun.l.google.com:19302` | Public STUN server list |
| `TURN_SERVER_URL` | `""` | Optional TURN relay server |
| `TURN_USERNAME` | `""` | TURN credentials |
| `TURN_CREDENTIAL` | `""` | TURN password/secret |
| `CALL_RING_TIMEOUT` | `30000` | Incoming/Outgoing ring timeout in ms |
| `WEBRTC_CONNECTION_TIMEOUT` | `20000` | Media connection timeout in ms |

---

## 🔬 Automated Tests

Run the full automated test suite:

```bash
npm test
```

### Test Coverage
* **`presence.test.ts`**: User registration, status changes to `busy`/`online`, disconnect cleanup.
* **`signaling.test.ts`**: Call session lifecycle, state transitions, active call tracking.
* **`callState.test.ts`**: All 11 required lifecycle transitions (`IDLE -> CALLING -> RINGING -> CONNECTING -> CONNECTED -> DISCONNECTED -> IDLE`, duration formatting, invalid transition prevention).
* **`callFlow.test.ts`**: Dual-client simulated WebRTC signaling integration test (Register -> Call -> Ring -> Accept -> Offer -> Answer -> ICE -> Hangup).

---

## 🔒 Production Considerations

1. **HTTPS & WSS**:
   * WebRTC requires a Secure Context (`https://` and `wss://`) in production browsers for microphone access.
2. **TURN Servers**:
   * While STUN resolves direct P2P connections on open networks, Symmetric NATs and strict corporate firewalls require a TURN relay server (e.g. Coturn, Metered, Twilio Network Traversal).
3. **Horizontal Scaling**:
   * For multiple signaling nodes, use **Redis Pub/Sub** to synchronize presence and route call requests between servers.
4. **Mobile Background Calling**:
   * Integrate the provided `NotificationService` interface with **Firebase Cloud Messaging (FCM)** and **Apple Push Notification service (APNs)** with CallKit / ConnectionService for native lockscreen incoming calls.
