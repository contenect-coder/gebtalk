import { CallSession, CallState } from '../types/signaling.js';

export class CallManager {
  private calls: Map<string, CallSession> = new Map();
  private userToCallId: Map<string, string> = new Map();

  public createCall(callId: string, callerId: string, receiverId: string): CallSession {
    const session: CallSession = {
      callId,
      callerId,
      receiverId,
      state: 'CALLING',
      createdAt: Date.now(),
    };

    this.calls.set(callId, session);
    this.userToCallId.set(callerId, callId);
    this.userToCallId.set(receiverId, callId);

    return session;
  }

  public getCall(callId: string): CallSession | undefined {
    return this.calls.get(callId);
  }

  public getCallByUser(userId: string): CallSession | undefined {
    const callId = this.userToCallId.get(userId);
    return callId ? this.calls.get(callId) : undefined;
  }

  public isUserInCall(userId: string): boolean {
    const callId = this.userToCallId.get(userId);
    if (!callId) return false;
    const call = this.calls.get(callId);
    if (!call) return false;
    return ['CALLING', 'RINGING', 'CONNECTING', 'CONNECTED'].includes(call.state);
  }

  public updateCallState(callId: string, state: CallState): CallSession | null {
    const call = this.calls.get(callId);
    if (!call) return null;

    call.state = state;
    return call;
  }

  public endCall(callId: string): CallSession | null {
    const call = this.calls.get(callId);
    if (!call) return null;

    this.calls.delete(callId);
    this.userToCallId.delete(call.callerId);
    this.userToCallId.delete(call.receiverId);

    call.state = 'DISCONNECTED';
    return call;
  }

  public endCallByUser(userId: string): CallSession | null {
    const callId = this.userToCallId.get(userId);
    if (!callId) return null;
    return this.endCall(callId);
  }

  public getActiveCalls(): CallSession[] {
    return Array.from(this.calls.values());
  }
}
