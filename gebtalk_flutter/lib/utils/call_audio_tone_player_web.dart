import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class CallAudioTonePlayerImpl {
  static web.AudioContext? _audioContext;
  static Timer? _loopTimer;
  static bool _isPlayingLoop = false;

  static web.AudioContext _getContext() {
    if (_audioContext == null || _audioContext!.state == 'closed') {
      _audioContext = web.AudioContext();
    }
    if (_audioContext!.state == 'suspended') {
      _audioContext!.resume();
    }
    return _audioContext!;
  }

  /// Plays outgoing call dial/ringback tone (repeated 2-second dual tone)
  static void playOutgoingDialTone() {
    stopAllTones();
    _isPlayingLoop = true;

    void playSingleRingback() {
      if (!_isPlayingLoop) return;
      try {
        final ctx = _getContext();
        final now = ctx.currentTime;

        // Dual Tone: 440 Hz + 480 Hz (Standard North American / International Ringback)
        final osc1 = ctx.createOscillator();
        final osc2 = ctx.createOscillator();
        final gain = ctx.createGain();

        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(440, now);

        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(480, now);

        // Smooth volume envelope: fade in, hold, fade out
        gain.gain.setValueAtTime(0.0, now);
        gain.gain.linearRampToValueAtTime(0.35, now + 0.05);
        gain.gain.setValueAtTime(0.35, now + 1.85);
        gain.gain.linearRampToValueAtTime(0.0, now + 2.0);

        osc1.connect(gain);
        osc2.connect(gain);
        gain.connect(ctx.destination);

        osc1.start(now);
        osc2.start(now);
        osc1.stop(now + 2.0);
        osc2.stop(now + 2.0);
      } catch (e) {
        debugPrint('[TonePlayer] Error playing outgoing ringback tone: $e');
      }
    }

    // Play immediately, then repeat every 4.5 seconds
    playSingleRingback();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      playSingleRingback();
    });
  }

  /// Plays incoming call melodic ringtone loop
  static void playIncomingRingtone() {
    stopAllTones();
    _isPlayingLoop = true;

    void playMelodicPattern() {
      if (!_isPlayingLoop) return;
      try {
        final ctx = _getContext();
        final now = ctx.currentTime;

        // Melodic notes sequence: E5 (659Hz), G#5 (830Hz), B5 (987Hz), E6 (1318Hz)
        final notes = [
          {'freq': 659.25, 'start': 0.0, 'dur': 0.18},
          {'freq': 830.61, 'start': 0.2, 'dur': 0.18},
          {'freq': 987.77, 'start': 0.4, 'dur': 0.18},
          {'freq': 1318.51, 'start': 0.6, 'dur': 0.35},
          {'freq': 987.77, 'start': 1.0, 'dur': 0.18},
          {'freq': 1318.51, 'start': 1.2, 'dur': 0.45},
        ];

        for (final note in notes) {
          final osc = ctx.createOscillator();
          final gain = ctx.createGain();
          final noteStart = now + (note['start'] as double);
          final noteDur = note['dur'] as double;

          osc.type = 'triangle';
          osc.frequency.setValueAtTime(note['freq'] as double, noteStart);

          gain.gain.setValueAtTime(0.0, noteStart);
          gain.gain.linearRampToValueAtTime(0.40, noteStart + 0.03);
          gain.gain.linearRampToValueAtTime(0.0, noteStart + noteDur);

          osc.connect(gain);
          gain.connect(ctx.destination);

          osc.start(noteStart);
          osc.stop(noteStart + noteDur);
        }
      } catch (e) {
        debugPrint('[TonePlayer] Error playing incoming ringtone: $e');
      }
    }

    playMelodicPattern();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      playMelodicPattern();
    });
  }

  /// Plays short positive call connected chime
  static void playCallConnectedChime() {
    stopAllTones();
    try {
      final ctx = _getContext();
      final now = ctx.currentTime;

      final chords = [
        {'freq': 523.25, 'start': 0.0, 'dur': 0.15}, // C5
        {'freq': 659.25, 'start': 0.12, 'dur': 0.15}, // E5
        {'freq': 783.99, 'start': 0.24, 'dur': 0.28}, // G5
      ];

      for (final n in chords) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        final st = now + (n['start'] as double);
        final dur = n['dur'] as double;

        osc.type = 'sine';
        osc.frequency.setValueAtTime(n['freq'] as double, st);

        gain.gain.setValueAtTime(0.0, st);
        gain.gain.linearRampToValueAtTime(0.35, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }
    } catch (e) {
      debugPrint('[TonePlayer] Error playing connected chime: $e');
    }
  }

  /// Plays short call disconnect/ended tone
  static void playCallEndedTone() {
    stopAllTones();
    try {
      final ctx = _getContext();
      final now = ctx.currentTime;

      final tones = [
        {'freq': 480.0, 'start': 0.0, 'dur': 0.15},
        {'freq': 440.0, 'start': 0.18, 'dur': 0.25},
      ];

      for (final n in tones) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        final st = now + (n['start'] as double);
        final dur = n['dur'] as double;

        osc.type = 'sine';
        osc.frequency.setValueAtTime(n['freq'] as double, st);

        gain.gain.setValueAtTime(0.0, st);
        gain.gain.linearRampToValueAtTime(0.30, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }
    } catch (e) {
      debugPrint('[TonePlayer] Error playing ended tone: $e');
    }
  }

  /// Immediately stops all playing sounds and cancel loops
  static void stopAllTones() {
    _isPlayingLoop = false;
    _loopTimer?.cancel();
    _loopTimer = null;
  }
}
