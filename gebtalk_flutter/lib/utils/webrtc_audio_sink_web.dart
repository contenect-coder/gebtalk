import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

class WebRtcAudioSinkImpl {
  static web.HTMLAudioElement? _remoteAudioElement;

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
          elem.volume = 1.0;
          elem.muted = false;
          try {
            elem.play().toDart.catchError((err) {
              debugPrint('[WebRtcAudioSink] Audio play catch: $err');
              return null;
            });
          } catch (pe) {
            debugPrint('[WebRtcAudioSink] play invoke catch: $pe');
          }
          debugPrint('[WebRtcAudioSink] Bound remote stream to HTMLAudioElement');
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
        elem.volume = 1.0;
        elem.muted = false;
        try {
          elem.play().toDart.catchError((err) {
            debugPrint('[WebRtcAudioSink] Track play catch: $err');
            return null;
          });
        } catch (pe) {
          debugPrint('[WebRtcAudioSink] Track play invoke catch: $pe');
        }
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
    } catch (_) {}
  }

  static Future<void> setSpeakerphoneOn(bool isSpeaker) async {
    if (!kIsWeb) return;
    _currentSpeakerState = isSpeaker;
    
    Future<void> applySink() async {
      try {
        final elem = _ensureElement();
        final nav = web.window.navigator;
        if (nav.mediaDevices != null) {
          final devices = await nav.mediaDevices.enumerateDevices().toDart;
          final len = devices.length;
          String? targetDeviceId;
          
          for (int i = 0; i < len; i++) {
            final d = devices[i];
            if (d.kind == 'audiooutput') {
              final label = d.label.toLowerCase();
              final deviceId = d.deviceId;
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
          
          final finalId = targetDeviceId ?? (isSpeaker ? 'default' : '');
          
          try {
            final dynamic dynElem = elem;
            if (dynElem.setSinkId != null) {
              await dynElem.setSinkId(finalId.toJS);
              debugPrint('[WebRtcAudioSink] Applied audio sink: "$finalId" (speaker=$isSpeaker)');
            }
          } catch (sinkErr) {
            debugPrint('[WebRtcAudioSink] setSinkId notice: $sinkErr');
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
