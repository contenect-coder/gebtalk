import React from 'react';
import { ShieldCheck, Activity } from 'lucide-react';
import { CallSessionInfo, CallState } from '../types/calling.js';
import { formatDuration } from '../state/callState.js';
import { CallControls } from './CallControls.js';

interface ActiveCallProps {
  call: CallSessionInfo;
  callState: CallState;
  isMuted: boolean;
  connectionQuality: string;
  onToggleMute: () => void;
  onHangUp: () => void;
}

export const ActiveCall: React.FC<ActiveCallProps> = ({
  call,
  callState,
  isMuted,
  connectionQuality,
  onToggleMute,
  onHangUp,
}) => {
  const isConnecting = callState === 'CONNECTING';

  return (
    <div className="call-modal-overlay">
      <div className="call-modal-card active-call-card">
        <div className="security-badge">
          <ShieldCheck size={14} className="text-emerald-400" />
          <span>WebRTC End-to-End Encrypted Audio</span>
        </div>

        <div className="active-call-avatar-wrap">
          <div className="avatar-large avatar-active">
            {call.peerName.charAt(0).toUpperCase()}
          </div>
          {isMuted && <span className="muted-tag">MUTED</span>}
        </div>

        <div className="call-target-meta">
          <h2 className="call-target-name">{call.peerName}</h2>
          <span className="call-target-id">{call.peerId}</span>
        </div>

        <div className="call-status-timer-box">
          {isConnecting ? (
            <div className="connecting-status">
              <Activity size={16} className="icon-spin text-accent" />
              <span>Establishing WebRTC Media Stream...</span>
            </div>
          ) : (
            <>
              <div className="call-timer-display">{formatDuration(call.durationSeconds)}</div>
              <div className="audio-wave-visualizer">
                <span className="bar bar-1" />
                <span className="bar bar-2" />
                <span className="bar bar-3" />
                <span className="bar bar-4" />
                <span className="bar bar-5" />
              </div>
              <span className="text-xs text-muted">Status: {connectionQuality}</span>
            </>
          )}
        </div>

        <CallControls
          isMuted={isMuted}
          onToggleMute={onToggleMute}
          onHangUp={onHangUp}
        />
      </div>
    </div>
  );
};
