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
}
