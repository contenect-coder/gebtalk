import React from 'react';
import { Mic, MicOff, PhoneOff } from 'lucide-react';

interface CallControlsProps {
  isMuted: boolean;
  onToggleMute: () => void;
  onHangUp: () => void;
}

export const CallControls: React.FC<CallControlsProps> = ({
  isMuted,
  onToggleMute,
  onHangUp,
}) => {
  return (
    <div className="call-controls-container">
      <button
        className={`btn btn-circle btn-lg ${isMuted ? 'btn-warning active' : 'btn-glass'}`}
        onClick={onToggleMute}
        title={isMuted ? 'Unmute Microphone' : 'Mute Microphone'}
      >
        {isMuted ? <MicOff size={22} /> : <Mic size={22} />}
      </button>

      <button
        className="btn btn-danger btn-circle btn-lg btn-hangup"
        onClick={onHangUp}
        title="Hang Up"
      >
        <PhoneOff size={24} />
      </button>
    </div>
  );
};
