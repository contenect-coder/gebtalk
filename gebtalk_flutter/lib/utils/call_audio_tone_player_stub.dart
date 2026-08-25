import 'package:flutter/services.dart';

class CallAudioTonePlayerImpl {
  static const _channel = MethodChannel('gebtalk/audio_control');

  static void unlockAudio() {}

  static void playOutgoingDialTone() {
    try {
      _channel.invokeMethod('playOutgoingDialTone');
    } catch (_) {}
  }

  static void playIncomingRingtone() {
    try {
      _channel.invokeMethod('playIncomingRingtone');
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

  static void stopAllTones() {
    try {
      _channel.invokeMethod('stopAllTones');
    } catch (_) {}
  }
}
