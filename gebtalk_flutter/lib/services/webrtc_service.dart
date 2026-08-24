import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
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
  bool isSpeakerOn = false;

  Timer? _incomingPollTimer;
  Timer? _signalingPollTimer;
  Timer? _callTimeoutTimer;
  Timer? _autoDismissTimer;
  int _lastFetchedCandidateId = 0;
  String? _cachedOfferSdp;
  
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

  void initialize(String userId) {
    if (userId.isEmpty) return;
    currentUserId = userId;
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
    _cleanupCall();
  }

  void resetForLogout() {
    disposeService();
    currentUserId = null;
    currentCallId = null;
    currentPeerId = null;
    currentPeerName = null;
    currentPeerAvatar = null;
    currentPeerEmail = null;
    _cachedOfferSdp = null;
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
    
    _signalingPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
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
          
          if (status == 'ended' || status == 'declined' || status == 'busy') {
            _transitionToTerminalState(status == 'declined' ? 'declined' : (status == 'busy' ? 'busy' : 'ended'));
            return;
          }
          
          // Caller side: Wait for accepted answer
          if (isCaller && (callState == 'calling' || callState == 'ringing') && status == 'connected') {
            final sdpAnswer = data['sdp_answer'];
            if (sdpAnswer != null) {
              callState = 'connecting';
              statusMessage = 'Connecting encrypted audio...';
              notifyListeners();
              
              await _peerConnection?.setRemoteDescription(
                RTCSessionDescription(sdpAnswer, 'answer')
              );
              
              callState = 'connected';
              statusMessage = null;
              callStartTime = DateTime.now();
              _startDurationTimer();
              CallAudioTonePlayer.stopAllTones();
              CallAudioTonePlayer.playCallConnectedChime();
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
              await _peerConnection?.addCandidate(candidate);
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

  // Setup local media & RTCPeerConnection with graceful permission handling
  Future<bool> _setupPeerConnection() async {
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
    
    try {
      _peerConnection = await createPeerConnection(_iceConfiguration);
      
      // Add local tracks to peer connection if available
      if (localStream != null) {
        localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, localStream!);
        });
      }

      // Handle local candidates
      _peerConnection!.onIceCandidate = (candidate) async {
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
      };

      // Handle connection states
      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('[WebRTC] ICE connection state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (callState != 'connected') {
            callState = 'connected';
            statusMessage = null;
            callStartTime ??= DateTime.now();
            _startDurationTimer();
            notifyListeners();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          if (callState == 'connected') {
            callState = 'reconnecting';
            statusMessage = 'Reconnecting...';
            notifyListeners();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('[WebRTC] ICE connection state failed notification');
          if (callState != 'connected') {
            _transitionToTerminalState('failed');
          }
        }
      };

      // Handle remote tracks
      _peerConnection!.onAddStream = (stream) {
        remoteStream = stream;
        remoteRenderer.srcObject = stream;
        WebRtcAudioSink.attachRemoteAudio(stream);
        for (var track in stream.getAudioTracks()) {
          track.enabled = true;
        }
        notifyListeners();
      };
      
      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          remoteRenderer.srcObject = event.streams[0];
          WebRtcAudioSink.attachRemoteAudio(event.streams[0]);
          for (var track in event.streams[0].getAudioTracks()) {
            track.enabled = true;
          }
          notifyListeners();
        }
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
    CallAudioTonePlayer.playOutgoingDialTone();
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

    callState = 'connecting';
    statusMessage = 'Connecting...';
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
      
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerSdp, 'offer')
      );
      
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      final acceptRes = await http.post(
        Uri.parse('${ApiService.baseUrl}/calls/accept'),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
        body: json.encode({
          'call_id': int.parse(currentCallId!),
          'sdp_answer': answer.sdp,
        }),
      );
      
      if (acceptRes.statusCode == 200) {
        callState = 'connected';
        statusMessage = null;
        callStartTime = DateTime.now();
        _startDurationTimer();
        _startSignalingPolling();
        CallAudioTonePlayer.stopAllTones();
        CallAudioTonePlayer.playCallConnectedChime();
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
    _transitionToTerminalState('declined');
    
    if (tempCallId != null) {
      try {
        await http.post(
          Uri.parse('${ApiService.baseUrl}/calls/end'),
          headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
          body: json.encode({
            'call_id': int.parse(tempCallId),
            'duration': 0,
            'state_before_end': 'ringing',
            'reason': 'declined',
          }),
        );
      } catch (e) {
        debugPrint('[WebRTC] Error posting decline: $e');
      }
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
      try {
        await http.post(
          Uri.parse('${ApiService.baseUrl}/calls/end'),
          headers: {'Content-Type': 'application/json', 'User-Agent': 'GEBTALK-Client'},
          body: json.encode({
            'call_id': int.parse(tempCallId),
            'duration': tempDuration,
            'state_before_end': tempStateBeforeEnd,
            'reason': isCancel ? 'cancelled' : 'ended',
          }),
        );
      } catch (e) {
        debugPrint('[WebRTC] Error posting end call: $e');
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

    WebRtcAudioSink.detachRemoteAudio();
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
    isSpeakerOn = false;

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
    isSpeakerOn = !isSpeakerOn;
    if (!kIsWeb) {
      Helper.setSpeakerphoneOn(isSpeakerOn);
    }
    notifyListeners();
  }
}
