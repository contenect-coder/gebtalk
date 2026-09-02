import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

/// Production WebRTC Audio Sink & Routing Implementation for Web/Browser
/// Manages remote MediaStream audio playback, device enumeration, output sinks (setSinkId),
/// autoplay policy unlocking, and real-time audio pipeline diagnostics.
class WebRtcAudioSinkImpl {
  static web.HTMLAudioElement? _remoteAudioElement;
  static String? _activeSinkLabel = 'Default System Output';
  static String _selectedOutputDeviceId = '';
  static bool _currentSpeakerState = false;
  static bool _retryListenerAdded = false;

  static Future<bool> checkAndRequestMicrophonePermission() async {
    return true; // Web browser prompts for permission during getUserMedia()
  }

  static web.HTMLAudioElement _ensureElement() {
    if (_remoteAudioElement == null) {
      _remoteAudioElement = web.HTMLAudioElement();
      _remoteAudioElement!.id = 'gebtalk_remote_audio_player';
      _remoteAudioElement!.autoplay = true;
      _remoteAudioElement!.setAttribute('playsinline', 'true');
      _remoteAudioElement!.setAttribute('webkit-playsinline', 'true');
      _remoteAudioElement!.style.position = 'fixed';
      _remoteAudioElement!.style.bottom = '0px';
      _remoteAudioElement!.style.right = '0px';
      _remoteAudioElement!.style.width = '1px';
      _remoteAudioElement!.style.height = '1px';
      _remoteAudioElement!.style.opacity = '0.01';
      _remoteAudioElement!.style.pointerEvents = 'none';
      _remoteAudioElement!.volume = 1.0;
      _remoteAudioElement!.muted = false;

      // Attach diagnostic lifecycle event listeners
      void onPlaying(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio PLAYING (volume=${_remoteAudioElement?.volume}, muted=${_remoteAudioElement?.muted})');
      }
      void onPause(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio PAUSED');
      }
      void onError(web.Event e) {
        debugPrint('[WebRtcAudioSink][EVENT] Remote audio ERROR: ${_remoteAudioElement?.error?.message ?? "unknown"}');
      }

      _remoteAudioElement!.addEventListener('playing', onPlaying.toJS);
      _remoteAudioElement!.addEventListener('pause', onPause.toJS);
      _remoteAudioElement!.addEventListener('error', onError.toJS);

      web.document.body?.append(_remoteAudioElement!);
      debugPrint('[WebRtcAudioSink] Created and attached HTMLAudioElement #gebtalk_remote_audio_player to DOM');
    }
    return _remoteAudioElement!;
  }

  static void _ensurePlayback(web.HTMLAudioElement elem) {
    elem.volume = 1.0;
    elem.muted = false;
    
    debugPrint('[WebRtcAudioSink][DIAG] Audio element pre-play: srcObject=${elem.srcObject != null} | paused=${elem.paused} | muted=${elem.muted} | volume=${elem.volume}');

    try {
      elem.play().toDart.then((_) {
        debugPrint('[WebRtcAudioSink][DIAG] REMOTE AUDIO PLAYBACK STARTED SUCCESS (muted=${elem.muted}, volume=${elem.volume})');
      }).catchError((err) {
        debugPrint('[WebRtcAudioSink][DIAG] REMOTE AUDIO PLAYBACK BLOCKED by Autoplay Policy: $err');
        if (!_retryListenerAdded) {
          _retryListenerAdded = true;
          void onGesture(web.Event e) {
            try {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.then((_) {
                debugPrint('[WebRtcAudioSink][DIAG] REMOTE AUDIO PLAYBACK STARTED ON USER GESTURE');
              }).catchError((_) => null);
            } catch (_) {}
          }
          web.window.addEventListener('click', onGesture.toJS);
          web.window.addEventListener('touchstart', onGesture.toJS);
          web.window.addEventListener('pointerdown', onGesture.toJS);
          web.window.addEventListener('keydown', onGesture.toJS);
        }
        return null;
      });
    } catch (pe) {
      debugPrint('[WebRtcAudioSink] play() invoke catch: $pe');
    }
  }

  /// Binds remote MediaStream to the HTMLAudioElement
  static void attachRemoteAudio(MediaStream stream) {
    if (!kIsWeb) return;
    try {
      final elem = _ensureElement();

      // Extract jsStream from flutter_webrtc MediaStreamWeb
      try {
        final dynamic dynStream = stream;
        final jsMediaStream = dynStream.jsStream;
        if (jsMediaStream != null) {
          elem.srcObject = jsMediaStream;
          _ensurePlayback(elem);
          debugPrint('[WebRtcAudioSink] Bound remote MediaStream to HTMLAudioElement');

          // Log tracks on the JS MediaStream
          try {
            final dynamic dynJsStream = jsMediaStream;
            final audioTracks = dynJsStream.getAudioTracks();
            final int trackCount = audioTracks.length as int;
            debugPrint('[WebRtcAudioSink][DIAG] Remote JS MediaStream Audio Tracks count: $trackCount');
            for (int i = 0; i < trackCount; i++) {
              final dynamic tr = audioTracks[i];
              debugPrint('[WebRtcAudioSink][DIAG] JS Track #$i: kind=${tr.kind} | readyState=${tr.readyState} | enabled=${tr.enabled} | id=${tr.id}');
            }
          } catch (te) {
            debugPrint('[WebRtcAudioSink] Error logging JS tracks: $te');
          }

          // Aggressive retries to guarantee playback initiation
          Future.delayed(const Duration(milliseconds: 250), () {
            try {
              if (elem.paused) {
                elem.volume = 1.0;
                elem.muted = false;
                elem.play().toDart.catchError((_) => null);
                debugPrint('[WebRtcAudioSink] Retried play() after 250ms');
              }
            } catch (_) {}
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            try {
              if (elem.paused) {
                elem.volume = 1.0;
                elem.muted = false;
                elem.play().toDart.catchError((_) => null);
                debugPrint('[WebRtcAudioSink] Retried play() after 800ms');
              }
            } catch (_) {}
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

  /// Binds standalone MediaStreamTrack to HTMLAudioElement
  static void attachRemoteTrack(MediaStreamTrack track) {
    if (!kIsWeb) return;
    try {
      final elem = _ensureElement();
      final dynamic dynTrack = track;
      final jsTrack = dynTrack.jsTrack;
      if (jsTrack != null) {
        final jsStream = web.MediaStream();
        jsStream.addTrack(jsTrack);
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
      if (_remoteAudioElement != null) {
        _remoteAudioElement!.srcObject = null;
        _remoteAudioElement!.pause();
        debugPrint('[WebRtcAudioSink] Detached remote audio and paused element');
      }
    } catch (_) {}
  }

  /// Unlocks audio on user gesture
  static void unlockAudio() {
    if (!kIsWeb) return;
    try {
      final elem = _ensureElement();
      elem.muted = false;
      elem.volume = 1.0;
      elem.play().toDart.catchError((_) => null);
    } catch (_) {}
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
      } else {
        debugPrint('[WebRtcAudioSink][DIAG] HTMLMediaElement.setSinkId not supported on this browser');
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
              // Priority 1: Wired/Bluetooth Headset, Headphones, Earpiece, Receiver
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
              // Priority 2: Speaker, Loudspeaker, Main, External
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
          // If a specific device matching headphones or speaker was found, route to it.
          // Otherwise, route to default output ('') so desktop headphones receive sound naturally.
          final String sink = targetDeviceId ?? (_selectedOutputDeviceId.isNotEmpty ? _selectedOutputDeviceId : '');
          await dynElem.setSinkId(sink.toJS);
          _activeSinkLabel = targetLabel ?? (isSpeaker ? 'Loudspeaker' : 'Earpiece / Headphones');
          debugPrint('[WebRtcAudioSink] Applied audio sink: "$sink" (label: "$_activeSinkLabel")');
        }
      } catch (e) {
        debugPrint('[WebRtcAudioSink] setSpeakerphoneOn error: $e');
      }
    }

    await applySink();
    Future.delayed(const Duration(milliseconds: 300), applySink);
  }

  /// Returns diagnostic state of the audio element
  static Map<String, dynamic> getAudioDiagnostics() {
    final elem = _remoteAudioElement;
    if (elem == null) {
      return {
        'elementConnected': false,
        'isPlaying': false,
        'isPaused': true,
        'isMuted': false,
        'volume': 0.0,
        'hasSrcObject': false,
        'activeSink': _activeSinkLabel ?? 'Default Output',
      };
    }
    return {
      'elementConnected': elem.srcObject != null,
      'isPlaying': !elem.paused && !elem.muted && elem.volume > 0,
      'isPaused': elem.paused,
      'isMuted': elem.muted,
      'volume': elem.volume,
      'hasSrcObject': elem.srcObject != null,
      'activeSink': _activeSinkLabel ?? 'Default Output',
    };
  }
}
