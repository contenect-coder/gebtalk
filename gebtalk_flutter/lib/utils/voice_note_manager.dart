import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/api_service.dart';
import '../theme/colors.dart';

/// Centralized manager for recording voice notes across Mobile & Web
class VoiceNoteManager {
  static final AudioRecorder _recorder = AudioRecorder();

  static Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('[VoiceNoteManager] Permission check error: $e');
      return false;
    }
  }

  static Future<bool> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        final perm = await _recorder.hasPermission();
        if (!perm) return false;
      }
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );
      await _recorder.start(config, path: '');
      return true;
    } catch (e) {
      debugPrint('[VoiceNoteManager] Start recording error: $e');
      return false;
    }
  }

  static Future<VoiceRecordResult?> stopRecording(int durationSeconds) async {
    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) return null;

      Uint8List? bytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        final file = io.File(path);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
          // Clean up temp file asynchronously
          file.delete().ignore();
        }
      }

      if (bytes == null || bytes.isEmpty) return null;

      final mins = (durationSeconds ~/ 60).toString();
      final secs = (durationSeconds % 60).toString().padLeft(2, '0');
      final formattedDuration = '$mins:$secs';

      return VoiceRecordResult(
        bytes: bytes,
        duration: formattedDuration,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      debugPrint('[VoiceNoteManager] Stop recording error: $e');
      return null;
    }
  }

  static Future<void> cancelRecording() async {
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('[VoiceNoteManager] Cancel recording error: $e');
    }
  }

  static Future<bool> isRecording() async {
    try {
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }
}

class VoiceRecordResult {
  final Uint8List bytes;
  final String duration;
  final int durationSeconds;

  VoiceRecordResult({
    required this.bytes,
    required this.duration,
    required this.durationSeconds,
  });
}

/// Interactive WhatsApp-style voice note player with waveform and speed controls
class VoiceNotePlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String duration;
  final bool isUser;

  const VoiceNotePlayerWidget({
    super.key,
    required this.audioUrl,
    required this.duration,
    required this.isUser,
  });

  @override
  State<VoiceNotePlayerWidget> createState() => _VoiceNotePlayerWidgetState();
}

class _VoiceNotePlayerWidgetState extends State<VoiceNotePlayerWidget> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  double _speed = 1.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = (state == PlayerState.playing));
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        final resolvedUrl = ApiService.resolveUrl(widget.audioUrl);
        if (_position > Duration.zero && _position < _duration) {
          await _player.resume();
        } else {
          await _player.setPlaybackRate(_speed);
          await _player.play(UrlSource(resolvedUrl));
        }
      }
    } catch (e) {
      debugPrint('[VoiceNotePlayer] Error toggling playback: $e');
    }
  }

  void _cycleSpeed() async {
    setState(() {
      if (_speed == 1.0) {
        _speed = 1.5;
      } else if (_speed == 1.5) {
        _speed = 2.0;
      } else {
        _speed = 1.0;
      }
    });
    try {
      await _player.setPlaybackRate(_speed);
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString();
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    const waveHeights = [8.0, 14.0, 6.0, 20.0, 16.0, 10.0, 22.0, 18.0, 12.0, 15.0, 8.0, 18.0, 14.0, 10.0, 20.0, 6.0];
    final progress = (_duration.inMilliseconds > 0)
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final displayTime = _isPlaying
        ? _formatDuration(_position)
        : (_duration > Duration.zero ? _formatDuration(_duration) : widget.duration);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              color: widget.isUser ? Colors.white : AppColors.primary,
              size: 32,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _togglePlayPause,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  children: List.generate(waveHeights.length, (index) {
                    final waveFraction = index / waveHeights.length;
                    final isPlayed = waveFraction <= progress;
                    final activeColor = widget.isUser ? Colors.white : AppColors.primary;
                    final inactiveColor = widget.isUser ? Colors.white38 : AppColors.primary.withValues(alpha: 0.25);

                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.0),
                        height: waveHeights[index],
                        decoration: BoxDecoration(
                          color: isPlayed ? activeColor : inactiveColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayTime,
                      style: TextStyle(
                        color: widget.isUser ? Colors.white70 : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    InkWell(
                      onTap: _cycleSpeed,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: widget.isUser ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_speed}x',
                          style: TextStyle(
                            color: widget.isUser ? Colors.white : AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
