import { useState, useEffect, useRef, useCallback } from 'react';
import { CallState, CallSessionInfo, UserPresence, SignalingMessage } from '../types/calling.js';
import { SignalingClient } from '../services/SignalingClient.js';
import { WebRTCCallManager } from '../services/WebRTCCallManager.js';
import { MockPushNotificationService } from '../services/NotificationService.js';
import { isValidTransition, CALL_CONFIG } from '../state/callState.js';

interface UseWebRTCCallOptions {
  serverUrl: string;
  userId: string;
  displayName: string;
}

export function useWebRTCCall({ serverUrl, userId, displayName }: UseWebRTCCallOptions) {
  const [isConnected, setIsConnected] = useState<boolean>(false);
  const [users, setUsers] = useState<UserPresence[]>([]);
  const [callState, setCallState] = useState<CallState>('IDLE');
  const [activeCall, setActiveCall] = useState<CallSessionInfo | null>(null);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [connectionQuality, setConnectionQuality] = useState<string>('idle');

  const signalingRef = useRef<SignalingClient | null>(null);
  const webrtcRef = useRef<WebRTCCallManager | null>(null);
  const notificationRef = useRef<MockPushNotificationService>(new MockPushNotificationService());

  const durationTimerRef = useRef<number>();
  const ringTimeoutRef = useRef<number>();
  const connectionTimeoutRef = useRef<number>();
  const pendingOfferRef = useRef<string | null>(null);

  const safeSetCallState = useCallback((nextState: CallState) => {
    setCallState((current) => {
      if (isValidTransition(current, nextState)) {
        console.log(`[CallState] Transition: ${current} -> ${nextState}`);
        return nextState;
      }
      console.warn(`[CallState] Invalid transition ignored: ${current} -> ${nextState}`);
      return current;
    });
  }, []);

  const clearAllTimers = useCallback(() => {
    if (durationTimerRef.current) clearInterval(durationTimerRef.current);
    if (ringTimeoutRef.current) clearTimeout(ringTimeoutRef.current);
    if (connectionTimeoutRef.current) clearTimeout(connectionTimeoutRef.current);
  }, []);

  const resetCallState = useCallback(
    (reason?: string) => {
      clearAllTimers();
      webrtcRef.current?.cleanup();
      setIsMuted(false);
      pendingOfferRef.current = null;
      setConnectionQuality('idle');

      if (activeCall?.callId) {
        notificationRef.current.cancelNotification(activeCall.callId);
      }

      if (reason) {
        console.log(`[Call] Reset: ${reason}`);
      }

      safeSetCallState('IDLE');
      setActiveCall(null);
    },
    [activeCall, clearAllTimers, safeSetCallState]
  );

  // Initialize WebRTC Call Manager
  useEffect(() => {
    webrtcRef.current = new WebRTCCallManager({
      onIceCandidate: (candidate) => {
        if (activeCall && signalingRef.current) {
          signalingRef.current.send({
            type: 'ice-candidate',
            from: userId,
            to: activeCall.peerId,
            callId: activeCall.callId,
            candidate,
          });
        }
      },
      onRemoteStream: () => {
        setConnectionQuality('optimal');
      },
      onConnectionStateChange: (state) => {
        setConnectionQuality(state);
        if (state === 'connected') {
          if (connectionTimeoutRef.current) clearTimeout(connectionTimeoutRef.current);
          safeSetCallState('CONNECTED');

          // Start call duration timer
          if (durationTimerRef.current) clearInterval(durationTimerRef.current);
          durationTimerRef.current = window.setInterval(() => {
            setActiveCall((prev) => (prev ? { ...prev, durationSeconds: prev.durationSeconds + 1 } : null));
          }, 1000);
        } else if (state === 'failed' || state === 'closed') {
          setErrorMessage('WebRTC media connection failed');
          safeSetCallState('FAILED');
          setTimeout(() => resetCallState('WebRTC state failed'), CALL_CONFIG.DISMISS_AUTO_MS);
        }
      },
      onError: (err) => {
        setErrorMessage(err.message);
        safeSetCallState('FAILED');
        setTimeout(() => resetCallState(err.message), CALL_CONFIG.DISMISS_AUTO_MS);
      },
    });

    return () => {
      webrtcRef.current?.cleanup();
    };
  }, [userId, activeCall, safeSetCallState, resetCallState]);

  // Connect Signaling Client
  useEffect(() => {
    if (!userId || !serverUrl) return;

    const signaling = new SignalingClient(serverUrl);
    signalingRef.current = signaling;

    signaling.connect(userId, displayName, (connected) => {
      setIsConnected(connected);
      if (!connected && callState !== 'IDLE') {
        setErrorMessage('Signaling connection lost');
        resetCallState('Signaling dropped');
      }
    });

    const unregRegistered = signaling.on('registered', (msg: SignalingMessage) => {
      if (msg.users) setUsers(msg.users);
    });

    const unregUserOnline = signaling.on('user-online', (msg: SignalingMessage) => {
      if (msg.user) {
        setUsers((prev) => {
          const filtered = prev.filter((u) => u.userId !== msg.user!.userId);
          return [...filtered, msg.user!];
        });
      }
    });

    const unregUserOffline = signaling.on('user-offline', (msg: SignalingMessage) => {
      if (msg.userId) {
        setUsers((prev) => prev.filter((u) => u.userId !== msg.userId));
      }
    });

    const unregCallRequest = signaling.on('call-request', (msg: SignalingMessage) => {
      if (!msg.from || !msg.callId) return;

      const callerId = msg.from;
      const callerName = msg.callerName || callerId;
      const callId = msg.callId;

      setActiveCall({
        callId,
        peerId: callerId,
        peerName: callerName,
        isCaller: false,
        state: 'RINGING',
        durationSeconds: 0,
      });

      safeSetCallState('RINGING');

      // Send ringing acknowledgement back
      signaling.send({
        type: 'call-ringing',
        from: userId,
        to: callerId,
        callId,
      });

      // Trigger push/system notification
      notificationRef.current.showIncomingCall({
        callId,
        callerId,
        callerName,
        timestamp: Date.now(),
      });

      // Auto-timeout if not answered in 30s
      if (ringTimeoutRef.current) clearTimeout(ringTimeoutRef.current);
      ringTimeoutRef.current = window.setTimeout(() => {
        declineCall('No answer / Call timed out');
      }, CALL_CONFIG.RING_TIMEOUT_MS);
    });

    const unregCallRinging = signaling.on('call-ringing', () => {
      safeSetCallState('CALLING');
    });

    const unregCallAccepted = signaling.on('call-accepted', async (msg: SignalingMessage) => {
      if (!activeCall || msg.callId !== activeCall.callId) return;

      if (ringTimeoutRef.current) clearTimeout(ringTimeoutRef.current);
      safeSetCallState('CONNECTING');

      try {
        const offer = await webrtcRef.current?.createOffer();
        if (offer && offer.sdp) {
          signaling.send({
            type: 'offer',
            from: userId,
            to: activeCall.peerId,
            callId: activeCall.callId,
            sdp: offer.sdp,
          });
        }
      } catch (err: any) {
        setErrorMessage(`Failed to create WebRTC offer: ${err.message}`);
        hangUp();
      }
    });

    const unregOffer = signaling.on('offer', async (msg: SignalingMessage) => {
      if (!msg.sdp || !msg.callId) return;
      pendingOfferRef.current = msg.sdp;

      if (callState === 'CONNECTING') {
        try {
          const answer = await webrtcRef.current?.handleRemoteOffer(msg.sdp);
          if (answer && answer.sdp) {
            signaling.send({
              type: 'answer',
              from: userId,
              to: msg.from!,
              callId: msg.callId,
              sdp: answer.sdp,
            });
          }
        } catch (err: any) {
          setErrorMessage(`Failed to handle SDP offer: ${err.message}`);
          hangUp();
        }
      }
    });

    const unregAnswer = signaling.on('answer', async (msg: SignalingMessage) => {
      if (!msg.sdp) return;
      try {
        await webrtcRef.current?.handleRemoteAnswer(msg.sdp);
      } catch (err: any) {
        setErrorMessage(`Failed to process answer: ${err.message}`);
      }
    });

    const unregIceCandidate = signaling.on('ice-candidate', (msg: SignalingMessage) => {
      if (msg.candidate) {
        webrtcRef.current?.addIceCandidate(msg.candidate);
      }
    });

    const unregBusy = signaling.on('busy', (msg: SignalingMessage) => {
      setErrorMessage(msg.reason || 'User is currently on another call');
      safeSetCallState('DECLINED');
      setTimeout(() => resetCallState('Busy'), CALL_CONFIG.DISMISS_AUTO_MS);
    });

    const unregCallDeclined = signaling.on('call-declined', (msg: SignalingMessage) => {
      setErrorMessage(msg.reason || 'Call was declined by receiver');
      safeSetCallState('DECLINED');
      setTimeout(() => resetCallState('Declined'), CALL_CONFIG.DISMISS_AUTO_MS);
    });

    const unregCallEnded = signaling.on('call-ended', (msg: SignalingMessage) => {
      setErrorMessage(msg.reason || 'Call ended');
      safeSetCallState('DISCONNECTED');
      setTimeout(() => resetCallState('Ended'), CALL_CONFIG.DISMISS_AUTO_MS);
    });

    const unregError = signaling.on('error', (msg: SignalingMessage) => {
      setErrorMessage(msg.message || 'Call error occurred');
      if (callState !== 'IDLE') {
        safeSetCallState('FAILED');
        setTimeout(() => resetCallState(msg.message), CALL_CONFIG.DISMISS_AUTO_MS);
      }
    });

    return () => {
      unregRegistered();
      unregUserOnline();
      unregUserOffline();
      unregCallRequest();
      unregCallRinging();
      unregCallAccepted();
      unregOffer();
      unregAnswer();
      unregIceCandidate();
      unregBusy();
      unregCallDeclined();
      unregCallEnded();
      unregError();
      signaling.disconnect();
    };
  }, [userId, displayName, serverUrl, callState, activeCall, safeSetCallState, resetCallState]);

  // Start outgoing call
  const startCall = useCallback(
    async (targetUserId: string, targetUserName?: string) => {
      if (!targetUserId || targetUserId === userId) {
        setErrorMessage('Cannot call yourself or empty user');
        return;
      }

      if (callState !== 'IDLE') {
        setErrorMessage('Another call is already in progress');
        return;
      }

      try {
        // Pre-verify microphone access
        await webrtcRef.current?.acquireMicrophone();
      } catch (err: any) {
        setErrorMessage(err.message);
        return;
      }

      const callId = `CALL-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
      const peerName = targetUserName || targetUserId;

      setActiveCall({
        callId,
        peerId: targetUserId,
        peerName,
        isCaller: true,
        state: 'CALLING',
        durationSeconds: 0,
      });

      safeSetCallState('CALLING');

      signalingRef.current?.send({
        type: 'call-request',
        from: userId,
        to: targetUserId,
        callId,
        callerName: displayName,
      });

      // Outgoing call timeout (30 seconds)
      if (ringTimeoutRef.current) clearTimeout(ringTimeoutRef.current);
      ringTimeoutRef.current = window.setTimeout(() => {
        hangUp('No answer from user');
      }, CALL_CONFIG.RING_TIMEOUT_MS);
    },
    [userId, displayName, callState, safeSetCallState]
  );

  // Answer incoming call
  const answerCall = useCallback(async () => {
    if (!activeCall || callState !== 'RINGING') return;

    if (ringTimeoutRef.current) clearTimeout(ringTimeoutRef.current);
    notificationRef.current.cancelNotification(activeCall.callId);

    safeSetCallState('CONNECTING');

    try {
      await webrtcRef.current?.acquireMicrophone();

      signalingRef.current?.send({
        type: 'call-accepted',
        from: userId,
        to: activeCall.peerId,
        callId: activeCall.callId,
      });

      if (pendingOfferRef.current) {
        const answer = await webrtcRef.current?.handleRemoteOffer(pendingOfferRef.current);
        if (answer && answer.sdp) {
          signalingRef.current?.send({
            type: 'answer',
            from: userId,
            to: activeCall.peerId,
            callId: activeCall.callId,
            sdp: answer.sdp,
          });
        }
      }
    } catch (err: any) {
      setErrorMessage(`Failed to answer: ${err.message}`);
      declineCall('Microphone error');
    }
  }, [activeCall, callState, userId, safeSetCallState]);

  // Decline incoming call
  const declineCall = useCallback(
    (reason?: string) => {
      if (!activeCall) return;

      signalingRef.current?.send({
        type: 'call-declined',
        from: userId,
        to: activeCall.peerId,
        callId: activeCall.callId,
        reason: reason || 'Call declined',
      });

      safeSetCallState('DECLINED');
      setTimeout(() => resetCallState('Declined'), 1000);
    },
    [activeCall, userId, safeSetCallState, resetCallState]
  );

  // Hang up active call
  const hangUp = useCallback(
    (reason?: string) => {
      if (!activeCall) {
        resetCallState('Hangup on empty call');
        return;
      }

      signalingRef.current?.send({
        type: 'call-ended',
        from: userId,
        to: activeCall.peerId,
        callId: activeCall.callId,
        reason: reason || 'Call ended by user',
      });

      safeSetCallState('ENDING');
      setTimeout(() => resetCallState('Ended by user'), 500);
    },
    [activeCall, userId, safeSetCallState, resetCallState]
  );

  // Toggle Mute
  const toggleMute = useCallback(() => {
    if (webrtcRef.current) {
      const nextMuted = !isMuted;
      webrtcRef.current.setMute(nextMuted);
      setIsMuted(nextMuted);
    }
  }, [isMuted]);

  const clearError = useCallback(() => {
    setErrorMessage(null);
  }, []);

  return {
    isConnected,
    users,
    callState,
    activeCall,
    isMuted,
    errorMessage,
    connectionQuality,
    startCall,
    answerCall,
    declineCall,
    hangUp,
    toggleMute,
    clearError,
  };
}
