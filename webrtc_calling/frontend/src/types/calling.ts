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

export type UserStatus = 'online' | 'offline' | 'busy' | 'calling';

export interface UserPresence {
  userId: string;
  displayName: string;
  status: UserStatus;
  lastSeen?: number;
}

export interface CallSessionInfo {
  callId: string;
  peerId: string;
  peerName: string;
  isCaller: boolean;
  state: CallState;
  startTime?: number;
  durationSeconds: number;
}

export interface SignalingMessage {
  type: string;
  from?: string;
  to?: string;
  callId?: string;
  userId?: string;
  displayName?: string;
  callerName?: string;
  users?: UserPresence[];
  user?: UserPresence;
  sdp?: string;
  candidate?: RTCIceCandidateInit;
  reason?: string;
  code?: string;
  message?: string;
  timestamp?: number;
}

export interface NotificationPayload {
  callId: string;
  callerId: string;
  callerName: string;
  timestamp: number;
}
