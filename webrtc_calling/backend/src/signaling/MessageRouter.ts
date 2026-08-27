import { WebSocket } from 'ws';
import { PresenceManager } from '../presence/PresenceManager.js';
import { CallManager } from '../calls/CallManager.js';
import {
  SignalingMessage,
  RegisterMessage,
  CallRequestMessage,
  CallRingingMessage,
  CallAcceptedMessage,
  CallDeclinedMessage,
  CallEndedMessage,
  OfferMessage,
  AnswerMessage,
  IceCandidateMessage,
  ErrorMessage,
  BusyMessage,
} from '../types/signaling.js';

export class MessageRouter {
  constructor(
    private presence: PresenceManager,
    private callManager: CallManager,
    private broadcastCallback: (message: SignalingMessage, excludeSocket?: WebSocket) => void
  ) {}

  public sendToSocket(socket: WebSocket, message: SignalingMessage): boolean {
    if (socket.readyState === WebSocket.OPEN) {
      try {
        socket.send(JSON.stringify(message));
        return true;
      } catch (err) {
        console.error('[Signaling] Error sending message to socket:', err);
      }
    }
    return false;
  }

  public sendToUser(userId: string, message: SignalingMessage): boolean {
    const socket = this.presence.getSocket(userId);
    if (socket) {
      return this.sendToSocket(socket, message);
    }
    return false;
  }

  public handleMessage(socket: WebSocket, rawData: string): void {
    let message: SignalingMessage;
    try {
      message = JSON.parse(rawData);
    } catch (err) {
      this.sendError(socket, 'INVALID_JSON', 'Malformed JSON payload');
      return;
    }

    if (!message || typeof message.type !== 'string') {
      this.sendError(socket, 'INVALID_MESSAGE', 'Missing message type');
      return;
    }

    const authenticatedUserId = this.presence.getUserIdBySocket(socket);

    // If message is not 'register' or 'ping', socket must be registered
    if (message.type !== 'register' && message.type !== 'ping') {
      if (!authenticatedUserId) {
        this.sendError(socket, 'UNAUTHORIZED', 'Socket must be registered before sending signaling messages');
        return;
      }

      // Prevent impersonation: verify 'from' matches authenticated user
      if (message.from && message.from !== authenticatedUserId) {
        this.sendError(socket, 'FORBIDDEN', `Cannot send message as user "${message.from}"`);
        return;
      }
    }

    switch (message.type) {
      case 'ping':
        this.sendToSocket(socket, { type: 'pong', timestamp: Date.now() });
        break;

      case 'register':
        this.handleRegister(socket, message as RegisterMessage);
        break;

      case 'call-request':
        this.handleCallRequest(socket, authenticatedUserId!, message as CallRequestMessage);
        break;

      case 'call-ringing':
        this.handleCallRinging(socket, authenticatedUserId!, message as CallRingingMessage);
        break;

      case 'call-accepted':
        this.handleCallAccepted(socket, authenticatedUserId!, message as CallAcceptedMessage);
        break;

      case 'call-declined':
        this.handleCallDeclined(socket, authenticatedUserId!, message as CallDeclinedMessage);
        break;

      case 'call-ended':
        this.handleCallEnded(socket, authenticatedUserId!, message as CallEndedMessage);
        break;

      case 'offer':
        this.handleOffer(socket, authenticatedUserId!, message as OfferMessage);
        break;

      case 'answer':
        this.handleAnswer(socket, authenticatedUserId!, message as AnswerMessage);
        break;

      case 'ice-candidate':
        this.handleIceCandidate(socket, authenticatedUserId!, message as IceCandidateMessage);
        break;

      default:
        this.sendError(socket, 'UNKNOWN_TYPE', `Unknown message type: ${(message as any).type}`);
        break;
    }
  }

  private handleRegister(socket: WebSocket, msg: RegisterMessage): void {
    const userId = (msg.userId || '').trim();
    if (!userId || userId.length < 2) {
      this.sendError(socket, 'INVALID_USER_ID', 'User ID must be at least 2 characters');
      return;
    }

    const displayName = (msg.displayName || userId).trim();
    const presence = this.presence.registerUser(userId, displayName, socket);

    console.log(`[Signaling] Registered user: ${userId} (${displayName})`);

    // Send confirmation and current user list to registrant
    const allUsers = this.presence.getAllUsers(userId);
    this.sendToSocket(socket, {
      type: 'registered',
      userId: presence.userId,
      displayName: presence.displayName,
      users: allUsers,
      timestamp: Date.now(),
    });

    // Broadcast user-online event to all other clients
    this.broadcastCallback(
      {
        type: 'user-online',
        user: presence,
        timestamp: Date.now(),
      },
      socket
    );
  }

  private handleCallRequest(socket: WebSocket, callerId: string, msg: CallRequestMessage): void {
    const receiverId = (msg.to || '').trim();
    const callId = (msg.callId || '').trim();

    if (!receiverId || !callId) {
      this.sendError(socket, 'INVALID_CALL_REQUEST', 'Recipient and Call ID required', callId);
      return;
    }

    if (callerId === receiverId) {
      this.sendError(socket, 'SELF_CALL', 'Cannot call yourself', callId);
      return;
    }

    // Check receiver presence
    const receiver = this.presence.getUser(receiverId);
    if (!receiver || receiver.socket.readyState !== WebSocket.OPEN) {
      this.sendToSocket(socket, {
        type: 'error',
        code: 'USER_OFFLINE',
        message: `User ${receiverId} is offline`,
        callId,
      });
      return;
    }

    // Check if receiver or caller is busy
    if (this.callManager.isUserInCall(receiverId) || receiver.status === 'busy' || receiver.status === 'calling') {
      const busyMsg: BusyMessage = {
        type: 'busy',
        from: receiverId,
        to: callerId,
        callId,
        reason: 'User is currently on another call',
      };
      this.sendToSocket(socket, busyMsg);
      return;
    }

    if (this.callManager.isUserInCall(callerId)) {
      this.sendError(socket, 'ALREADY_IN_CALL', 'You are already in an active call session', callId);
      return;
    }

    // Create Call Session
    this.callManager.createCall(callId, callerId, receiverId);
    this.presence.setUserStatus(callerId, 'calling');
    this.presence.setUserStatus(receiverId, 'calling');

    const callerProfile = this.presence.getUser(callerId);
    const callerName = callerProfile?.displayName || callerId;

    // Route call-request to receiver
    this.sendToSocket(receiver.socket, {
      type: 'call-request',
      from: callerId,
      to: receiverId,
      callId,
      callerName,
      timestamp: Date.now(),
    });

    console.log(`[Call] Outgoing call initiated: ${callerId} -> ${receiverId} (Call ID: ${callId})`);
  }

  private handleCallRinging(socket: WebSocket, receiverId: string, msg: CallRingingMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call || call.receiverId !== receiverId) return;

    this.callManager.updateCallState(msg.callId, 'RINGING');
    this.sendToUser(call.callerId, {
      type: 'call-ringing',
      from: receiverId,
      to: call.callerId,
      callId: msg.callId,
      timestamp: Date.now(),
    });
  }

  private handleCallAccepted(socket: WebSocket, receiverId: string, msg: CallAcceptedMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call || call.receiverId !== receiverId) return;

    this.callManager.updateCallState(msg.callId, 'CONNECTING');
    this.presence.setUserStatus(call.callerId, 'busy');
    this.presence.setUserStatus(call.receiverId, 'busy');

    this.sendToUser(call.callerId, {
      type: 'call-accepted',
      from: receiverId,
      to: call.callerId,
      callId: msg.callId,
      timestamp: Date.now(),
    });

    console.log(`[Call] Call accepted: ${msg.callId}`);
  }

  private handleCallDeclined(socket: WebSocket, receiverId: string, msg: CallDeclinedMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call || call.receiverId !== receiverId) return;

    this.callManager.endCall(msg.callId);
    this.presence.setUserStatus(call.callerId, 'online');
    this.presence.setUserStatus(call.receiverId, 'online');

    this.sendToUser(call.callerId, {
      type: 'call-declined',
      from: receiverId,
      to: call.callerId,
      callId: msg.callId,
      reason: msg.reason || 'Call was declined by receiver',
      timestamp: Date.now(),
    });

    console.log(`[Call] Call declined: ${msg.callId}`);
  }

  private handleCallEnded(socket: WebSocket, userId: string, msg: CallEndedMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call) return;

    const peerId = call.callerId === userId ? call.receiverId : call.callerId;

    this.callManager.endCall(msg.callId);
    this.presence.setUserStatus(call.callerId, 'online');
    this.presence.setUserStatus(call.receiverId, 'online');

    this.sendToUser(peerId, {
      type: 'call-ended',
      from: userId,
      to: peerId,
      callId: msg.callId,
      reason: msg.reason || 'Call ended by peer',
      timestamp: Date.now(),
    });

    console.log(`[Call] Call ended: ${msg.callId} by ${userId}`);
  }

  private handleOffer(socket: WebSocket, senderId: string, msg: OfferMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call) {
      this.sendError(socket, 'CALL_NOT_FOUND', 'Call session not found', msg.callId);
      return;
    }

    const recipientId = msg.to || (call.callerId === senderId ? call.receiverId : call.callerId);
    this.sendToUser(recipientId, {
      type: 'offer',
      from: senderId,
      to: recipientId,
      callId: msg.callId,
      sdp: msg.sdp,
      timestamp: Date.now(),
    });
  }

  private handleAnswer(socket: WebSocket, senderId: string, msg: AnswerMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call) {
      this.sendError(socket, 'CALL_NOT_FOUND', 'Call session not found', msg.callId);
      return;
    }

    const recipientId = msg.to || (call.callerId === senderId ? call.receiverId : call.callerId);
    this.callManager.updateCallState(msg.callId, 'CONNECTED');

    this.sendToUser(recipientId, {
      type: 'answer',
      from: senderId,
      to: recipientId,
      callId: msg.callId,
      sdp: msg.sdp,
      timestamp: Date.now(),
    });
  }

  private handleIceCandidate(socket: WebSocket, senderId: string, msg: IceCandidateMessage): void {
    const call = this.callManager.getCall(msg.callId);
    if (!call) return;

    const recipientId = msg.to || (call.callerId === senderId ? call.receiverId : call.callerId);
    this.sendToUser(recipientId, {
      type: 'ice-candidate',
      from: senderId,
      to: recipientId,
      callId: msg.callId,
      candidate: msg.candidate,
      timestamp: Date.now(),
    });
  }

  public handleDisconnect(socket: WebSocket): void {
    const result = this.presence.unregisterBySocket(socket);
    if (!result) return;

    const { userId } = result;
    console.log(`[Signaling] User disconnected: ${userId}`);

    // If user was in a call, notify peer and end call session
    const activeCall = this.callManager.endCallByUser(userId);
    if (activeCall) {
      const peerId = activeCall.callerId === userId ? activeCall.receiverId : activeCall.callerId;
      this.presence.setUserStatus(peerId, 'online');
      this.sendToUser(peerId, {
        type: 'call-ended',
        from: userId,
        to: peerId,
        callId: activeCall.callId,
        reason: 'Peer disconnected from signaling server',
        timestamp: Date.now(),
      });
    }

    // Broadcast user-offline event
    this.broadcastCallback({
      type: 'user-offline',
      userId,
      timestamp: Date.now(),
    });
  }

  private sendError(socket: WebSocket, code: string, message: string, callId?: string): void {
    const errorMsg: ErrorMessage = {
      type: 'error',
      code,
      message,
      callId,
      timestamp: Date.now(),
    };
    this.sendToSocket(socket, errorMsg);
  }
}
