import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Native mobile / desktop stub for WebRtcAudioSink
class WebRtcAudioSinkImpl {
  static const _channel = MethodChannel('gebtalk/audio_control');
  static bool _isSpeaker = false;

  static Future<bool> checkAndRequestMicrophonePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkAndRequestMicrophonePermission');
      return result ?? true;
    } catch (e) {
      debugPrint('[WebRtcAudioSink] checkAndRequestMicrophonePermission error: $e');
      return true;
    }
  }

  static void attachRemoteAudio(MediaStream stream) {
    // Native mobile handles audio track decoding through native WebRTC engine
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    // Native mobile handles audio track decoding through native WebRTC engine
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
    _isSpeaker = isSpeaker;
    try {
      await _channel.invokeMethod('setSpeakerphoneOn', {'isSpeaker': isSpeaker});
    } catch (_) {}
  }

  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    return [];
  }

  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    return [];
  }

  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    return true;
  }

  static Map<String, dynamic> getAudioDiagnostics() {
    return {
      'elementConnected': true,
      'isPlaying': true,
      'isPaused': false,
      'isMuted': false,
      'volume': 1.0,
      'hasSrcObject': true,
      'activeSink': _isSpeaker ? 'Loudspeaker' : 'Earpiece / Receiver',
    };
  }
}
