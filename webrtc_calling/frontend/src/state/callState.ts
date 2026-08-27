import { CallState } from '../types/calling.js';

export const CALL_CONFIG = {
  RING_TIMEOUT_MS: 30000,
  WEBRTC_CONNECTION_TIMEOUT_MS: 20000,
  SIGNALING_HEARTBEAT_MS: 15000,
  RECONNECT_INTERVAL_MS: 3000,
  DISMISS_AUTO_MS: 3500,
};

const VALID_TRANSITIONS: Record<CallState, CallState[]> = {
  IDLE: ['CALLING', 'RINGING'],
  CALLING: ['CONNECTING', 'DECLINED', 'FAILED', 'DISCONNECTED', 'IDLE'],
  RINGING: ['CONNECTING', 'DECLINED', 'FAILED', 'DISCONNECTED', 'IDLE'],
  CONNECTING: ['CONNECTED', 'FAILED', 'DISCONNECTED', 'ENDING', 'IDLE'],
  CONNECTED: ['ENDING', 'DISCONNECTED', 'FAILED', 'IDLE'],
  ENDING: ['DISCONNECTED', 'IDLE'],
  DISCONNECTED: ['IDLE'],
  DECLINED: ['IDLE'],
  FAILED: ['IDLE'],
};

export function isValidTransition(current: CallState, next: CallState): boolean {
  if (current === next) return true;
  const allowed = VALID_TRANSITIONS[current] || [];
  return allowed.includes(next);
}

export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}
