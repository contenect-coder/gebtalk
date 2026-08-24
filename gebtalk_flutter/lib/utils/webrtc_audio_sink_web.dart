import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

class WebRtcAudioSinkImpl {
  static web.HTMLAudioElement? _remoteAudioElement;

  static void attachRemoteAudio(MediaStream stream) {
    if (!kIsWeb) return;
    try {
      if (_remoteAudioElement == null) {
        _remoteAudioElement = web.HTMLAudioElement();
        _remoteAudioElement!.id = 'gebtalk_remote_audio_player';
        _remoteAudioElement!.autoplay = true;
        _remoteAudioElement!.setAttribute('playsinline', 'true');
        _remoteAudioElement!.setAttribute('webkit-playsinline', 'true');
        _remoteAudioElement!.style.display = 'none';
        web.document.body?.append(_remoteAudioElement!);
      }

      // Extract jsStream from flutter_webrtc MediaStreamWeb
      try {
        final dynamic dynStream = stream;
        final jsMediaStream = dynStream.jsStream;
        if (jsMediaStream != null) {
          _remoteAudioElement!.srcObject = jsMediaStream;
          try {
            _remoteAudioElement!.play().toDart.catchError((err) {
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
