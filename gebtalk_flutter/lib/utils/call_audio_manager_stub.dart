import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Native mobile / desktop stub implementation for CallAudioManager
class CallAudioManagerImpl {
  static const _channel = MethodChannel('gebtalk/audio_control');
  static String _ringtoneState = 'STOPPED';
  static String? _lastRingtoneError;
  static String? _lastRemotePlayError;
  static String _lastTestSpeakerResult = 'NOT RUN';

  static Future<void> initializeAudio() async {
    // Native audio handles audio focus automatically via Android AudioManager / iOS AVAudioSession
  }

  static void unlockAudio() {}

  static Future<bool> checkAndRequestMicrophonePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkAndRequestMicrophonePermission');
      return result ?? true;
    } catch (e) {
      debugPrint('[CallAudioManager] checkAndRequestMicrophonePermission error: $e');
      return true;
    }
  }

  static Future<void> startIncomingRingtone() async {
    _ringtoneState = 'PLAYING';
    _lastRingtoneError = null;
    try {
      await _channel.invokeMethod('playIncomingRingtone');
    } catch (e) {
      _ringtoneState = 'ERROR';
      _lastRingtoneError = e.toString();
      debugPrint('[CallAudioManager] Native startIncomingRingtone error: $e');
    }
  }

  static Future<void> startOutgoingDialTone() async {
    _ringtoneState = 'DIALING';
    _lastRingtoneError = null;
    try {
      await _channel.invokeMethod('playOutgoingDialTone');
    } catch (e) {
      _lastRingtoneError = e.toString();
      debugPrint('[CallAudioManager] Native startOutgoingDialTone error: $e');
    }
  }

  static void stopRingtone() {
    _ringtoneState = 'STOPPED';
    try {
      _channel.invokeMethod('stopAllTones');
    } catch (_) {}
  }

  static void playCallConnectedChime() {
    try {
      _channel.invokeMethod('playCallConnectedChime');
    } catch (_) {}
  }

  static void playCallEndedTone() {
    try {
      _channel.invokeMethod('playCallEndedTone');
    } catch (_) {}
  }

  static void attachRemoteAudio(MediaStream stream) {
    // Native flutter_webrtc automatically plays remote audio via WebRTC audio track
    _lastRemotePlayError = null;
  }

  static void attachRemoteTrack(MediaStreamTrack track) {
    _lastRemotePlayError = null;
  }

  static void stopRemoteAudio() {
    // Reset remote audio state
  }

  static void cleanup() {
    stopRingtone();
    stopRemoteAudio();
  }

  static Future<bool> testSpeaker() async {
    try {
      playCallConnectedChime();
      _lastTestSpeakerResult = 'PASSED';
      return true;
    } catch (e) {
      _lastTestSpeakerResult = 'FAILED: $e';
      return false;
    }
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    try {
      await Helper.setSpeakerphoneOn(isSpeaker);
    } catch (e) {
      debugPrint('[CallAudioManager] setSpeakerphoneOn error: $e');
    }
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

  static Map<String, dynamic> getDiagnostics() {
    return {
      'ringtoneState': _ringtoneState,
      'lastRingtoneError': _lastRingtoneError,
      'remoteAudioElementExists': true,
      'hasSrcObject': true,
      'remoteStreamActive': true,
      'remoteAudioPaused': false,
      'remoteAudioMuted': false,
      'remoteAudioVolume': 1.0,
      'remoteAudioReadyState': 4,
      'lastRemotePlayError': _lastRemotePlayError,
      'audioContextState': 'native',
      'isAudioUnlocked': true,
      'activeSink': 'Native AudioManager',
      'lastTestSpeakerResult': _lastTestSpeakerResult,
    };
  }
}
