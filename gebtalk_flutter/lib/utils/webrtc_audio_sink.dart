import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_audio_sink_stub.dart'
    if (dart.library.js_interop) 'webrtc_audio_sink_web.dart'
    if (dart.library.html) 'webrtc_audio_sink_web.dart';

/// Unified Call Audio Manager & WebRTC Audio Sink Interface
class WebRtcAudioSink {
  static Future<bool> checkAndRequestMicrophonePermission() async {
    return await WebRtcAudioSinkImpl.checkAndRequestMicrophonePermission();
  }

  static void attachRemoteAudio(MediaStream stream) {
    WebRtcAudioSinkImpl.attachRemoteAudio(stream);
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    WebRtcAudioSinkImpl.attachRemoteTrack(track);
  }

  static void detachRemoteAudio() {
    WebRtcAudioSinkImpl.detachRemoteAudio();
  }

  static void unlockAudio() {
    WebRtcAudioSinkImpl.unlockAudio();
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    await WebRtcAudioSinkImpl.setSpeakerphoneOn(isSpeaker);
  }

  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    return await WebRtcAudioSinkImpl.getAudioInputDevices();
  }

  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    return await WebRtcAudioSinkImpl.getAudioOutputDevices();
  }

  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    return await WebRtcAudioSinkImpl.setAudioOutputDevice(deviceId, label: label);
  }

  static Map<String, dynamic> getAudioDiagnostics() {
    return WebRtcAudioSinkImpl.getAudioDiagnostics();
  }
}
