import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'web_notification_service.dart';
import '../utils/call_audio_tone_player.dart';
import '../utils/webrtc_audio_sink.dart';

/// Production-ready WebRTC Internet Voice Calling Service for GEBTALK
/// Provides pure VoIP calling over internet (Wi-Fi / Mobile Data) without SIM or phone numbers.
class WebRtcService extends ChangeNotifier {
  String? currentUserId;
  String? currentCallId;
  String? currentPeerId;
  String? currentPeerName;
  String? currentPeerAvatar;
  String? currentPeerEmail;
  bool isCaller = false;
  final String _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}';
  
  // Call State Machine:
  // 'idle', 'calling', 'ringing', 'connecting', 'connected', 'reconnecting', 'busy', 'declined', 'failed', 'ended', 'cancelled'
  String callState = 'idle';
  String? statusMessage;
  String? errorMessage;
  
  DateTime? callStartTime;
  Timer? _durationTimer;
  int callDurationSeconds = 0;

  RTCPeerConnection? _peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _isRendererInitialized = false;

  bool isMuted = false;
  bool isSpeakerOn = kIsWeb;

  Timer? _incomingPollTimer;
  Timer? _signalingPollTimer;
  Timer? _callTimeoutTimer;
  Timer? _autoDismissTimer;
  int _lastFetchedCandidateId = 0;
  String? _cachedOfferSdp;
  String lastIceConnectionState = 'NEW';
  int audioReceiversCount = 0;
  String remoteTrackState = 'NOT RECEIVED';
  String localTrackState = 'NOT FOUND';
  String currentAudioInputDevice = 'Default Microphone';
  String currentAudioOutputDevice = 'Default Output / Headphones';
  List<Map<String, String>> availableAudioInputs = [];
  List<Map<String, String>> availableAudioOutputs = [];
  Map<String, dynamic> remoteAudioElementDiag = {};

  bool get hasLocalAudioTrack => localStream != null && localStream!.getAudioTracks().isNotEmpty;
  bool get hasRemoteAudioTrack => remoteStream != null && remoteStream!.getAudioTracks().isNotEmpty;
  String get audioOutputMode => isSpeakerOn ? 'SPEAKER' : 'EARPIECE';
  bool get isAudioSessionActive => callState == 'connected' || callState == 'connecting';
  bool get isRingtonePlaying => (callState == 'ringing' && !isCaller) || (callState == 'calling' && isCaller);

  Future<void> refreshAudioDiagnostics() async {
    try {
      if (_peerConnection != null) {
        final receivers = await _peerConnection!.getReceivers();
        audioReceiversCount = receivers.where((r) => r.track?.kind == 'audio').length;
      } else {
        audioReceiversCount = 0;
      }
      remoteAudioElementDiag = WebRtcAudioSink.getAudioDiagnostics();
      availableAudioInputs = await WebRtcAudioSink.getAudioInputDevices();
      availableAudioOutputs = await WebRtcAudioSink.getAudioOutputDevices();
      if (remoteAudioElementDiag['activeSink'] != null) {
        currentAudioOutputDevice = remoteAudioElementDiag['activeSink'].toString();
      }
      if (availableAudioInputs.isNotEmpty) {
        currentAudioInputDevice = availableAudioInputs.first['label'] ?? 'Default Microphone';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTC] refreshAudioDiagnostics error: $e');
    }
  }

  Future<void> setAudioOutputDevice(String deviceId, {String? label}) async {
    await WebRtcAudioSink.setAudioOutputDevice(deviceId, label: label);
    if (label != null) {
      currentAudioOutputDevice = label;
    }
    await refreshAudioDiagnostics();
    notifyListeners();
  }

  Future<bool> testSpeaker() async {
    final success = await WebRtcAudioSink.testSpeaker();
    await refreshAudioDiagnostics();
    notifyListeners();
    return success;
  }
  
  Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302',
          'stun:stun.services.mozilla.com',
          'stun:stun.cloudflare.com:3478',
          'stun:stun.sipgate.net:3478',
          'stun:global.stun.twilio.com:3478',
        ]
      },
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      }
    ],
    'sdpSemantics': 'unified-plan',
  };

  final List<RTCIceCandidate> _pendingLocalCandidates = [];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _isRemoteDescriptionSet = false;

  void initialize(String userId) {
    if (userId.isEmpty) return;
    currentUserId = userId;
    debugPrint('[WebRTC] Initializing WebRTC service for user: $userId (deviceId: $_deviceId)');
    
    // Register device with backend for high-priority background VoIP wake-up
    ApiService.registerDevice(
      deviceId: _deviceId,
      platform: kIsWeb ? 'WEB' : (defaultTargetPlatform == TargetPlatform.android ? 'ANDROID' : 'IOS'),
      deviceName: kIsWeb ? 'GebTalk Web Client' : 'GebTalk App',
    );
    WebNotificationService.requestPermission();

    if (!_isRendererInitialized) {
      _isRendererInitialized = true;
      remoteRenderer.initialize().catchError((e) {
        debugPrint('[WebRTC] RemoteRenderer init error: $e');
      });
    }
    _fetchIceConfig();
    _startIncomingCallPolling();
  }

  /// Fetch dynamic STUN / TURN server configurations from backend
  Future<void> _fetchIceConfig() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/calls/config'),
        headers: {'User-Agent': 'GEBTALK-Client'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && data['iceServers'] != null) {
          _iceConfiguration = Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('[WebRTC] Using default STUN servers: $e');
    }
  }

  void disposeService() {
    _stopIncomingCallPolling();
    _stopSignalingPolling();
    _durationTimer?.cancel();
    _autoDismissTimer?.cancel();
    WebNotificationService.closeActiveNotification();
    _cleanupCall();
  }

  void resetForLogout() {
    disposeService();
    ApiService.unregisterDevice(_deviceId);
    WebNotificationService.closeActiveNotification();
    currentUserId = null;
    currentCallId = null;
    currentPeerId = null;
    currentPeerName = null;
    currentPeerAvatar = null;
    currentPeerEmail = null;
    _cachedOfferSdp = null;
    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
    _isRemoteDescriptionSet = false;
    callState = 'idle';
    statusMessage = null;
    errorMessage = null;
    callDurationSeconds = 0;
    isMuted = false;
    isSpeakerOn = false;
    notifyListeners();
  }

  // Polling for incoming calls when IDLE
  void _startIncomingCallPolling() {
    _incomingPollTimer?.cancel();
    _incomingPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (callState != 'idle' || currentUserId == null) return;
      try {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/calls/incoming?callee_id=$currentUserId'),
          headers: {'User-Agent': 'GEBTALK-Client'},
        );
        if (response.statusCode == 200 && response.body != 'null' && response.body.isNotEmpty) {
          final data = json.decode(response.body);
          if (data != null && data['status'] == 'ringing') {
            currentCallId = data['call_id']?.toString();
            currentPeerId = data['caller_id'];
            currentPeerName = data['caller_name'] ?? data['caller_id'];
            currentPeerAvatar = data['caller_avatar'] ?? '';
            _cachedOfferSdp = data['sdp_offer'];
            isCaller = false;
            callState = 'ringing';
            statusMessage = 'Incoming Voice Call...';
            CallAudioTonePlayer.playIncomingRingtone();
            
            // Present system/desktop incoming call alert if in background or on desktop
            WebNotificationService.showIncomingCallNotification(
              callerName: currentPeerName ?? 'GebTalk User',
              callType: 'Voice',
              onAnswer: () => acceptCall(),
              onDecline: () => declineCall(),
            );
            
            notifyListeners();
            _startSignalingPolling();
          }
        }
      } catch (e) {
        debugPrint('[WebRTC] Incoming call poll error: $e');
      }
    });
  }

  void _stopIncomingCallPolling() {
    _incomingPollTimer?.cancel();
    _incomingPollTimer = null;
  }

  // Polling for call status, answers, and candidates
  void _startSignalingPolling() {
    _signalingPollTimer?.cancel();
    _lastFetchedCandidateId = 0;
    
    _signalingPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) async {
      if (currentCallId == null) return;
      
      try {
        // 1. Check status of call
        final statusRes = await http.get(
          Uri.parse('${ApiService.baseUrl}/calls/status?call_id=$currentCallId'),
          headers: {'User-Agent': 'GEBTALK-Client'},
        );
        
        if (statusRes.statusCode == 200) {
          final data = json.decode(statusRes.body);
          final status = data['status'];
          
          if (status == 'ended' || status == 'declined' || status == 'rejected' || status == 'cancelled' || status == 'busy') {
            WebNotificationService.closeActiveNotification();
            CallAudioTonePlayer.stopAllTones();
            _transitionToTerminalState(
              status == 'declined' || status == 'rejected' ? 'declined' : 
              (status == 'cancelled' ? 'cancelled' : 
              (status == 'busy' ? 'busy' : 'ended'))
            );
            return;
          }
          
          // Multi-device call forking: if answered on another device
          if (!isCaller && callState == 'ringing' && (status == 'connected' || status == 'answered')) {
            debugPrint('[WebRTC] Call was answered on another device. Dismissing ringing.');
            WebNotificationService.closeActiveNotification();
            CallAudioTonePlayer.stopAllTones();
            _transitionToTerminalState('ended');
            return;
          }
          
          // Caller side: Wait for accepted answer
          if (isCaller && (callState == 'calling' || callState == 'ringing') && (status == 'connected' || status == 'answered')) {
            final sdpAnswer = data['sdp_answer'];
            if (sdpAnswer != null) {
              // Stop tones BEFORE setting remote description so the tone
              // AudioContext is fully released before WebRTC audio takes over
              CallAudioTonePlayer.stopAllTones();
              
              callState = 'connecting';
              statusMessage = 'Connecting encrypted audio...';
              notifyListeners();
              
              // === DIAGNOSTIC: SDP Answer Audio Check ===
              final answerStr = sdpAnswer.toString();
              final hasAudio = answerStr.contains('m=audio');
              final direction = answerStr.contains('a=sendrecv') ? 'sendrecv' 
                  : answerStr.contains('a=recvonly') ? 'recvonly' 
                  : answerStr.contains('a=sendonly') ? 'sendonly' 
                  : answerStr.contains('a=inactive') ? 'inactive' : 'unknown';
              debugPrint('[WebRTC][DIAG] SDP ANSWER: m=audio=${hasAudio} direction=$direction');
              
              await _peerConnection?.setRemoteDescription(
                RTCSessionDescription(sdpAnswer, 'answer')
              );
              _isRemoteDescriptionSet = true;
              
              // Flush any buffered remote ICE candidates
              for (final cand in _pendingRemoteCandidates) {
                try {
                  await _peerConnection?.addCandidate(cand);
                } catch (e) {
                  debugPrint('[WebRTC] Error adding buffered remote candidate: $e');
                }
              }
              _pendingRemoteCandidates.clear();

              // Ensure microphone tracks are transmitting
              if (localStream != null) {
                for (var track in localStream!.getAudioTracks()) {
                  track.enabled = !isMuted;
                }
              }
              if (_peerConnection != null) {
                _peerConnection!.getSenders().then((senders) {
                  for (var sender in senders) {
                    if (sender.track != null && sender.track!.kind == 'audio') {
                      sender.track!.enabled = !isMuted;
                    }
                  }
                }).catchError((_) {});
              }

              // Default to loudspeaker on Web (browsers have no access to physical top earpiece), or top earpiece on native mobile
              await _applyAudioRouting(kIsWeb ? true : false);
              
              callState = 'connected';
              statusMessage = null;
              callStartTime = DateTime.now();
              _startDurationTimer();
              CallAudioTonePlayer.playCallConnectedChime();
              debugPrint('[WebRTC][DIAG] CALL STATE: CONNECTED (caller side)');
              notifyListeners();
            }
          }
        }

        // 2. Fetch remote ICE candidates
        final iceRes = await http.get(
          Uri.parse('${ApiService.baseUrl}/calls/ice-candidates?call_id=$currentCallId&exclude_sender_id=$currentUserId'),
          headers: {'User-Agent': 'GEBTALK-Client'},
        );
        
        if (iceRes.statusCode == 200) {
          final List candidates = json.decode(iceRes.body);
          for (var item in candidates) {
            final int id = item['id'];
            if (id > _lastFetchedCandidateId) {
              _lastFetchedCandidateId = id;
              final candMap = json.decode(item['candidate']);
              final candidate = RTCIceCandidate(
                candMap['candidate'],
                candMap['sdpMid'],
                candMap['sdpMLineIndex'],
              );
              if (_isRemoteDescriptionSet && _peerConnection != null) {
                try {
                  await _peerConnection!.addCandidate(candidate);
                } catch (ce) {
                  debugPrint('[WebRTC] Error adding remote candidate: $ce');
                }
              } else {
                _pendingRemoteCandidates.add(candidate);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[WebRTC] Signaling poll error: $e');
      }
    });
  }

  void _stopSignalingPolling() {
    _signalingPollTimer?.cancel();
    _signalingPollTimer = null;
  }

  Future<void> _sendLocalCandidate(RTCIceCandidate candidate) async {
    if (currentCallId == null || currentUserId == null) return;
    try {
      final candidateJson = json.encode({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
      await http.post(
        Uri.parse('${ApiService.baseUrl}/calls/ice-candidate'),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
        body: json.encode({
          'call_id': int.parse(currentCallId!),
          'sender_id': currentUserId,
          'candidate': candidateJson,
        }),
      );
    } catch (e) {
      debugPrint('[WebRTC] Error sending ICE candidate: $e');
    }
  }

  Future<void> _flushPendingLocalCandidates() async {
    if (currentCallId == null || currentUserId == null) return;
    final toSend = List<RTCIceCandidate>.from(_pendingLocalCandidates);
    _pendingLocalCandidates.clear();
    for (final c in toSend) {
      await _sendLocalCandidate(c);
    }
  }

  /// Unified Audio Routing: Applies routing across both flutter_webrtc helper and native Android AudioManager
  Future<void> _applyAudioRouting(bool speakerOn) async {
    isSpeakerOn = speakerOn;
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(speakerOn);
      } catch (e) {
        debugPrint('[WebRTC] Helper.setSpeakerphoneOn error: $e');
      }
    }
    try {
      await WebRtcAudioSink.setSpeakerphoneOn(speakerOn);
    } catch (e) {
      debugPrint('[WebRTC] WebRtcAudioSink.setSpeakerphoneOn error: $e');
    }
    notifyListeners();
  }

  // Setup local media & RTCPeerConnection with graceful permission handling
  Future<bool> _setupPeerConnection() async {
    // 1. Verify and request microphone runtime permission (vital for Android 14 / Samsung A06)
    final hasMic = await WebRtcAudioSink.checkAndRequestMicrophonePermission();
    if (!hasMic) {
      debugPrint('[WebRTC] Microphone runtime permission denied');
      errorMessage = 'Microphone permission required for voice calls.';
      statusMessage = 'Microphone Permission Required';
      _transitionToTerminalState('failed');
      return false;
    }

    // NOTE: Do NOT set audio routing before getUserMedia.
    // flutter_webrtc configures its own audio session during getUserMedia.
    // Setting MODE_IN_COMMUNICATION prematurely causes race conditions.

    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    } catch (e) {
      debugPrint('[WebRTC] Complex microphone constraints failed, falling back to simple audio: $e');
      try {
        localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      } catch (e2) {
        debugPrint('[WebRTC] Microphone access denied or unavailable: $e2');
        localStream = null;
      }
    }

    // === DIAGNOSTIC: Local Audio Track Status ===
    if (localStream != null) {
      final audioTracks = localStream!.getAudioTracks();
      localTrackState = audioTracks.isNotEmpty ? 'FOUND (LIVE)' : 'NOT FOUND';
      debugPrint('[WebRTC][DIAG] LOCAL AUDIO TRACK: $localTrackState (count: ${audioTracks.length})');
      for (var track in audioTracks) {
        debugPrint('[WebRTC][DIAG] LOCAL TRACK STATE: enabled=${track.enabled} | kind=${track.kind} | muted=${track.muted} | id=${track.id}');
        track.enabled = !isMuted;
      }
      // Allow microphone hardware to settle
      await Future.delayed(const Duration(milliseconds: 120));
    } else {
      localTrackState = 'NOT FOUND';
      debugPrint('[WebRTC][DIAG] LOCAL AUDIO TRACK: NOT FOUND (localStream is null)');
    }
    
    try {
      _isRemoteDescriptionSet = false;
      _peerConnection = await createPeerConnection(_iceConfiguration);
      debugPrint('[WebRTC][DIAG] PEER CONNECTION: CREATED');
      
      // Add local tracks to peer connection if available
      if (localStream != null) {
        localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, localStream!);
        });
        debugPrint('[WebRTC][DIAG] Added ${localStream!.getTracks().length} local track(s) to PeerConnection');
      } else {
        try {
          await _peerConnection!.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
            init: RTCRtpTransceiverInit(
              direction: TransceiverDirection.RecvOnly,
            ),
          );
          debugPrint('[WebRTC][DIAG] Added RecvOnly audio transceiver (no mic)');
        } catch (_) {}
      }

      // Handle local candidates
      _peerConnection!.onIceCandidate = (candidate) async {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
        if (currentCallId == null || currentUserId == null) {
          _pendingLocalCandidates.add(candidate);
          debugPrint('[WebRTC] Buffered local ICE candidate while callId is pending');
          return;
        }
        await _sendLocalCandidate(candidate);
      };

      // Handle connection states
      _peerConnection!.onConnectionState = (state) {
        debugPrint('[WebRTC][DIAG] PEER CONNECTION STATE: $state');
      };

      _peerConnection!.onIceConnectionState = (state) async {
        final stateName = state.toString().split('.').last.replaceAll('RTCIceConnectionState', '').toUpperCase();
        lastIceConnectionState = stateName;
        debugPrint('[WebRTC][DIAG] ICE CONNECTION: $state ($stateName)');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          CallAudioTonePlayer.stopAllTones();
          if (localStream != null) {
            for (var track in localStream!.getAudioTracks()) {
              track.enabled = !isMuted;
            }
          }
          if (_peerConnection != null) {
            _peerConnection!.getSenders().then((senders) {
              debugPrint('[WebRTC][DIAG] SENDERS count: ${senders.length}');
              for (var sender in senders) {
                if (sender.track != null && sender.track!.kind == 'audio') {
                  sender.track!.enabled = !isMuted;
                  debugPrint('[WebRTC][DIAG] SENDER TRACK: kind=${sender.track!.kind} enabled=${sender.track!.enabled}');
                }
              }
            }).catchError((_) {});
            // Diagnostic: check receivers for remote audio
            _peerConnection!.getReceivers().then((receivers) {
              debugPrint('[WebRTC][DIAG] RECEIVERS count: ${receivers.length}');
              for (var receiver in receivers) {
                if (receiver.track != null) {
                  debugPrint('[WebRTC][DIAG] RECEIVER TRACK: kind=${receiver.track!.kind} enabled=${receiver.track!.enabled}');
                }
              }
            }).catchError((_) {});
          }
          await _applyAudioRouting(isSpeakerOn);
          debugPrint('[WebRTC][DIAG] AUDIO OUTPUT: ${isSpeakerOn ? "SPEAKER" : "EARPIECE"} | MICROPHONE: ${isMuted ? "DISABLED" : "ENABLED"} | MUTE: ${isMuted ? "ON" : "OFF"}');
          if (callState != 'connected') {
            callState = 'connected';
            statusMessage = null;
            callStartTime ??= DateTime.now();
            _startDurationTimer();
            debugPrint('[WebRTC][DIAG] CALL STATE: CONNECTED');
          }
          await refreshAudioDiagnostics();
          notifyListeners();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          if (callState == 'connected') {
            callState = 'reconnecting';
            statusMessage = 'Reconnecting...';
            debugPrint('[WebRTC][DIAG] CALL STATE: RECONNECTING');
            notifyListeners();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('[WebRTC][DIAG] ICE CONNECTION: FAILED');
          if (callState != 'connected') {
            _transitionToTerminalState('failed');
          }
        }
      };

      // Handle remote tracks
      _peerConnection!.onAddStream = (stream) async {
        debugPrint('[WebRTC][DIAG] onAddStream fired — audio tracks count: ${stream.getAudioTracks().length}');
        remoteStream = stream;
        remoteRenderer.srcObject = stream;
        remoteRenderer.muted = false;
        remoteTrackState = 'LIVE';
        WebRtcAudioSink.attachRemoteAudio(stream);
        for (var track in stream.getAudioTracks()) {
          track.enabled = true;
          debugPrint('[WebRTC][DIAG] REMOTE AUDIO TRACK (onAddStream): kind=${track.kind} enabled=${track.enabled} muted=${track.muted} id=${track.id}');
        }
        await _applyAudioRouting(isSpeakerOn);
        await refreshAudioDiagnostics();
        notifyListeners();
      };
      
      _peerConnection!.onTrack = (event) async {
        debugPrint('[WebRTC][DIAG] onTrack fired — track.kind=${event.track.kind} enabled=${event.track.enabled} muted=${event.track.muted} streams=${event.streams.length}');
        remoteTrackState = (event.track.enabled && !(event.track.muted ?? false)) ? 'LIVE' : 'LIVE';
        
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          remoteRenderer.srcObject = event.streams[0];
          remoteRenderer.muted = false;
          WebRtcAudioSink.attachRemoteAudio(event.streams[0]);
          for (var track in event.streams[0].getAudioTracks()) {
            track.enabled = true;
            debugPrint('[WebRTC][DIAG] REMOTE AUDIO TRACK (onTrack): kind=${track.kind} enabled=${track.enabled} id=${track.id}');
          }
        } else {
          final track = event.track;
          if (track.kind == 'audio') {
            track.enabled = true;
            debugPrint('[WebRTC][DIAG] REMOTE AUDIO TRACK (onTrack no stream): kind=${track.kind} enabled=${track.enabled}');
            WebRtcAudioSink.attachRemoteTrack(track);
          }
        }
        await _applyAudioRouting(isSpeakerOn);
        await refreshAudioDiagnostics();
        notifyListeners();
      };
      return true;
    } catch (e) {
      debugPrint('[WebRTC] PeerConnection init error: $e');
      errorMessage = 'Unable to initialize WebRTC connection.';
      _transitionToTerminalState('failed');
      return false;
    }
  }

  // Dial out to a peer over the internet
  Future<void> startCall(String calleeId, String peerName, {String? calleeEmail, String? peerAvatar}) async {
    if (callState != 'idle' || currentUserId == null) return;
    
    isCaller = true;
    currentPeerName = peerName;
    currentPeerAvatar = peerAvatar ?? '';
    currentPeerEmail = calleeEmail ?? (calleeId.contains('@') ? calleeId : null);
    
    String targetSignalingId = calleeId;

    // If callee identifier is an email address, resolve to active target session
    if (calleeId.contains('@')) {
      final lookup = await ApiService.lookupCallTarget(calleeId);
      if (lookup != null && lookup['found'] == true && lookup['resolved'] != null) {
        final resolved = lookup['resolved'];
        targetSignalingId = resolved['user_id']?.toString() ?? calleeId;
        currentPeerName = resolved['name'] ?? peerName;
        currentPeerEmail = resolved['email'] ?? calleeId;
        currentPeerAvatar = resolved['avatar'] ?? currentPeerAvatar;
      }
    }

    currentPeerId = targetSignalingId;
    
    // Prevent self-calling
    if (currentUserId == targetSignalingId || (currentPeerEmail != null && currentPeerEmail == currentUserId)) {
      statusMessage = 'Cannot Call Yourself';
      errorMessage = 'You cannot initiate a call to your own account.';
      _transitionToTerminalState('failed');
      return;
    }

    callState = 'calling';
    statusMessage = 'Calling...';
    errorMessage = null;
    WebRtcAudioSink.unlockAudio();
    CallAudioTonePlayer.playOutgoingDialTone();
    // NOTE: Do NOT call _applyAudioRouting here — it races with getUserMedia
    // and flutter_webrtc's audio session. Routing is applied after ICE connects.
    notifyListeners();

    // 35-second call timeout timer
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 35), () {
      if (callState == 'calling' || callState == 'ringing') {
        if (currentPeerEmail != null && currentPeerEmail!.contains('@')) {
          ApiService.notifyMissedCall(
            calleeEmail: currentPeerEmail!,
            callType: 'voice',
          );
        }
        statusMessage = 'No Answer';
        _transitionToTerminalState('ended');
      }
    });

    final setupSuccess = await _setupPeerConnection();
    if (!setupSuccess) return;

    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(offer);

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/calls/create'),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
        body: json.encode({
          'caller_id': currentUserId,
          'callee_id': targetSignalingId,
          'sdp_offer': offer.sdp,
          'call_type': 'voice',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        currentCallId = data['call_id']?.toString();
        // Flush any candidates gathered during offer creation
        await _flushPendingLocalCandidates();
        callState = 'ringing';
        statusMessage = 'Ringing...';
        notifyListeners();
        _startSignalingPolling();
      } else if (response.statusCode == 486) {
        // Callee is Busy
        statusMessage = 'User is Busy';
        _transitionToTerminalState('busy');
      } else if (response.statusCode == 403) {
        // Role authorization violation
        statusMessage = 'Call Restricted (Unauthorized)';
        errorMessage = 'You do not have authorization to call this contact.';
        _transitionToTerminalState('failed');
      } else if (response.statusCode == 400) {
        try {
          final errData = json.decode(response.body);
          statusMessage = errData['error'] ?? 'Cannot Place Call';
          errorMessage = errData['error'] ?? 'Cannot Place Call';
        } catch (_) {
          statusMessage = 'Cannot Place Call';
        }
        _transitionToTerminalState('failed');
      } else {
        statusMessage = 'Call Failed';
        _transitionToTerminalState('failed');
      }
    } catch (e) {
      debugPrint('[WebRTC] Error starting WebRTC call: $e');
      statusMessage = 'Connection Error';
      errorMessage = 'Could not connect call. Check network.';
      _transitionToTerminalState('failed');
    }
  }

  // Accept incoming call
  Future<void> acceptCall() async {
    if (callState != 'ringing' || currentCallId == null) return;

    // Immediately stop loud incoming ringtone so audio hardware switches cleanly to top earpiece receiver
    CallAudioTonePlayer.stopAllTones();
    callState = 'connecting';
    statusMessage = 'Connecting...';
    WebRtcAudioSink.unlockAudio();
    // NOTE: Do NOT call _applyAudioRouting here — _setupPeerConnection will
    // acquire the microphone first, then audio routing is applied after ICE connects.
    notifyListeners();

    final setupSuccess = await _setupPeerConnection();
    if (!setupSuccess) return;

    try {
      String? offerSdp = _cachedOfferSdp;
      
      // If offer SDP was not in memory, fetch from backend status endpoint
      if (offerSdp == null || offerSdp.isEmpty) {
        final statusRes = await http.get(
          Uri.parse('${ApiService.baseUrl}/calls/status?call_id=$currentCallId'),
          headers: {'User-Agent': 'GEBTALK-Client'},
        );
        
        if (statusRes.statusCode == 200) {
          final data = json.decode(statusRes.body);
          offerSdp = data['sdp_offer'];
        }
      }

      if (offerSdp == null || offerSdp.isEmpty) {
        throw Exception('SDP Offer is missing for call $currentCallId');
      }
      
      // === DIAGNOSTIC: SDP Offer Audio Check ===
      final offerStr = offerSdp.toString();
      final hasAudio = offerStr.contains('m=audio');
      final direction = offerStr.contains('a=sendrecv') ? 'sendrecv' 
          : offerStr.contains('a=recvonly') ? 'recvonly' 
          : offerStr.contains('a=sendonly') ? 'sendonly' 
          : offerStr.contains('a=inactive') ? 'inactive' : 'unknown';
      debugPrint('[WebRTC][DIAG] SDP OFFER: m=audio=$hasAudio direction=$direction');
      
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerSdp, 'offer')
      );
      _isRemoteDescriptionSet = true;

      // Flush any buffered remote ICE candidates
      for (final cand in _pendingRemoteCandidates) {
        try {
          await _peerConnection?.addCandidate(cand);
        } catch (e) {
          debugPrint('[WebRTC] Error adding buffered candidate: $e');
        }
      }
      _pendingRemoteCandidates.clear();
      
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      // Flush any local candidates gathered during answer creation
      await _flushPendingLocalCandidates();

      final acceptRes = await http.post(
        Uri.parse('${ApiService.baseUrl}/calls/accept'),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
        body: json.encode({
          'call_id': int.parse(currentCallId!),
          'sdp_answer': answer.sdp,
          'device_id': _deviceId,
        }),
      );
      
      if (acceptRes.statusCode == 200) {
        // Ensure local microphone audio is active
        if (localStream != null) {
          for (var track in localStream!.getAudioTracks()) {
            track.enabled = !isMuted;
          }
        }
        if (_peerConnection != null) {
          _peerConnection!.getSenders().then((senders) {
            for (var sender in senders) {
              if (sender.track != null && sender.track!.kind == 'audio') {
                sender.track!.enabled = !isMuted;
              }
            }
          }).catchError((_) {});
        }

        // Default to loudspeaker on Web (browsers have no access to physical top earpiece), or top earpiece on native mobile
        await _applyAudioRouting(kIsWeb ? true : false);

        callState = 'connected';
        statusMessage = null;
        callStartTime = DateTime.now();
        _startDurationTimer();
        _startSignalingPolling();
        CallAudioTonePlayer.stopAllTones();
        CallAudioTonePlayer.playCallConnectedChime();
        debugPrint('[WebRTC][DIAG] CALL STATE: CONNECTED (receiver side)');
        notifyListeners();
      } else {
        throw Exception('Server rejected call accept: status ${acceptRes.statusCode}');
      }
    } catch (e) {
      debugPrint('[WebRTC] Error accepting call: $e');
      _transitionToTerminalState('failed');
    }
  }

  // Reject / Decline call
  Future<void> declineCall() async {
    if (callState != 'ringing') return;
    final tempCallId = currentCallId;
    WebNotificationService.closeActiveNotification();
    CallAudioTonePlayer.stopAllTones();
    _transitionToTerminalState('declined');
    
    if (tempCallId != null) {
      ApiService.declineCall(int.parse(tempCallId));
    }
  }

  // Cancel / End active call
  Future<void> endCall() async {
    if (callState == 'idle') return;
    
    final tempCallId = currentCallId;
    final tempDuration = callDurationSeconds;
    final tempStateBeforeEnd = callState;
    final tempIsCaller = isCaller;
    final tempPeerEmail = currentPeerEmail;
    final isCancel = (callState == 'calling' || callState == 'ringing') && isCaller;

    WebNotificationService.closeActiveNotification();
    CallAudioTonePlayer.stopAllTones();
    _transitionToTerminalState(isCancel ? 'cancelled' : 'ended');

    // If caller hung up before connecting, trigger missed call transactional alert
    if (tempIsCaller && (tempStateBeforeEnd == 'calling' || tempStateBeforeEnd == 'ringing') && tempDuration == 0) {
      if (tempPeerEmail != null && tempPeerEmail.contains('@')) {
        ApiService.notifyMissedCall(
          calleeEmail: tempPeerEmail,
          callType: 'voice',
        );
      }
    }

    if (tempCallId != null) {
      if (isCancel) {
        ApiService.cancelCall(int.parse(tempCallId));
      } else {
        try {
          await http.post(
            Uri.parse('${ApiService.baseUrl}/calls/end'),
            headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
            body: json.encode({
              'call_id': int.parse(tempCallId),
              'duration': tempDuration,
              'state_before_end': tempStateBeforeEnd,
              'reason': 'ended',
            }),
          );
        } catch (e) {
          debugPrint('[WebRTC] Error posting end call: $e');
        }
      }
    }
  }

  void _transitionToTerminalState(String finalState) {
    callState = finalState;
    if (finalState == 'busy') {
      statusMessage = 'User is Busy';
    } else if (finalState == 'declined') {
      statusMessage = 'Call Declined';
    } else if (finalState == 'failed') {
      statusMessage = statusMessage ?? errorMessage ?? 'Call Failed';
    } else if (finalState == 'cancelled') {
      statusMessage = 'Call Cancelled';
    } else {
      statusMessage = 'Call Ended';
    }
    CallAudioTonePlayer.stopAllTones();
    CallAudioTonePlayer.playCallEndedTone();
    notifyListeners();

    _cleanupMedia();

    // Auto dismiss overlay back to idle after 1.5 seconds
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(milliseconds: 1500), () {
      _cleanupCall();
    });
  }

  void _cleanupMedia() {
    CallAudioTonePlayer.stopAllTones();
    _stopSignalingPolling();
    _durationTimer?.cancel();
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;

    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
    _isRemoteDescriptionSet = false;
    _lastFetchedCandidateId = 0;
    lastIceConnectionState = 'NEW';

    WebRtcAudioSink.detachRemoteAudio();
    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }

    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    localStream = null;

    remoteRenderer.srcObject = null;
    remoteStream?.dispose();
    remoteStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;
  }

  void _cleanupCall() {
    _cleanupMedia();
    callDurationSeconds = 0;
    callStartTime = null;
    callState = 'idle';
    statusMessage = null;
    errorMessage = null;
    currentCallId = null;
    currentPeerId = null;
    currentPeerName = null;
    currentPeerAvatar = null;
    isCaller = false;
    isMuted = false;
    isSpeakerOn = kIsWeb;

    notifyListeners();
    _startIncomingCallPolling(); // Resume listening for incoming calls
  }

  // Call duration counter
  void _startDurationTimer() {
    _durationTimer?.cancel();
    callDurationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      callDurationSeconds++;
      notifyListeners();
    });
  }

  // Audio toggles
  void toggleMute() {
    isMuted = !isMuted;
    
    // 1. Toggle tracks on local MediaStream
    if (localStream != null) {
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = !isMuted;
      }
    }
    
    // 2. Toggle audio tracks on PeerConnection senders
    if (_peerConnection != null) {
      _peerConnection!.getSenders().then((senders) {
        for (var sender in senders) {
          if (sender.track != null && sender.track!.kind == 'audio') {
            sender.track!.enabled = !isMuted;
          }
        }
      }).catchError((e) {
        debugPrint('[WebRTC] Error toggling sender mute: $e');
      });
    }
    
    notifyListeners();
  }

  void toggleSpeaker() {
    _applyAudioRouting(!isSpeakerOn);
  }
}
