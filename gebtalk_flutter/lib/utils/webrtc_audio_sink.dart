import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_audio_sink_stub.dart'
    if (dart.library.js_interop) 'webrtc_audio_sink_web.dart'
    if (dart.library.html) 'webrtc_audio_sink_web.dart';

class WebRtcAudioSink {
  static void attachRemoteAudio(MediaStream stream) {
    WebRtcAudioSinkImpl.attachRemoteAudio(stream);
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    WebRtcAudioSinkImpl.attachRemoteTrack(track);
  }

  static void detachRemoteAudio() {
    WebRtcAudioSinkImpl.detachRemoteAudio();
  }
}
