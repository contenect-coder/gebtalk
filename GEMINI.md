# GEBTALK Project Instructions & Knowledge

## Android Build & APK
- **Android APK Built**: An Android release APK has been created and compiled for the GEBTALK mobile app.
- **APK Locations**:
  - Flutter Build Output: `gebtalk_flutter/build/app/outputs/flutter-apk/app-release.apk`
  - APK Release Output: `gebtalk_flutter/build/app/outputs/apk/release/app-release.apk`
  - Backend Uploads (served/distributed): `gebtalk_backend/uploads/gebtalk.apk`
  - Debug APK: `gebtalk_flutter/gebtalk-debug.apk`
- **Permanent Server URL (ngrok Static Domain)**:
  - Backend API: `https://sharper-prevent-psychic.ngrok-free.dev/api`
  - Health check: `https://sharper-prevent-psychic.ngrok-free.dev/api/health`
- **APK Download Links**:
  - Direct High-Speed GitHub Release (Recommended, no interstitial): `https://github.com/contenect-coder/gebtalk/releases/download/v1.0.6/gebtalk.apk`
  - Backend Uploads Server: `https://sharper-prevent-psychic.ngrok-free.dev/uploads/gebtalk.apk`
- **Key Mobile Configurations & Fixes Applied**:
  - **Native Android Foreground VoIP & Notification Service (`GebtalkBackgroundService.kt`)**: Added persistent Android foreground service with `phoneCall|dataSync` types, persistent sticky lifecycle, and boot receiver (`BootReceiver.kt`) to ensure incoming calls and chat notifications are received even when the app is completely closed or screen is locked.
  - **Heads-Up & Lockscreen Call Alerts**: Implemented high-priority incoming call notification channel with native ringtone loop, vibration, and interactive `ANSWER` / `DECLINE` notification buttons (`CallActionReceiver.kt`).
  - **Background Notification Polling Endpoint**: Created ultra-fast `/api/notifications/poll` endpoint in `app.py` returning ringing calls and unread messages in < 5ms.
  - **Direct Live Tunnel Integration**: Configured live tunnel URL directly as default `baseUrl` in APK.
  - **In-App Server Connection Switching (`ServerSettingsScreen`)**: Users can now change the backend URL (paste new Cloudflare tunnel, switch to local Wi-Fi, or reset to default) directly from Settings > Server Connection without reinstalling the APK. Network error SnackBars now show a "Change Server" action button.
  - Native speakerphone channel linked in `MainActivity.kt` with `CallAudioManager`.
  - **Global Metered TURN Relay Integration**: Dedicated Metered live TURN infrastructure (`gebtalk.metered.live`) integrated into backend `/api/calls/config` and Flutter WebRTC client (`global.relay.metered.ca`) across UDP 80/443, TCP 80, and TLS 443, enabling seamless audio connectivity through Symmetric Carrier-Grade NAT (4G cellular data) where direct STUN peer-to-peer connection is blocked by carrier firewalls.
