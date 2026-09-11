import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

/// Production WebRTC Audio Sink & Routing Implementation for Web/Browser
/// Features:
/// 1. Primary Output: Web Audio API (AudioContext + MediaStreamAudioSourceNode) which bypasses
///    mobile browser HTML5 autoplay restrictions and guarantees full-volume speaker playback.
/// 2. Secondary Output: HTMLAudioElement with persistent user-gesture unlocking and auto-retry.
/// 3. Device enumeration and output sink management.
/// 4. Real-time audio pipeline diagnostics.
class WebRtcAudioSinkImpl {
  static web.HTMLAudioElement? _remoteAudioElement;
  static web.AudioContext? _audioContext;
  static web.GainNode? _gainNode;
  static web.MediaStreamAudioSourceNode? _mediaStreamSourceNode;
  static String? _activeSinkLabel = 'Default System Output';
  static String _selectedOutputDeviceId = '';
  static bool _currentSpeakerState = true;
  static bool _globalListenersAttached = false;
  static web.MediaStream? _currentJsStream;

  static Future<bool> checkAndRequestMicrophonePermission() async {
    return true; // Web browser prompts for permission during getUserMedia()
  }

  /// Initializes the Web AudioContext and unlocks audio hardware on user interaction
  static void _ensureAudioContextUnlocked() {
    try {
      _audioContext ??= web.AudioContext();
      if (_audioContext!.state == 'suspended') {
        _audioContext!.resume().toDart.then((_) {
          debugPrint('[WebRtcAudioSink] AudioContext resumed successfully (state=${_audioContext?.state})');
        }).catchError((err) {
          debugPrint('[WebRtcAudioSink] AudioContext resume error: $err');
        });
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] AudioContext initialization error: $e');
    }
  }

  /// Ensures global user-gesture listeners are registered on the window
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
      debugPrint('[WebRtcAudioSink] Attached global user-gesture audio unlock listeners');
    } catch (e) {
      debugPrint('[WebRtcAudioSink] Error attaching gesture listeners: $e');
    }
  }

  static web.HTMLAudioElement _ensureElement() {
    if (_remoteAudioElement == null) {
      _remoteAudioElement = web.HTMLAudioElement();
      _remoteAudioElement!.id = 'gebtalk_remote_audio_player';
      _remoteAudioElement!.autoplay = true;
      _remoteAudioElement!.setAttribute('playsinline', 'true');
      _remoteAudioElement!.setAttribute('webkit-playsinline', 'true');
      // Visible non-zero layout prevents mobile Chrome background media suspension
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

      // Attach diagnostic lifecycle event listeners
      void onPlaying(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio PLAYING (volume=${_remoteAudioElement?.volume}, muted=${_remoteAudioElement?.muted})');
        // HTMLAudioElement is successfully outputting audio! Mute Web Audio fallback to avoid echo
        try {
          _gainNode?.gain.value = 0.0;
        } catch (_) {}
      }
      void onPause(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio PAUSED');
        // If element is paused, enable Web Audio fallback
        try {
          _gainNode?.gain.value = 1.0;
        } catch (_) {}
      }
      void onError(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio ERROR: ${_remoteAudioElement?.error?.message ?? "unknown"}');
        try {
          _gainNode?.gain.value = 1.0;
        } catch (_) {}
      }

      _remoteAudioElement!.addEventListener('playing', onPlaying.toJS);
      _remoteAudioElement!.addEventListener('pause', onPause.toJS);
      _remoteAudioElement!.addEventListener('error', onError.toJS);

      web.document.body?.append(_remoteAudioElement!);
      debugPrint('[WebRtcAudioSink] Created and attached HTMLAudioElement #gebtalk_remote_audio_player to DOM');
    }
    _ensureGlobalGestureListeners();
    return _remoteAudioElement!;
  }

  static void _ensurePlayback(web.HTMLAudioElement elem) {
    elem.volume = 1.0;
    elem.muted = false;

    debugPrint('[WebRtcAudioSink][DIAG] Audio element pre-play: srcObject=${elem.srcObject != null} | paused=${elem.paused} | muted=${elem.muted} | volume=${elem.volume}');

    try {
      elem.play().toDart.then((_) {
        debugPrint('[WebRtcAudioSink][DIAG] REMOTE AUDIO PLAYBACK STARTED SUCCESS (muted=${elem.muted}, volume=${elem.volume})');
        try {
          _gainNode?.gain.value = 0.0;
        } catch (_) {}
      }).catchError((err) {
        debugPrint('[WebRtcAudioSink][DIAG] HTMLAudioElement play() deferred by Autoplay Policy: $err');
        _ensureAudioContextUnlocked();
        try {
          _gainNode?.gain.value = 1.0;
        } catch (_) {}
        return null;
      });
    } catch (pe) {
      debugPrint('[WebRtcAudioSink] play() invoke catch: $pe');
      try {
        _gainNode?.gain.value = 1.0;
      } catch (_) {}
    }
  }

  /// Connects MediaStream to Web Audio API destination for guaranteed mobile playback
  static void _connectWebAudioGraph(web.MediaStream jsStream) {
    try {
      _currentJsStream = jsStream;
      _ensureAudioContextUnlocked();

      if (_audioContext != null) {
        _gainNode ??= _audioContext!.createGain();
        final isElemPlaying = _remoteAudioElement != null && !_remoteAudioElement!.paused && !_remoteAudioElement!.muted && _remoteAudioElement!.volume > 0;
        _gainNode!.gain.value = isElemPlaying ? 0.0 : 1.0;
        _gainNode!.connect(_audioContext!.destination);

        _mediaStreamSourceNode?.disconnect();
        final source = _audioContext!.createMediaStreamSource(jsStream);
        source.connect(_gainNode!);
        _mediaStreamSourceNode = source;
        debugPrint('[WebRtcAudioSink][SUCCESS] Connected MediaStream to Web AudioContext (initial gain=${_gainNode!.gain.value})');
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] Error connecting Web Audio graph: $e');
    }
  }

  /// Binds remote MediaStream to both the Web Audio graph and HTMLAudioElement
  static void attachRemoteAudio(MediaStream stream) {
    if (!kIsWeb) return;
    try {
      _ensureGlobalGestureListeners();
      _ensureAudioContextUnlocked();
      final elem = _ensureElement();

      // Extract jsStream from flutter_webrtc MediaStreamWeb
      try {
        final dynamic dynStream = stream;
        final jsMediaStream = dynStream.jsStream as web.MediaStream?;
        if (jsMediaStream != null) {
          // 1. Web Audio API route (bypasses HTML5 autoplay restrictions on mobile browsers)
          _connectWebAudioGraph(jsMediaStream);

          // 2. HTMLAudioElement secondary route
          elem.srcObject = jsMediaStream;
          _ensurePlayback(elem);
          debugPrint('[WebRtcAudioSink] Bound remote MediaStream to HTMLAudioElement');

          // Log audio tracks
          try {
            final audioTracks = jsMediaStream.getAudioTracks().toDart;
            debugPrint('[WebRtcAudioSink][DIAG] Remote JS Audio Tracks count: ${audioTracks.length}');
            for (int i = 0; i < audioTracks.length; i++) {
              final tr = audioTracks[i];
              debugPrint('[WebRtcAudioSink][DIAG] JS Track #$i: kind=${tr.kind} | readyState=${tr.readyState} | enabled=${tr.enabled} | id=${tr.id}');
            }
          } catch (te) {
            debugPrint('[WebRtcAudioSink] Error logging JS tracks: $te');
          }

          // Aggressive playback triggers on timers
          Future.delayed(const Duration(milliseconds: 150), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((_) => null);
            }
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((_) => null);
            }
          });
          Future.delayed(const Duration(milliseconds: 1200), () {
            _ensureAudioContextUnlocked();
            if (elem.paused) {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((_) => null);
            }
          });

          setSpeakerphoneOn(_currentSpeakerState);
        }
      } catch (e) {
        debugPrint('[WebRtcAudioSink] Error accessing jsStream: $e');
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] Error attaching HTMLAudioElement: $e');
    }
  }

  /// Binds standalone MediaStreamTrack to both Web Audio graph and HTMLAudioElement
  static void attachRemoteTrack(MediaStreamTrack track) {
    if (!kIsWeb) return;
    try {
      _ensureGlobalGestureListeners();
      _ensureAudioContextUnlocked();
      final elem = _ensureElement();

      final dynamic dynTrack = track;
      final jsTrack = dynTrack.jsTrack as web.MediaStreamTrack?;
      if (jsTrack != null) {
        final jsStream = web.MediaStream();
        jsStream.addTrack(jsTrack);

        _connectWebAudioGraph(jsStream);

        elem.srcObject = jsStream;
        _ensurePlayback(elem);
        debugPrint('[WebRtcAudioSink] Bound remote track to HTMLAudioElement');
        setSpeakerphoneOn(_currentSpeakerState);
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] Error attaching remote track: $e');
    }
  }

  /// Cleanly detaches stream and resets playback
  static void detachRemoteAudio() {
    if (!kIsWeb) return;
    try {
      _mediaStreamSourceNode?.disconnect();
      _mediaStreamSourceNode = null;
      _gainNode?.disconnect();
      _gainNode = null;
      _currentJsStream = null;

      if (_remoteAudioElement != null) {
        _remoteAudioElement!.srcObject = null;
        _remoteAudioElement!.pause();
        debugPrint('[WebRtcAudioSink] Detached remote audio and paused element');
      }
    } catch (_) {}
  }

  /// Unlocks audio hardware and resumes both AudioContext and HTMLAudioElement on user gesture
  static void unlockAudio() {
    if (!kIsWeb) return;
    try {
      _ensureAudioContextUnlocked();

      if (_currentJsStream != null && _mediaStreamSourceNode == null) {
        _connectWebAudioGraph(_currentJsStream!);
      }

      final elem = _ensureElement();
      elem.muted = false;
      elem.volume = 1.0;
      if (elem.srcObject != null && elem.paused) {
        elem.play().toDart.then((_) {
          debugPrint('[WebRtcAudioSink] unlockAudio: element playing');
        }).catchError((_) => null);
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] unlockAudio error: $e');
    }
  }

  /// Enumerates available microphone input devices
  static Future<List<Map<String, String>>> getAudioInputDevices() async {
    final list = <Map<String, String>>[];
    if (!kIsWeb) return list;
    try {
      final nav = web.window.navigator;
      final devices = await nav.mediaDevices.enumerateDevices().toDart;
      final dynamic dynDevices = devices;
      final int len = dynDevices.length as int;
      for (int i = 0; i < len; i++) {
        final dynamic d = dynDevices[i];
        if (d.kind == 'audioinput') {
          final label = (d.label as String? ?? '').trim();
          list.add({
            'deviceId': d.deviceId as String? ?? '',
            'label': label.isNotEmpty ? label : 'Microphone ${list.length + 1}',
            'groupId': d.groupId as String? ?? '',
          });
        }
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] getAudioInputDevices error: $e');
    }
    return list;
  }

  /// Enumerates available speaker / headphone output devices
  static Future<List<Map<String, String>>> getAudioOutputDevices() async {
    final list = <Map<String, String>>[];
    if (!kIsWeb) return list;
    try {
      final nav = web.window.navigator;
      final devices = await nav.mediaDevices.enumerateDevices().toDart;
      final dynamic dynDevices = devices;
      final int len = dynDevices.length as int;
      for (int i = 0; i < len; i++) {
        final dynamic d = dynDevices[i];
        if (d.kind == 'audiooutput') {
          final label = (d.label as String? ?? '').trim();
          list.add({
            'deviceId': d.deviceId as String? ?? '',
            'label': label.isNotEmpty ? label : 'Audio Output ${list.length + 1}',
            'groupId': d.groupId as String? ?? '',
          });
        }
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] getAudioOutputDevices error: $e');
    }
    return list;
  }

  /// Explicitly selects an audio output device via setSinkId()
  static Future<bool> setAudioOutputDevice(String deviceId, {String? label}) async {
    if (!kIsWeb) return false;
    _selectedOutputDeviceId = deviceId;
    if (label != null && label.isNotEmpty) {
      _activeSinkLabel = label;
    }
    try {
      final elem = _ensureElement();
      final dynamic dynElem = elem;
      if (dynElem.setSinkId != null) {
        await dynElem.setSinkId(deviceId.toJS);
        _activeSinkLabel = label ?? (deviceId.isEmpty ? 'Default System Output' : deviceId);
        debugPrint('[WebRtcAudioSink][DIAG] setAudioOutputDevice SUCCESS: sinkId="$deviceId" label="$_activeSinkLabel"');
        return true;
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink][DIAG] setAudioOutputDevice ERROR: $e');
    }
    return false;
  }

  /// Switches between Earpiece/Headphones (false) and Speakerphone/Loudspeaker (true)
  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    if (!kIsWeb) return;
    _currentSpeakerState = isSpeaker;

    Future<void> applySink() async {
      try {
        final elem = _ensureElement();
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
                  label.contains('receiver') ||
                  label.contains('communications')) {
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
            debugPrint('[WebRtcAudioSink] Applied audio sink: "$sink" (label: "$_activeSinkLabel")');
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[WebRtcAudioSink] setSpeakerphoneOn error: $e');
      }
    }

    await applySink();
    Future.delayed(const Duration(milliseconds: 300), applySink);
  }

  /// Returns diagnostic state of the audio element & Web Audio graph
  static Map<String, dynamic> getAudioDiagnostics() {
    final elem = _remoteAudioElement;
    final ctxState = _audioContext?.state ?? 'not created';
    final hasSource = _mediaStreamSourceNode != null;

    if (elem == null) {
      return {
        'elementConnected': false,
        'isPlaying': hasSource && ctxState == 'running',
        'isPaused': !hasSource,
        'isMuted': false,
        'volume': 1.0,
        'hasSrcObject': false,
        'activeSink': _activeSinkLabel ?? 'Default Output',
        'audioContextState': ctxState,
        'webAudioGraphLive': hasSource,
      };
    }
    return {
      'elementConnected': elem.srcObject != null || hasSource,
      'isPlaying': (!elem.paused && !elem.muted && elem.volume > 0) || (hasSource && ctxState == 'running'),
      'isPaused': elem.paused && (!hasSource || ctxState != 'running'),
      'isMuted': elem.muted,
      'volume': elem.volume,
      'hasSrcObject': elem.srcObject != null || hasSource,
      'activeSink': _activeSinkLabel ?? 'Default Output',
      'audioContextState': ctxState,
      'webAudioGraphLive': hasSource,
    };
  }
}
