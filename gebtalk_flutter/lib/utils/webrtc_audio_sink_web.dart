import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

class WebRtcAudioSinkImpl {
  static web.HTMLAudioElement? _remoteAudioElement;
  static web.AudioContext? _sinkAudioContext;
  static web.MediaStreamAudioSourceNode? _mediaSourceNode;
  static web.GainNode? _gainNode;

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
      web.document.body?.append(_remoteAudioElement!);
    }
    return _remoteAudioElement!;
  }

  static bool _currentSpeakerState = false;
  static bool _retryListenerAdded = false;

  static void _ensurePlayback(web.HTMLAudioElement elem) {
    elem.volume = 1.0;
    elem.muted = false;
    try {
      elem.play().toDart.catchError((err) {
        debugPrint('[WebRtcAudioSink] Audio play blocked by policy, queuing gesture listener: $err');
        if (!_retryListenerAdded) {
          _retryListenerAdded = true;
          void onGesture(web.Event e) {
            try {
              elem.volume = 1.0;
              elem.muted = false;
              elem.play().toDart.catchError((_) => null);
              if (_sinkAudioContext != null && _sinkAudioContext!.state == 'suspended') {
                _sinkAudioContext!.resume();
              }
            } catch (_) {}
          }
          web.window.addEventListener('click', onGesture.toJS);
          web.window.addEventListener('touchstart', onGesture.toJS);
          web.window.addEventListener('pointerdown', onGesture.toJS);
        }
        return null;
      });
    } catch (pe) {
      debugPrint('[WebRtcAudioSink] play invoke catch: $pe');
    }
  }

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
          debugPrint('[WebRtcAudioSink] Bound remote stream to HTMLAudioElement');
          
          // Connect to Web Audio API graph for zero-latency direct speaker pipeline
          try {
            if (_sinkAudioContext == null || _sinkAudioContext!.state == 'closed') {
              _sinkAudioContext = web.AudioContext();
            }
            if (_sinkAudioContext!.state == 'suspended') {
              _sinkAudioContext!.resume();
            }
            try {
              _mediaSourceNode?.disconnect();
            } catch (_) {}
            final dynamic dynAudioCtx = _sinkAudioContext;
            _mediaSourceNode = dynAudioCtx.createMediaStreamSource(jsMediaStream) as web.MediaStreamAudioSourceNode?;
            _gainNode = _sinkAudioContext!.createGain();
            _gainNode!.gain.value = 1.0;
            _mediaSourceNode?.connect(_gainNode!);
            _gainNode?.connect(_sinkAudioContext!.destination);
            debugPrint('[WebRtcAudioSink] Connected Web Audio stream source node');
          } catch (we) {
            debugPrint('[WebRtcAudioSink] Web Audio graph node note: $we');
          }

          setSpeakerphoneOn(_currentSpeakerState);
        }
      } catch (e) {
        debugPrint('[WebRtcAudioSink] Error accessing jsStream: $e');
      }
    } catch (e) {
      debugPrint('[WebRtcAudioSink] Error attaching HTMLAudioElement: $e');
    }
  }

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

  static void detachRemoteAudio() {
    if (!kIsWeb) return;
    try {
      if (_remoteAudioElement != null) {
        _remoteAudioElement!.srcObject = null;
        _remoteAudioElement!.pause();
      }
      try {
        _mediaSourceNode?.disconnect();
        _mediaSourceNode = null;
        _gainNode?.disconnect();
        _gainNode = null;
      } catch (_) {}
    } catch (_) {}
  }

  static void unlockAudio() {
    if (!kIsWeb) return;
    try {
      final elem = _ensureElement();
      elem.muted = false;
      elem.volume = 1.0;
      elem.play().toDart.catchError((_) => null);
      if (_sinkAudioContext != null && _sinkAudioContext!.state == 'suspended') {
        _sinkAudioContext!.resume();
      }
    } catch (_) {}
  }

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
        
        for (int i = 0; i < len; i++) {
          final dynamic d = dynDevices[i];
          if (d.kind == 'audiooutput') {
            final label = (d.label as String? ?? '').toLowerCase();
            final deviceId = d.deviceId as String? ?? '';
            if (!isSpeaker) {
              // Earpiece / Top Speaker / Receiver / Communications target
              if (label.contains('earpiece') ||
                  label.contains('receiver') ||
                  label.contains('internal') ||
                  label.contains('phone') ||
                  label.contains('headset') ||
                  label.contains('earphone') ||
                  label.contains('communications') ||
                  deviceId == 'communications') {
                targetDeviceId = deviceId;
                break;
              }
            } else {
              // Loudspeaker / Bottom Speaker target
              if (label.contains('speaker') ||
                  label.contains('loudspeaker') ||
                  label.contains('main') ||
                  label.contains('external')) {
                targetDeviceId = deviceId;
                break;
              }
            }
          }
        }
        
        if (!isSpeaker) {
          // Earpiece target
          final dynamic dynElem = elem;
          if (dynElem.setSinkId != null) {
            try {
              final sink = targetDeviceId ?? '';
              await dynElem.setSinkId(sink.toJS);
              debugPrint('[WebRtcAudioSink] Applied earpiece sink: "$sink"');
            } catch (e) {
              debugPrint('[WebRtcAudioSink] setSinkId earpiece error: $e');
            }
          }
        } else {
          // Loudspeaker target
          final dynamic dynElem = elem;
          if (dynElem.setSinkId != null) {
            try {
              final sink = targetDeviceId ?? 'default';
              await dynElem.setSinkId(sink.toJS);
              debugPrint('[WebRtcAudioSink] Applied speakerphone sink: "$sink"');
            } catch (e) {
              debugPrint('[WebRtcAudioSink] setSinkId speaker error: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[WebRtcAudioSink] Error switching speakerphone: $e');
      }
    }

    // Apply immediately and retry after permissions settle
    await applySink();
    Future.delayed(const Duration(milliseconds: 350), applySink);
    Future.delayed(const Duration(milliseconds: 900), applySink);
  }
}
