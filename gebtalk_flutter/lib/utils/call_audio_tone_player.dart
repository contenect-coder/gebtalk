import 'call_audio_manager.dart';

/// Backwards-compatible facade for call tone playing, delegating to CallAudioManager
class CallAudioTonePlayer {
  static void unlockAudio() {
    CallAudioManager.unlockAudio();
  }

  static void playOutgoingDialTone() {
    CallAudioManager.startOutgoingDialTone();
  }

  static void playIncomingRingtone() {
    CallAudioManager.startIncomingRingtone();
  }

  static void playCallConnectedChime() {
    CallAudioManager.playCallConnectedChime();
  }

  static void playCallEndedTone() {
    CallAudioManager.playCallEndedTone();
  }

  static void stopAllTones() {
    CallAudioManager.stopRingtone();
  }
}
