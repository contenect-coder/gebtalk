import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_audio_manager_stub.dart'
    if (dart.library.js_interop) 'call_audio_manager_web.dart'
    if (dart.library.html) 'call_audio_manager_web.dart';

/// Centralized Call Audio Manager for GEBTALK
/// Coordinates Ringtone Audio, Remote WebRTC Conversation Audio, Autoplay Unlocking,
/// Device Routing, and Diagnostic HUD.
class CallAudioManager {
  static Future<void> initializeAudio() async {
    await CallAudioManagerImpl.initializeAudio();
  }

  static void unlockAudio() {
    CallAudioManagerImpl.unlockAudio();
  }

  static Future<bool> checkAndRequestMicrophonePermission() async {
    return await CallAudioManagerImpl.checkAndRequestMicrophonePermission();
  }

  static Future<void> startIncomingRingtone() async {
    await CallAudioManagerImpl.startIncomingRingtone();
  }

  static Future<void> startOutgoingDialTone() async {
    await CallAudioManagerImpl.startOutgoingDialTone();
  }

  static void stopRingtone() {
    CallAudioManagerImpl.stopRingtone();
  }

  static void playCallConnectedChime() {
    CallAudioManagerImpl.playCallConnectedChime();
  }

  static void playCallEndedTone() {
    CallAudioManagerImpl.playCallEndedTone();
  }

  static void attachRemoteAudio(MediaStream stream) {
    CallAudioManagerImpl.attachRemoteAudio(stream);
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    CallAudioManagerImpl.attachRemoteTrack(track);
  }

  static void stopRemoteAudio() {
    CallAudioManagerImpl.stopRemoteAudio();
  }

  static void cleanup() {
    CallAudioManagerImpl.cleanup();
  }

  static Future<bool> testSpeaker() async {
    return await CallAudioManagerImpl.testSpeaker();
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    await CallAudioManagerImpl.setSpeakerphoneOn(isSpeaker);
  }

  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    return await CallAudioManagerImpl.getAudioInputDevices();
  }

  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    return await CallAudioManagerImpl.getAudioOutputDevices();
  }

  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    return await CallAudioManagerImpl.setAudioOutputDevice(deviceId, label: label);
  }

  static Map<String, dynamic> getDiagnostics() {
    return CallAudioManagerImpl.getDiagnostics();
  }
}
