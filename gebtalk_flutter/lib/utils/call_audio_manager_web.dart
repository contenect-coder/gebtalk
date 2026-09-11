import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

/// Production WebRTC Call Audio Manager & Diagnostics Engine for Web / Browsers
/// Implements full A-Z architectural separation between Ringtone and Remote Conversation Audio.
class CallAudioManagerImpl {
  // 1. Dedicated Remote WebRTC Conversation Pipeline
  static web.HTMLAudioElement? _remoteAudioElement;
  static web.AudioContext? _audioContext;
  static web.GainNode? _remoteGainNode;
  static web.MediaStreamAudioSourceNode? _mediaStreamSourceNode;
  static web.MediaStream? _currentJsStream;
  static String? _lastRemotePlayError;

  // 2. Dedicated Ringtone Pipeline
  static web.HTMLAudioElement? _ringtoneAudioElement;
  static Timer? _ringtoneLoopTimer;
  static bool _isRingtonePlaying = false;
  static String _ringtoneState = 'STOPPED'; // 'STOPPED', 'RINGING', 'DIALING', 'ERROR'
  static String? _lastRingtoneError;

  // 3. Audio Routing & Device Management
  static String? _activeSinkLabel = 'Default System Output';
  static String _selectedOutputDeviceId = '';
  static bool _currentSpeakerState = true;
  static bool _globalListenersAttached = false;
  static String _lastTestSpeakerResult = 'NOT RUN';

  static Future<bool> checkAndRequestMicrophonePermission() async {
    return true; // Web browser triggers native permission prompt upon getUserMedia()
  }

  /// Initializes the Web Audio environment from a genuine user interaction
  static Future<void> initializeAudio() async {
    try {
      _ensureGlobalGestureListeners();
      _ensureAudioContextUnlocked();
      _ensureRemoteElement();
      _ensureRingtoneElement();
      debugPrint('[CallAudioManager] Audio environment initialized successfully');
    } catch (e) {
      debugPrint('[CallAudioManager] Audio environment initialization error: $e');
    }
  }

  /// Initializes and resumes the AudioContext on user interaction
  static void _ensureAudioContextUnlocked() {
    try {
      if (_audioContext == null || _audioContext!.state == 'closed') {
        _audioContext = web.AudioContext();
      }
      if (_audioContext!.state == 'suspended') {
        _audioContext!.resume().toDart.then((_) {
          debugPrint('[CallAudioManager] AudioContext resumed successfully (state=${_audioContext?.state})');
        }).catchError((err) {
          debugPrint('[CallAudioManager] AudioContext resume error: $err');
        });
      }
    } catch (e) {
      debugPrint('[CallAudioManager] AudioContext initialization error: $e');
    }
  }

  /// Registers global gesture listeners on the document window for seamless audio unlock
  static void _ensureGlobalGestureListeners() {
    if (_globalListenersAttached) return;
    _globalListenersAttached = true;

    void onUserGesture(web.Event e) {
      unlockAudio();
    }

    try {
      web.window.addEventListener('touchstart', onUserGesture.toJS);
      web.window.addEventListener('touchend', onUserGesture.toJS);
      web.window.addEventListener('pointerdown', onUserGesture.toJS);
      web.window.addEventListener('click', onUserGesture.toJS);
      web.window.addEventListener('keydown', onUserGesture.toJS);
      debugPrint('[CallAudioManager] Attached global user-gesture audio unlock listeners');
    } catch (e) {
      debugPrint('[CallAudioManager] Error attaching gesture listeners: $e');
    }
  }

  /// Global unlock method triggered by UI taps and gesture listeners
  static void unlockAudio() {
    if (!kIsWeb) return;
    try {
      _ensureAudioContextUnlocked();

      // Retry remote audio if loaded but paused
      final remoteElem = _remoteAudioElement;
      if (remoteElem != null && remoteElem.srcObject != null && remoteElem.paused) {
        remoteElem.muted = false;
        remoteElem.volume = 1.0;
        remoteElem.play().toDart.then((_) {
          _lastRemotePlayError = null;
          debugPrint('[CallAudioManager] Remote audio unlocked and playing');
        }).catchError((err) {
          _lastRemotePlayError = err.toString();
          debugPrint('[CallAudioManager] Remote audio unlock error: $err');
        });
      }

      // Retry ringtone if in ringing state but paused
      if (_isRingtonePlaying && _ringtoneAudioElement != null && _ringtoneAudioElement!.paused) {
        _ringtoneAudioElement!.play().toDart.then((_) {
          _lastRingtoneError = null;
        }).catchError((err) {
          _lastRingtoneError = err.toString();
        });
      }
    } catch (e) {
      debugPrint('[CallAudioManager] unlockAudio error: $e');
    }
  }

  // ==========================================
  // PIPELINE 1: RINGBACK & RINGTONE SYSTEM
  // ==========================================

  static web.HTMLAudioElement _ensureRingtoneElement() {
    if (_ringtoneAudioElement == null) {
      _ringtoneAudioElement = web.HTMLAudioElement();
      _ringtoneAudioElement!.id = 'gebtalk_ringtone_player';
      _ringtoneAudioElement!.setAttribute('preload', 'auto');
      _ringtoneAudioElement!.setAttribute('playsinline', 'true');
      _ringtoneAudioElement!.style.position = 'fixed';
      _ringtoneAudioElement!.style.bottom = '0px';
      _ringtoneAudioElement!.style.left = '30px';
      _ringtoneAudioElement!.style.width = '24px';
      _ringtoneAudioElement!.style.height = '24px';
      _ringtoneAudioElement!.style.opacity = '0.9';
      _ringtoneAudioElement!.style.zIndex = '-999';
      _ringtoneAudioElement!.style.pointerEvents = 'none';

      web.document.body?.append(_ringtoneAudioElement!);
      debugPrint('[CallAudioManager] Created and attached #gebtalk_ringtone_player to DOM');
    }
    return _ringtoneAudioElement!;
  }

  /// Starts the incoming melodic call ringtone
  static Future<void> startIncomingRingtone() async {
    stopRingtone();
    _isRingtonePlaying = true;
    _ringtoneState = 'RINGING';
    _lastRingtoneError = null;
    debugPrint('[CallAudioManager][RINGTONE] Incoming ringtone requested');

    initializeAudio();

    void playMelodicPattern() {
      if (!_isRingtonePlaying) return;
      try {
        _ensureAudioContextUnlocked();
        final ctx = _audioContext;
        if (ctx == null) return;
        final now = ctx.currentTime + 0.05;

        // Harmonic musical sequence: E5 (659Hz), G#5 (830Hz), B5 (987Hz), E6 (1318Hz)
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
          gain.gain.linearRampToValueAtTime(0.85, noteStart + 0.03);
          gain.gain.linearRampToValueAtTime(0.0, noteStart + noteDur);

          osc.connect(gain);
          gain.connect(ctx.destination);

          osc.start(noteStart);
          osc.stop(noteStart + noteDur);
        }
      } catch (e) {
        _lastRingtoneError = e.toString();
        debugPrint('[CallAudioManager][RINGTONE] Error generating melodic ringtone: $e');
      }
    }

    playMelodicPattern();
    _ringtoneLoopTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      playMelodicPattern();
    });
  }

  /// Starts the outgoing dial / ringback tone (repeated international standard)
  static Future<void> startOutgoingDialTone() async {
    stopRingtone();
    _isRingtonePlaying = true;
    _ringtoneState = 'DIALING';
    _lastRingtoneError = null;
    debugPrint('[CallAudioManager][DIAL_TONE] Outgoing dial tone requested');

    initializeAudio();

    void playSingleRingback() {
      if (!_isRingtonePlaying) return;
      try {
        _ensureAudioContextUnlocked();
        final ctx = _audioContext;
        if (ctx == null) return;
        final now = ctx.currentTime + 0.05;

        // Dual Tone: 440 Hz + 480 Hz
        final osc1 = ctx.createOscillator();
        final osc2 = ctx.createOscillator();
        final gain = ctx.createGain();

        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(440, now);

        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(480, now);

        gain.gain.setValueAtTime(0.0, now);
        gain.gain.linearRampToValueAtTime(0.70, now + 0.06);
        gain.gain.setValueAtTime(0.70, now + 1.85);
        gain.gain.linearRampToValueAtTime(0.0, now + 2.0);

        osc1.connect(gain);
        osc2.connect(gain);
        gain.connect(ctx.destination);

        osc1.start(now);
        osc2.start(now);
        osc1.stop(now + 2.0);
        osc2.stop(now + 2.0);
      } catch (e) {
        _lastRingtoneError = e.toString();
        debugPrint('[CallAudioManager][DIAL_TONE] Error generating dial tone: $e');
      }
    }

    playSingleRingback();
    _ringtoneLoopTimer = Timer.periodic(const Duration(milliseconds: 4000), (_) {
      playSingleRingback();
    });
  }

  /// Immediately stops any active ringtone or dial tone
  static void stopRingtone() {
    _isRingtonePlaying = false;
    _ringtoneState = 'STOPPED';
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;

    if (_ringtoneAudioElement != null) {
      try {
        _ringtoneAudioElement!.pause();
        _ringtoneAudioElement!.currentTime = 0;
      } catch (_) {}
    }
    debugPrint('[CallAudioManager][RINGTONE] Ringtone stopped completely');
  }

  /// Plays short pleasant call connected chime
  static void playCallConnectedChime() {
    stopRingtone();
    try {
      _ensureAudioContextUnlocked();
      final ctx = _audioContext;
      if (ctx == null) return;
      final now = ctx.currentTime + 0.05;

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
        gain.gain.linearRampToValueAtTime(0.75, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }
    } catch (e) {
      debugPrint('[CallAudioManager] Error playing call connected chime: $e');
    }
  }

  /// Plays short call disconnect / ended tone
  static void playCallEndedTone() {
    stopRingtone();
    try {
      _ensureAudioContextUnlocked();
      final ctx = _audioContext;
      if (ctx == null) return;
      final now = ctx.currentTime + 0.05;

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
        gain.gain.linearRampToValueAtTime(0.65, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }
    } catch (e) {
      debugPrint('[CallAudioManager] Error playing call ended tone: $e');
    }
  }

  // ==========================================
  // PIPELINE 2: REMOTE WEBRTC CONVERSATION AUDIO
  // ==========================================

  static web.HTMLAudioElement _ensureRemoteElement() {
    if (_remoteAudioElement == null) {
      _remoteAudioElement = web.HTMLAudioElement();
      _remoteAudioElement!.id = 'gebtalk_remote_audio_player';
      _remoteAudioElement!.autoplay = true;
      _remoteAudioElement!.setAttribute('playsinline', 'true');
      _remoteAudioElement!.setAttribute('webkit-playsinline', 'true');
      _remoteAudioElement!.style.position = 'fixed';
      _remoteAudioElement!.style.bottom = '0px';
      _remoteAudioElement!.style.left = '0px';
      _remoteAudioElement!.style.width = '24px';
      _remoteAudioElement!.style.height = '24px';
      _remoteAudioElement!.style.opacity = '0.9';
      _remoteAudioElement!.style.zIndex = '-999';
      _remoteAudioElement!.style.pointerEvents = 'none';
      _remoteAudioElement!.volume = 1.0;
      _remoteAudioElement!.muted = false;

      void onPlaying(web.Event e) {
        debugPrint('[CallAudioManager][EVENT] Remote audio PLAYING (volume=${_remoteAudioElement?.volume}, muted=${_remoteAudioElement?.muted})');
        _lastRemotePlayError = null;
        try {
          _remoteGainNode?.gain.value = 0.0;
        } catch (_) {}
      }

      void onPause(web.Event e) {
        debugPrint('[CallAudioManager][EVENT] Remote audio PAUSED');
        try {
          _remoteGainNode?.gain.value = 1.0;
        } catch (_) {}
      }

      void onError(web.Event e) {
        final err = _remoteAudioElement?.error?.message ?? 'Unknown HTMLMediaElement error';
        _lastRemotePlayError = err;
        debugPrint('[CallAudioManager][EVENT] Remote audio ERROR: $err');
        try {
          _remoteGainNode?.gain.value = 1.0;
        } catch (_) {}
      }

      _remoteAudioElement!.addEventListener('playing', onPlaying.toJS);
      _remoteAudioElement!.addEventListener('pause', onPause.toJS);
      _remoteAudioElement!.addEventListener('error', onError.toJS);

      web.document.body?.append(_remoteAudioElement!);
      debugPrint('[CallAudioManager] Created and attached #gebtalk_remote_audio_player to DOM');
    }
    _ensureGlobalGestureListeners();
    return _remoteAudioElement!;
  }

  static void _connectWebAudioGraph(web.MediaStream jsStream) {
    try {
      _currentJsStream = jsStream;
      _ensureAudioContextUnlocked();

      if (_audioContext != null) {
        _remoteGainNode ??= _audioContext!.createGain();
        final isElemPlaying = _remoteAudioElement != null &&
            !_remoteAudioElement!.paused &&
            !_remoteAudioElement!.muted &&
            _remoteAudioElement!.volume > 0;
        _remoteGainNode!.gain.value = isElemPlaying ? 0.0 : 1.0;
        _remoteGainNode!.connect(_audioContext!.destination);

        _mediaStreamSourceNode?.disconnect();
        final source = _audioContext!.createMediaStreamSource(jsStream);
        source.connect(_remoteGainNode!);
        _mediaStreamSourceNode = source;
        debugPrint('[CallAudioManager][SUCCESS] Connected MediaStream to Web AudioContext (initial gain=${_remoteGainNode!.gain.value})');
      }
    } catch (e) {
      debugPrint('[CallAudioManager] Error connecting Web Audio graph: $e');
    }
  }

  static void _ensurePlayback(web.HTMLAudioElement elem) {
    elem.volume = 1.0;
    elem.muted = false;

    debugPrint('[CallAudioManager][DIAG] Audio element pre-play: srcObject=${elem.srcObject != null} | paused=${elem.paused} | muted=${elem.muted} | volume=${elem.volume}');

    try {
      elem.play().toDart.then((_) {
        _lastRemotePlayError = null;
        debugPrint('[CallAudioManager][DIAG] REMOTE AUDIO PLAYBACK STARTED SUCCESS (muted=${elem.muted}, volume=${elem.volume})');
        try {
          _remoteGainNode?.gain.value = 0.0;
        } catch (_) {}
      }).catchError((err) {
        _lastRemotePlayError = err.toString();
        debugPrint('[CallAudioManager][DIAG] HTMLAudioElement play() deferred by Autoplay Policy: $err');
        _ensureAudioContextUnlocked();
        try {
          _remoteGainNode?.gain.value = 1.0;
        } catch (_) {}
        return null;
      });
    } catch (pe) {
      _lastRemotePlayError = pe.toString();
      debugPrint('[CallAudioManager] play() invoke catch: $pe');
      try {
        _remoteGainNode?.gain.value = 1.0;
      } catch (_) {}
    }
  }

  /// Binds incoming remote MediaStream to both the Web Audio graph and HTMLAudioElement
  static void attachRemoteAudio(MediaStream stream) {
    if (!kIsWeb) return;
    try {
      _ensureGlobalGestureListeners();
      _ensureAudioContextUnlocked();
      final elem = _ensureRemoteElement();

      try {
        final dynamic dynStream = stream;
        final jsMediaStream = dynStream.jsStream as web.MediaStream?;
        if (jsMediaStream != null) {
          // 1. Connect Web Audio fail-safe graph
          _connectWebAudioGraph(jsMediaStream);

          // 2. Assign to persistent HTMLAudioElement
          elem.srcObject = jsMediaStream;
          _ensurePlayback(elem);
          debugPrint('[CallAudioManager] Bound remote MediaStream to HTMLAudioElement');

          // 3. Log remote track states
          try {
            final audioTracks = jsMediaStream.getAudioTracks().toDart;
            debugPrint('[CallAudioManager][DIAG] Remote Audio Tracks count: ${audioTracks.length}');
            for (int i = 0; i < audioTracks.length; i++) {
              final tr = audioTracks[i];
              debugPrint('[CallAudioManager][DIAG] Track #$i: kind=${tr.kind} | readyState=${tr.readyState} | enabled=${tr.enabled} | id=${tr.id}');
            }
          } catch (te) {
            debugPrint('[CallAudioManager] Error logging tracks: $te');
          }

          // 4. Staggered retry triggers to handle late autoplay unlocks
          Future.delayed(const Duration(milliseconds: 200), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((e) {
                _lastRemotePlayError = e.toString();
                return null;
              });
            }
          });
          Future.delayed(const Duration(milliseconds: 600), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((e) {
                _lastRemotePlayError = e.toString();
                return null;
              });
            }
          });
          Future.delayed(const Duration(milliseconds: 1200), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((e) {
                _lastRemotePlayError = e.toString();
                return null;
              });
            }
          });

          setSpeakerphoneOn(_currentSpeakerState);
        }
      } catch (e) {
        debugPrint('[CallAudioManager] Error accessing jsStream: $e');
      }
    } catch (e) {
      debugPrint('[CallAudioManager] Error attaching remote audio: $e');
    }
  }

  /// Binds standalone MediaStreamTrack to both Web Audio graph and HTMLAudioElement
  static void attachRemoteTrack(MediaStreamTrack track) {
    if (!kIsWeb) return;
    try {
      _ensureGlobalGestureListeners();
      _ensureAudioContextUnlocked();
      final elem = _ensureRemoteElement();

      final dynamic dynTrack = track;
      final jsTrack = dynTrack.jsTrack as web.MediaStreamTrack?;
      if (jsTrack != null) {
        final jsStream = web.MediaStream();
        jsStream.addTrack(jsTrack);

        _connectWebAudioGraph(jsStream);

        elem.srcObject = jsStream;
        _ensurePlayback(elem);
        debugPrint('[CallAudioManager] Bound remote track to HTMLAudioElement');
        setSpeakerphoneOn(_currentSpeakerState);
      }
    } catch (e) {
      debugPrint('[CallAudioManager] Error attaching remote track: $e');
    }
  }

  /// Cleanly stops remote conversation audio and detaches stream
  static void stopRemoteAudio() {
    if (!kIsWeb) return;
    try {
      _mediaStreamSourceNode?.disconnect();
      _mediaStreamSourceNode = null;
      _remoteGainNode?.disconnect();
      _remoteGainNode = null;
      _currentJsStream = null;

      if (_remoteAudioElement != null) {
        _remoteAudioElement!.srcObject = null;
        _remoteAudioElement!.pause();
        debugPrint('[CallAudioManager] Detached remote audio and paused element');
      }
    } catch (_) {}
  }

  /// Complete cleanup at call end
  static void cleanup() {
    stopRingtone();
    stopRemoteAudio();
  }

  // ==========================================
  // PIPELINE 3: TEST SPEAKER FUNCTION
  // ==========================================

  /// Developer / User speaker test function
  static Future<bool> testSpeaker() async {
    debugPrint('[CallAudioManager][TEST_SPEAKER] Test speaker requested');
    try {
      initializeAudio();
      _ensureAudioContextUnlocked();

      final ctx = _audioContext;
      if (ctx == null) {
        _lastTestSpeakerResult = 'FAILED: AudioContext unavailable';
        return false;
      }

      final now = ctx.currentTime + 0.05;
      final testChimes = [
        {'freq': 523.25, 'st': 0.0, 'dur': 0.12}, // C5
        {'freq': 659.25, 'st': 0.12, 'dur': 0.12}, // E5
        {'freq': 783.99, 'st': 0.24, 'dur': 0.12}, // G5
        {'freq': 1046.50, 'st': 0.36, 'dur': 0.25}, // C6
      ];

      for (final tc in testChimes) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        final st = now + (tc['st'] as double);
        final dur = tc['dur'] as double;

        osc.type = 'triangle';
        osc.frequency.setValueAtTime(tc['freq'] as double, st);

        gain.gain.setValueAtTime(0.0, st);
        gain.gain.linearRampToValueAtTime(0.85, st + 0.02);
        gain.gain.linearRampToValueAtTime(0.0, st + dur);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(st);
        osc.stop(st + dur);
      }

      _lastTestSpeakerResult = 'PASSED (ctx state=${ctx.state})';
      debugPrint('[CallAudioManager][TEST_SPEAKER] SUCCESS: Test sound dispatched');
      return true;
    } catch (e) {
      _lastTestSpeakerResult = 'FAILED: $e';
      debugPrint('[CallAudioManager][TEST_SPEAKER] ERROR: $e');
      return false;
    }
  }

  // ==========================================
  // PIPELINE 4: DEVICE ENUMERATION & ROUTING
  // ==========================================

  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    if (!kIsWeb) return [];
    final List<Map<String, String>> result = [];
    try {
      final nav = web.window.navigator;
      final devices = await nav.mediaDevices.enumerateDevices().toDart;
      final dynamic dynDevices = devices;
      final int len = dynDevices.length as int;
      for (int i = 0; i < len; i++) {
        final dynamic d = dynDevices[i];
        if (d.kind == 'audioinput') {
          final label = (d.label as String? ?? '').isNotEmpty
              ? (d.label as String)
              : 'Microphone ${result.length + 1}';
          result.add({
            'deviceId': d.deviceId as String? ?? '',
            'label': label,
          });
        }
      }
    } catch (e) {
      debugPrint('[CallAudioManager] getAudioInputDevices error: $e');
    }
    return result;
  }

  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    if (!kIsWeb) return [];
    final List<Map<String, String>> result = [];
    try {
      final nav = web.window.navigator;
      final devices = await nav.mediaDevices.enumerateDevices().toDart;
      final dynamic dynDevices = devices;
      final int len = dynDevices.length as int;
      for (int i = 0; i < len; i++) {
        final dynamic d = dynDevices[i];
        if (d.kind == 'audiooutput') {
          final label = (d.label as String? ?? '').isNotEmpty
              ? (d.label as String)
              : 'Speaker / Output ${result.length + 1}';
          result.add({
            'deviceId': d.deviceId as String? ?? '',
            'label': label,
          });
        }
      }
    } catch (e) {
      debugPrint('[CallAudioManager] getAudioOutputDevices error: $e');
    }
    return result;
  }

  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    if (!kIsWeb) return false;
    try {
      _selectedOutputDeviceId = deviceId;
      final elem = _remoteAudioElement;
      if (elem == null) return false;
      final dynamic dynElem = elem;
      if (dynElem.setSinkId != null) {
        await dynElem.setSinkId(deviceId.toJS);
        _activeSinkLabel = label ?? (deviceId.isEmpty ? 'Default System Output' : deviceId);
        debugPrint('[CallAudioManager] setAudioOutputDevice SUCCESS: sinkId="$deviceId" label="$_activeSinkLabel"');
        return true;
      }
    } catch (e) {
      debugPrint('[CallAudioManager] setAudioOutputDevice ERROR: $e');
    }
    return false;
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    if (!kIsWeb) return;
    _currentSpeakerState = isSpeaker;

    Future<void> applySink() async {
      try {
        final elem = _remoteAudioElement;
        if (elem == null) return;
        final nav = web.window.navigator;
        final devices = await nav.mediaDevices.enumerateDevices().toDart;
        final dynamic dynDevices = devices;
        final int len = dynDevices.length as int;
        String? targetDeviceId;
        String? targetLabel;

        for (int i = 0; i < len; i++) {
          final dynamic d = dynDevices[i];
          if (d.kind == 'audiooutput') {
            final label = (d.label as String? ?? '').toLowerCase();
            final deviceId = d.deviceId as String? ?? '';
            if (!isSpeaker) {
              if (label.contains('headphone') ||
                  label.contains('headset') ||
                  label.contains('earphone') ||
                  label.contains('earpiece') ||
                  label.contains('receiver')) {
                targetDeviceId = deviceId;
                targetLabel = d.label as String?;
                break;
              }
            } else {
              if (label.contains('speaker') ||
                  label.contains('loudspeaker') ||
                  label.contains('main') ||
                  label.contains('external')) {
                targetDeviceId = deviceId;
                targetLabel = d.label as String?;
                break;
              }
            }
          }
        }

        final dynamic dynElem = elem;
        if (dynElem.setSinkId != null) {
          final String sink = targetDeviceId ?? (_selectedOutputDeviceId.isNotEmpty ? _selectedOutputDeviceId : '');
          try {
            await dynElem.setSinkId(sink.toJS);
            _activeSinkLabel = targetLabel ?? (isSpeaker ? 'Loudspeaker' : 'Headphones / Output');
            debugPrint('[CallAudioManager] Applied audio sink: "$sink" (label: "$_activeSinkLabel")');
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[CallAudioManager] setSpeakerphoneOn error: $e');
      }
    }

    await applySink();
    Future.delayed(const Duration(milliseconds: 300), applySink);
  }

  // ==========================================
  // PIPELINE 5: COMPLETE REAL-TIME DIAGNOSTICS
  // ==========================================

  static Map<String, dynamic> getDiagnostics() {
    final remoteElem = _remoteAudioElement;
    final ctxState = _audioContext?.state ?? 'not created';
    final hasSource = _mediaStreamSourceNode != null;

    final remoteExists = remoteElem != null;
    final hasSrcObject = (remoteElem?.srcObject != null) || hasSource;
    final isPlaying = (remoteElem != null && !remoteElem.paused && !remoteElem.muted && remoteElem.volume > 0) ||
        (hasSource && ctxState == 'running');
    final isPaused = remoteElem != null ? remoteElem.paused : !hasSource;
    final isMuted = remoteElem?.muted ?? false;
    final volume = remoteElem?.volume ?? 1.0;
    final readyState = remoteElem?.readyState ?? (hasSource ? 4 : 0);

    return {
      'isPlaying': isPlaying,
      'ringtoneState': _ringtoneState,
      'lastRingtoneError': _lastRingtoneError,
      'remoteAudioElementExists': remoteExists,
      'hasSrcObject': hasSrcObject,
      'remoteStreamActive': hasSrcObject && (ctxState == 'running' || !isPaused),
      'remoteAudioPaused': isPaused,
      'remoteAudioMuted': isMuted,
      'remoteAudioVolume': volume,
      'remoteAudioReadyState': readyState,
      'lastRemotePlayError': _lastRemotePlayError,
      'audioContextState': ctxState,
      'isAudioUnlocked': ctxState == 'running',
      'activeSink': _activeSinkLabel ?? 'Default Output',
      'lastTestSpeakerResult': _lastTestSpeakerResult,
    };
  }
}
