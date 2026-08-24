import 'call_audio_tone_player_stub.dart'
    if (dart.library.js_interop) 'call_audio_tone_player_web.dart'
    if (dart.library.html) 'call_audio_tone_player_web.dart';

class CallAudioTonePlayer {
  static void unlockAudio() {
    CallAudioTonePlayerImpl.unlockAudio();
  }

  static void playOutgoingDialTone() {
    CallAudioTonePlayerImpl.playOutgoingDialTone();
  }

  static void playIncomingRingtone() {
    CallAudioTonePlayerImpl.playIncomingRingtone();
  }

  static void playCallConnectedChime() {
    CallAudioTonePlayerImpl.playCallConnectedChime();
  }

  static void playCallEndedTone() {
    CallAudioTonePlayerImpl.playCallEndedTone();
  }

  static void stopAllTones() {
    CallAudioTonePlayerImpl.stopAllTones();
  }
}
