import React from 'react';
import { PhoneOff, Wifi } from 'lucide-react';
import { CallSessionInfo } from '../types/calling.js';

interface OutgoingCallProps {
  call: CallSessionInfo;
  onCancel: () => void;
}

export const OutgoingCall: React.FC<OutgoingCallProps> = ({ call, onCancel }) => {
  return (
    <div className="call-modal-overlay">
      <div className="call-modal-card outgoing-glow">
        <div className="pulse-ring-container">
          <div className="pulse-ring pulse-1" />
          <div className="pulse-ring pulse-2" />
          <div className="avatar-large avatar-outgoing">
            {call.peerName.charAt(0).toUpperCase()}
          </div>
        </div>

        <div className="call-target-meta">
          <div className="call-status-badge">
            <Wifi size={14} className="icon-pulse text-accent" />
            <span>Calling...</span>
          </div>
          <h2 className="call-target-name">{call.peerName}</h2>
          <span className="call-target-id">{call.peerId}</span>
        </div>

        <p className="call-subtitle">Ringing recipient over secure peer-to-peer WebRTC...</p>

        <div className="call-actions">
          <button className="btn btn-danger btn-circle btn-lg" onClick={onCancel} title="Cancel Call">
            <PhoneOff size={24} />
          </button>
        </div>
      </div>
    </div>
  );
};
