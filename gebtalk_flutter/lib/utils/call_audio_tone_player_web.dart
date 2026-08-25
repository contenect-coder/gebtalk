import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class CallAudioTonePlayerImpl {
  static web.AudioContext? _audioContext;
  static Timer? _loopTimer;
  static bool _isPlayingLoop = false;
  static bool _listenersAttached = false;

  static void unlockAudio() {
    try {
      final ctx = _getContext();
      if (ctx.state == 'suspended') {
        ctx.resume();
      }
      if (!_listenersAttached) {
        _listenersAttached = true;
        void onUserGesture(web.Event e) {
          try {
            _audioContext?.resume();
          } catch (_) {}
        }
        web.window.addEventListener('click', onUserGesture.toJS);
        web.window.addEventListener('touchstart', onUserGesture.toJS);
        web.window.addEventListener('pointerdown', onUserGesture.toJS);
        web.window.addEventListener('keydown', onUserGesture.toJS);
      }
    } catch (e) {
      debugPrint('[TonePlayer] unlockAudio error: $e');
    }
  }

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
    unlockAudio();

    void playSingleRingback() {
      if (!_isPlayingLoop) return;
      try {
        final ctx = _getContext();
        if (ctx.state == 'suspended') {
          ctx.resume();
        }
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
        gain.gain.linearRampToValueAtTime(0.45, now + 0.05);
        gain.gain.setValueAtTime(0.45, now + 1.85);
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

    // Play immediately, then repeat every 4.0 seconds
    playSingleRingback();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 4000), (_) {
      playSingleRingback();
    });
  }

  /// Plays incoming call melodic ringtone loop
  static void playIncomingRingtone() {
    stopAllTones();
    _isPlayingLoop = true;
    unlockAudio();

    void playMelodicPattern() {
      if (!_isPlayingLoop) return;
      try {
        final ctx = _getContext();
        if (ctx.state == 'suspended') {
          ctx.resume();
        }
        final now = ctx.currentTime;

        // Clear harmonic musical sequence: C5 (523Hz), E5 (659Hz), G5 (784Hz), C6 (1046Hz), E6 (1318Hz)
        final notes = [
          {'freq': 659.25, 'start': 0.0, 'dur': 0.16},
          {'freq': 830.61, 'start': 0.18, 'dur': 0.16},
          {'freq': 987.77, 'start': 0.36, 'dur': 0.16},
          {'freq': 1318.51, 'start': 0.54, 'dur': 0.32},
          {'freq': 987.77, 'start': 0.90, 'dur': 0.16},
          {'freq': 1318.51, 'start': 1.08, 'dur': 0.40},
        ];

        for (final note in notes) {
          final osc = ctx.createOscillator();
          final gain = ctx.createGain();
          final noteStart = now + (note['start'] as double);
          final noteDur = note['dur'] as double;

          osc.type = 'triangle';
          osc.frequency.setValueAtTime(note['freq'] as double, noteStart);

          gain.gain.setValueAtTime(0.0, noteStart);
          gain.gain.linearRampToValueAtTime(0.60, noteStart + 0.03);
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
    _loopTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      playMelodicPattern();
    });
  }

  /// Plays short positive call connected chime
  static void playCallConnectedChime() {
    stopAllTones();
    try {
      final ctx = _getContext();
      if (ctx.state == 'suspended') {
        ctx.resume();
      }
      final now = ctx.currentTime;

      final chords = [
        {'freq': 523.25, 'start': 0.0, 'dur': 0.14}, // C5
        {'freq': 659.25, 'start': 0.10, 'dur': 0.14}, // E5
        {'freq': 783.99, 'start': 0.20, 'dur': 0.25}, // G5
        {'freq': 1046.50, 'start': 0.32, 'dur': 0.35}, // C6
      ];

      for (final n in chords) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        final st = now + (n['start'] as double);
        final dur = n['dur'] as double;

        osc.type = 'sine';
        osc.frequency.setValueAtTime(n['freq'] as double, st);

        gain.gain.setValueAtTime(0.0, st);
        gain.gain.linearRampToValueAtTime(0.50, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }

      // Suspend Web Audio context once connected chime finishes playing (allowing VoIP communications mode to take priority)
      Future.delayed(const Duration(milliseconds: 750), () {
        if (!_isPlayingLoop && _audioContext != null && _audioContext!.state == 'running') {
          try {
            _audioContext!.suspend();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[TonePlayer] Error playing connected chime: $e');
    }
  }

  /// Plays short call disconnect/ended tone
  static void playCallEndedTone() {
    stopAllTones();
    try {
      final ctx = _getContext();
      if (ctx.state == 'suspended') {
        ctx.resume();
      }
      final now = ctx.currentTime;

      final tones = [
        {'freq': 480.0, 'start': 0.0, 'dur': 0.12},
        {'freq': 440.0, 'start': 0.15, 'dur': 0.12},
        {'freq': 392.0, 'start': 0.30, 'dur': 0.22},
      ];

      for (final n in tones) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        final st = now + (n['start'] as double);
        final dur = n['dur'] as double;

        osc.type = 'sine';
        osc.frequency.setValueAtTime(n['freq'] as double, st);

        gain.gain.setValueAtTime(0.0, st);
        gain.gain.linearRampToValueAtTime(0.40, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!_isPlayingLoop && _audioContext != null && _audioContext!.state == 'running') {
          try {
            _audioContext!.suspend();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[TonePlayer] Error playing ended tone: $e');
    }
  }

  /// Immediately stops all playing sounds and cancel loops
  static void stopAllTones() {
    _isPlayingLoop = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    try {
      if (_audioContext != null && _audioContext!.state == 'running') {
        _audioContext!.suspend();
      }
    } catch (_) {}
  }
}
