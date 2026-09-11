import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_audio_manager.dart';

/// Unified Call Audio Manager & WebRTC Audio Sink Interface delegating to CallAudioManager
class WebRtcAudioSink {
  static Future<bool> checkAndRequestMicrophonePermission() async {
    return await CallAudioManager.checkAndRequestMicrophonePermission();
  }

  static void attachRemoteAudio(MediaStream stream) {
    CallAudioManager.attachRemoteAudio(stream);
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    CallAudioManager.attachRemoteTrack(track);
  }

  static void detachRemoteAudio() {
    CallAudioManager.stopRemoteAudio();
  }

  static void unlockAudio() {
    CallAudioManager.unlockAudio();
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    await CallAudioManager.setSpeakerphoneOn(isSpeaker);
  }

  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    return await CallAudioManager.getAudioInputDevices();
  }

  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    return await CallAudioManager.getAudioOutputDevices();
  }

  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    return await CallAudioManager.setAudioOutputDevice(deviceId, label: label);
  }

  static Map<String, dynamic> getAudioDiagnostics() {
    return CallAudioManager.getDiagnostics();
  }

  static Future<bool> testSpeaker() async {
    return await CallAudioManager.testSpeaker();
  }
}
