import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../services/webrtc_service.dart';
import '../theme/colors.dart';
import '../utils/webrtc_audio_sink.dart';

class CallOverlay extends StatefulWidget {
  const CallOverlay({super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  bool _showDiagnostics = false;

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final webrtcService = Provider.of<WebRtcService>(context);

    if (webrtcService.callState == 'idle') {
      return const SizedBox.shrink();
    }

    final String peerName = webrtcService.currentPeerName ?? 'User';
    final String? peerAvatar = webrtcService.currentPeerAvatar;
    final String state = webrtcService.callState;
    final bool isCaller = webrtcService.isCaller;
    
    final bool isIncoming = (state == 'ringing' && !isCaller);
    final bool isOutgoing = (state == 'calling' || (state == 'ringing' && isCaller));
    final bool isConnecting = state == 'connecting';
    final bool isConnected = state == 'connected';
    final bool isReconnecting = state == 'reconnecting';
    final bool isTerminal = state == 'busy' || state == 'declined' || state == 'failed' || state == 'ended' || state == 'cancelled';

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            if (webrtcService.remoteStream != null)
              Positioned(
                bottom: 0,
                right: 0,
                child: Opacity(
                  opacity: 0.001,
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: RTCVideoView(
                      webrtcService.remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (kIsWeb) {
                        WebRtcAudioSink.unlockAudio();
                      }
                    },
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.82),
                      child: SafeArea(
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                    // Top Security Badge & Diagnostics Toggle
                    Padding(
                      padding: const EdgeInsets.only(top: 36.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _showDiagnostics = !_showDiagnostics),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isConnected ? AppColors.primary.withValues(alpha: 0.4) : AppColors.glassBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    color: isConnected ? AppColors.primary : AppColors.textMuted,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isConnected ? 'HD VOICE • E2E ENCRYPTED' : 'INTERNET VOICE CALL',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: isConnected ? AppColors.primary : AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _showDiagnostics ? Icons.keyboard_arrow_up : Icons.info_outline,
                                    color: _showDiagnostics ? AppColors.primary : AppColors.textMuted,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showDiagnostics)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 280),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.90),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('─── CALL AUDIO DIAGNOSTICS ───', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                          InkWell(
                                            onTap: () async {
                                              await webrtcService.refreshAudioDiagnostics();
                                            },
                                            child: const Icon(Icons.refresh, color: AppColors.primary, size: 14),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      _buildDiagRow('CALL STATE', state.toUpperCase()),
                                      _buildDiagRow('LOCAL AUDIO TRACK', webrtcService.localTrackState),
                                      _buildDiagRow('REMOTE AUDIO TRACK', webrtcService.hasRemoteAudioTrack ? 'FOUND' : 'NOT FOUND'),
                                      _buildDiagRow('REMOTE TRACK STATE', webrtcService.remoteTrackState),
                                      _buildDiagRow('AUDIO RECEIVERS', '${webrtcService.audioReceiversCount}'),
                                      _buildDiagRow('AUDIO INPUT DEVICE', webrtcService.currentAudioInputDevice),
                                      _buildDiagRow('AUDIO OUTPUT DEVICE', webrtcService.currentAudioOutputDevice),
                                      _buildDiagRow('MOBILE OUTPUT ROUTE', webrtcService.isSpeakerOn ? 'SPEAKER (BOTTOM)' : 'EARPIECE (TOP)'),
                                      _buildDiagRow('SPEAKERPHONE', webrtcService.isSpeakerOn ? 'ON' : 'OFF'),
                                      _buildDiagRow('MUTE', webrtcService.isMuted ? 'ON' : 'OFF'),
                                      _buildDiagRow('AUDIO SESSION', webrtcService.isAudioSessionActive ? 'ACTIVE (VOICE_COMM)' : 'INACTIVE'),
                                      _buildDiagRow('RINGTONE STATE', webrtcService.remoteAudioElementDiag['ringtoneState'] ?? (webrtcService.isRingtonePlaying ? 'PLAYING' : 'STOPPED')),
                                      if (webrtcService.remoteAudioElementDiag['lastRingtoneError'] != null)
                                        _buildDiagRow('RINGTONE ERROR', webrtcService.remoteAudioElementDiag['lastRingtoneError'].toString()),
                                      _buildDiagRow('REMOTE AUDIO ELEMENT', webrtcService.remoteAudioElementDiag['hasSrcObject'] == true ? 'CONNECTED (DOM)' : 'NOT CONNECTED'),
                                      _buildDiagRow('REMOTE AUDIO STATE', webrtcService.remoteAudioElementDiag['remoteStreamActive'] == true ? 'PLAYING (LIVE)' : (webrtcService.remoteAudioElementDiag['remoteAudioPaused'] == true ? 'PAUSED' : 'WAITING')),
                                      _buildDiagRow('AUDIO CONTEXT', webrtcService.remoteAudioElementDiag['audioContextState'] ?? 'UNKNOWN'),
                                      if (webrtcService.remoteAudioElementDiag['lastRemotePlayError'] != null)
                                        _buildDiagRow('PLAYBACK ERROR', webrtcService.remoteAudioElementDiag['lastRemotePlayError'].toString()),
                                      _buildDiagRow('SPEAKER TEST', webrtcService.remoteAudioElementDiag['lastTestSpeakerResult'] ?? 'NOT RUN'),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            icon: const Icon(Icons.volume_up, size: 14),
                                            label: const Text('TEST SPEAKER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            onPressed: () async {
                                              final ok = await webrtcService.testSpeaker();
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(ok ? '✓ Speaker test chime played successfully!' : '⚠ Speaker test failed. Tap screen to unlock audio.'),
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                          if (webrtcService.availableAudioOutputs.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.headphones, color: AppColors.primary, size: 14),
                                              label: const Text('OUTPUT', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                                              onPressed: () => _showAudioDeviceDialog(context, webrtcService),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (webrtcService.remoteAudioElementDiag['lastRemotePlayError'] != null || webrtcService.remoteAudioElementDiag['isAudioUnlocked'] == false)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: GestureDetector(
                                onTap: () {
                                  WebRtcAudioSink.unlockAudio();
                                  webrtcService.refreshAudioDiagnostics();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app, color: Colors.amber, size: 14),
                                      SizedBox(width: 6),
                                      Text(
                                        'Call Audio Blocked • Tap To Enable Sound',
                                        style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms),

                    // Middle Caller Info & Pulsing Avatar Section
                    Column(
                      children: [
                        // Pulsing Avatar Stack
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glowing pulse rings when calling or ringing
                            if (isOutgoing || isIncoming || isConnecting) ...[
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isIncoming
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : const Color(0xFF00E5FF).withValues(alpha: 0.2),
                                    width: 2,
                                  ),
                                ),
                              )
                                  .animate(onPlay: (controller) => controller.repeat())
                                  .scale(begin: const Offset(1, 1), end: const Offset(1.4, 1.4), duration: 2.seconds, curve: Curves.easeOut)
                                  .fadeOut(duration: 2.seconds),
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isIncoming
                                        ? AppColors.primary.withValues(alpha: 0.3)
                                        : const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                              )
                                  .animate(onPlay: (controller) => controller.repeat())
                                  .scale(begin: const Offset(1, 1), end: const Offset(1.25, 1.25), delay: 600.ms, duration: 2.seconds, curve: Curves.easeOut)
                                  .fadeOut(duration: 2.seconds),
                            ],

                            // Avatar Core
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isTerminal
                                    ? const LinearGradient(colors: [Color(0xFF7F1D1D), Color(0xFF991B1B)])
                                    : AppColors.primaryGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: isTerminal
                                        ? Colors.redAccent.withValues(alpha: 0.4)
                                        : AppColors.primary.withValues(alpha: 0.35),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: peerAvatar != null && peerAvatar.isNotEmpty && peerAvatar.startsWith('http')
                                    ? Image.network(
                                        peerAvatar,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildInitialAvatar(peerName),
                                      )
                                    : _buildInitialAvatar(peerName),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Peer Name
                        Text(
                          peerName,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 10),

                        // Status Badge / Live Duration
                        _buildStatusIndicator(webrtcService, state, isIncoming, isOutgoing, isConnected, isConnecting, isReconnecting, isTerminal),
                      ],
                    ),

                    // Bottom Controls Panel
                    Padding(
                      padding: const EdgeInsets.only(bottom: 48.0, left: 28.0, right: 28.0),
                      child: isIncoming
                          ? _buildIncomingControls(webrtcService)
                          : isOutgoing
                              ? _buildOutgoingControls(webrtcService)
                              : isConnected || isReconnecting || isConnecting
                                  ? _buildConnectedControls(webrtcService)
                                  : _buildTerminalStatus(webrtcService),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    ],
  ),
),
);
  }

  Widget _buildInitialAvatar(String name) {
    return Container(
      alignment: Alignment.center,
      color: Colors.transparent,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(
          fontSize: 50,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(
    WebRtcService svc,
    String state,
    bool isIncoming,
    bool isOutgoing,
    bool isConnected,
    bool isConnecting,
    bool isReconnecting,
    bool isTerminal,
  ) {
    if (isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2)),
            const SizedBox(width: 8),
            Text(
              _formatDuration(svc.callDurationSeconds),
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
    }

    if (isIncoming) {
      return const Text(
        'Incoming Internet Voice Call...',
        style: TextStyle(
          fontSize: 15,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeIn(duration: 800.ms);
    }

    if (isOutgoing) {
      return Text(
        svc.statusMessage ?? (state == 'calling' ? 'Calling...' : 'Ringing...'),
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF00E5FF),
          fontWeight: FontWeight.w600,
        ),
      ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeIn(duration: 800.ms);
    }

    if (isConnecting) {
      return const Text(
        'Connecting encrypted audio...',
        style: TextStyle(
          fontSize: 15,
          color: Color(0xFFFFD54F),
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (isReconnecting) {
      return const Text(
        'Reconnecting connection...',
        style: TextStyle(
          fontSize: 15,
          color: Color(0xFFFFB74D),
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // Terminal state text
    return Text(
      svc.statusMessage ?? 'Call Ended',
      style: TextStyle(
        fontSize: 16,
        color: state == 'busy' ? const Color(0xFFFFB74D) : (state == 'failed' ? Colors.redAccent : AppColors.textMuted),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // Incoming call buttons: Accept & Decline
  Widget _buildIncomingControls(WebRtcService svc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Decline Button (Red)
        _buildActionButton(
          icon: Icons.call_end,
          label: 'Decline',
          color: const Color(0xFFE53935),
          iconColor: Colors.white,
          onTap: () => svc.declineCall(),
        ),
        // Accept Button (Green/Teal)
        _buildActionButton(
          icon: Icons.call,
          label: 'Accept',
          color: const Color(0xFF00C853),
          iconColor: Colors.white,
          onTap: () {
            if (kIsWeb) {
              WebRtcAudioSink.unlockAudio();
            }
            svc.acceptCall();
          },
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // Outgoing call buttons: Mute, Cancel, Speaker
  Widget _buildOutgoingControls(WebRtcService svc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute Mic Toggle
        _buildCircularToggle(
          icon: svc.isMuted ? Icons.mic_off : Icons.mic,
          label: svc.isMuted ? 'Unmute' : 'Mute',
          isActive: svc.isMuted,
          onTap: () => svc.toggleMute(),
        ),

        // Cancel Call Button (Large Red)
        GestureDetector(
          onTap: () => svc.endCall(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Speaker Toggle Button
        _buildCircularToggle(
          icon: svc.isSpeakerOn ? Icons.volume_up : (kIsWeb ? Icons.headphones : Icons.hearing),
          label: svc.isSpeakerOn ? 'Speaker' : (kIsWeb ? 'Headset' : 'Earpiece'),
          isActive: svc.isSpeakerOn,
          onTap: () {
            if (kIsWeb) {
              WebRtcAudioSink.unlockAudio();
            }
            svc.toggleSpeaker();
          },
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // Active connected call controls: Mute, Hang Up, Speaker
  Widget _buildConnectedControls(WebRtcService svc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute Mic Button
        _buildCircularToggle(
          icon: svc.isMuted ? Icons.mic_off : Icons.mic,
          label: svc.isMuted ? 'Unmute' : 'Mute',
          isActive: svc.isMuted,
          onTap: () => svc.toggleMute(),
        ),

        // End Call Button (Large Red)
        GestureDetector(
          onTap: () => svc.endCall(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'End Call',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFEF5350),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Speaker Toggle Button
        _buildCircularToggle(
          icon: svc.isSpeakerOn ? Icons.volume_up : (kIsWeb ? Icons.headphones : Icons.hearing),
          label: svc.isSpeakerOn ? 'Speaker' : (kIsWeb ? 'Headset' : 'Earpiece'),
          isActive: svc.isSpeakerOn,
          onTap: () {
            if (kIsWeb) {
              WebRtcAudioSink.unlockAudio();
            }
            svc.toggleSpeaker();
          },
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildTerminalStatus(WebRtcService svc) {
    return Text(
      svc.statusMessage ?? 'Disconnected',
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 30,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularToggle({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : AppColors.glassWhite,
              border: Border.all(
                color: isActive ? Colors.white : AppColors.glassBorder,
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                icon,
                color: isActive ? Colors.black : Colors.white,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.white : AppColors.textMuted,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value) {
    final bool isGood = value.contains('FOUND') || value.contains('CONNECTED') || value.contains('LIVE') || value.contains('TRANSMITTING') || value.contains('ACTIVE') || value.contains('PLAYING');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isGood
                    ? const Color(0xFF00E676)
                    : (value.contains('NOT') || value.contains('FAILED') || value.contains('WAITING')
                        ? const Color(0xFFFF5252)
                        : const Color(0xFFFFD700)),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAudioDeviceDialog(BuildContext context, WebRtcService svc) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.midnightNavy.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          title: Row(
            children: const [
              Icon(Icons.headphones, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Select Audio Output', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: svc.availableAudioOutputs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = svc.currentAudioOutputDevice.contains('Default') || svc.currentAudioOutputDevice.contains('Headphones');
                  return ListTile(
                    leading: const Icon(Icons.settings_input_component, color: AppColors.primary, size: 20),
                    title: const Text('Default System Output / Headphones', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18) : null,
                    onTap: () async {
                      await svc.setAudioOutputDevice('', label: 'Default System Output / Headphones');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                }
                final dev = svc.availableAudioOutputs[index - 1];
                final devId = dev['deviceId'] ?? '';
                final devLabel = dev['label'] ?? 'Audio Device $index';
                final isSelected = svc.currentAudioOutputDevice == devLabel;
                return ListTile(
                  leading: const Icon(Icons.volume_up, color: Colors.white70, size: 20),
                  title: Text(devLabel, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18) : null,
                  onTap: () async {
                    await svc.setAudioOutputDevice(devId, label: devLabel);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        );
      },
    );
  }
}
