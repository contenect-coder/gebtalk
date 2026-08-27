export type UserStatus = 'online' | 'offline' | 'busy' | 'calling';

export type CallState =
  | 'IDLE'
  | 'CALLING'
  | 'RINGING'
  | 'CONNECTING'
  | 'CONNECTED'
  | 'ENDING'
  | 'DISCONNECTED'
  | 'DECLINED'
  | 'FAILED';

export interface UserPresence {
  userId: string;
  displayName: string;
  status: UserStatus;
  lastSeen: number;
}

export interface CallSession {
  callId: string;
  callerId: string;
  receiverId: string;
  state: CallState;
  createdAt: number;
}

export interface BaseSignalingMessage {
  type: string;
  from?: string;
  to?: string;
  callId?: string;
  timestamp?: number;
}

export interface RegisterMessage extends BaseSignalingMessage {
  type: 'register';
  userId: string;
  displayName?: string;
}

export interface RegisteredMessage extends BaseSignalingMessage {
  type: 'registered';
  userId: string;
  displayName: string;
  users: UserPresence[];
}

export interface UsersListMessage extends BaseSignalingMessage {
  type: 'users';
  users: UserPresence[];
}

export interface UserOnlineMessage extends BaseSignalingMessage {
  type: 'user-online';
  user: UserPresence;
}

export interface UserOfflineMessage extends BaseSignalingMessage {
  type: 'user-offline';
  userId: string;
}

export interface CallRequestMessage extends BaseSignalingMessage {
  type: 'call-request';
  from: string;
  to: string;
  callId: string;
  callerName?: string;
}

export interface CallRingingMessage extends BaseSignalingMessage {
  type: 'call-ringing';
  from: string;
  to: string;
  callId: string;
}

export interface CallAcceptedMessage extends BaseSignalingMessage {
  type: 'call-accepted';
  from: string;
  to: string;
  callId: string;
}

export interface CallDeclinedMessage extends BaseSignalingMessage {
  type: 'call-declined';
  from: string;
  to: string;
  callId: string;
  reason?: string;
}

export interface CallEndedMessage extends BaseSignalingMessage {
  type: 'call-ended';
  from: string;
  to: string;
  callId: string;
  reason?: string;
}

export interface OfferMessage extends BaseSignalingMessage {
  type: 'offer';
  from: string;
  to: string;
  callId: string;
  sdp: string;
}

export interface AnswerMessage extends BaseSignalingMessage {
  type: 'answer';
  from: string;
  to: string;
  callId: string;
  sdp: string;
}

export interface IceCandidateMessage extends BaseSignalingMessage {
  type: 'ice-candidate';
  from: string;
  to: string;
  callId: string;
  candidate: {
    candidate: string;
    sdpMid?: string | null;
    sdpMLineIndex?: number | null;
    usernameFragment?: string | null;
  };
}

export interface BusyMessage extends BaseSignalingMessage {
  type: 'busy';
  from: string;
  to: string;
  callId?: string;
  reason?: string;
}

export interface ErrorMessage extends BaseSignalingMessage {
  type: 'error';
  code: string;
  message: string;
  callId?: string;
}

export interface PingMessage extends BaseSignalingMessage {
  type: 'ping';
}

export interface PongMessage extends BaseSignalingMessage {
  type: 'pong';
}

export type SignalingMessage =
  | RegisterMessage
  | RegisteredMessage
  | UsersListMessage
  | UserOnlineMessage
  | UserOfflineMessage
  | CallRequestMessage
  | CallRingingMessage
  | CallAcceptedMessage
  | CallDeclinedMessage
  | CallEndedMessage
  | OfferMessage
  | AnswerMessage
  | IceCandidateMessage
  | BusyMessage
  | ErrorMessage
  | PingMessage
  | PongMessage;
