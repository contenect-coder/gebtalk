import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcAudioSinkImpl {
  static const _channel = MethodChannel('gebtalk/audio_control');

  static void attachRemoteAudio(MediaStream stream) {
    // Native mobile handles audio through OS audio framework
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    // Native mobile cleanup
  }

  static void detachRemoteAudio() {
    try {
      _channel.invokeMethod('resetAudioMode');
    } catch (_) {}
  }

  static void unlockAudio() {
    // Native mobile handles audio session
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    try {
      await _channel.invokeMethod('setSpeakerphoneOn', {'isSpeaker': isSpeaker});
    } catch (_) {}
  }
}
