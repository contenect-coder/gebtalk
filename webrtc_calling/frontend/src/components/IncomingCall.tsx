import React from 'react';
import { Phone, PhoneOff, Radio } from 'lucide-react';
import { CallSessionInfo } from '../types/calling.js';

interface IncomingCallProps {
  call: CallSessionInfo;
  onAnswer: () => void;
  onDecline: () => void;
}

export const IncomingCall: React.FC<IncomingCallProps> = ({ call, onAnswer, onDecline }) => {
  return (
    <div className="call-modal-overlay">
      <div className="call-modal-card incoming-glow animate-bounce-in">
        <div className="pulse-ring-container">
          <div className="pulse-ring pulse-green-1" />
          <div className="pulse-ring pulse-green-2" />
          <div className="avatar-large avatar-incoming">
            {call.peerName.charAt(0).toUpperCase()}
          </div>
        </div>

        <div className="call-target-meta">
          <div className="call-status-badge incoming-badge">
            <Radio size={14} className="icon-pulse text-emerald-400" />
            <span>Incoming Internet Audio Call</span>
          </div>
          <h2 className="call-target-name">{call.peerName}</h2>
          <span className="call-target-id">{call.peerId}</span>
        </div>

        <p className="call-subtitle">Peer-to-peer VoIP connection ready</p>

        <div className="call-actions-row">
          <button
            className="btn btn-danger btn-circle btn-lg"
            onClick={onDecline}
            title="Decline Call"
          >
            <PhoneOff size={24} />
          </button>

          <button
            className="btn btn-success btn-circle btn-lg"
            onClick={onAnswer}
            title="Answer Call"
          >
            <Phone size={24} />
          </button>
        </div>
      </div>
    </div>
  );
};
