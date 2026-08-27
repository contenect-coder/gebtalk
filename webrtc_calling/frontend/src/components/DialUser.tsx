import React, { useState } from 'react';
import { Phone, Sparkles } from 'lucide-react';

interface DialUserProps {
  onStartCall: (userId: string) => void;
  disabled: boolean;
}

export const DialUser: React.FC<DialUserProps> = ({ onStartCall, disabled }) => {
  const [targetId, setTargetId] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const clean = targetId.trim();
    if (clean) {
      onStartCall(clean);
    }
  };

  return (
    <div className="card dial-card">
      <div className="card-header">
        <div className="flex items-center gap-2">
          <Sparkles className="text-primary" size={18} />
          <h3>Direct Internet Call</h3>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="dial-form">
        <div className="input-group">
          <input
            type="text"
            className="input-text mono"
            placeholder="Enter peer User ID (e.g. bob, USR-8F2A91)"
            value={targetId}
            onChange={(e) => setTargetId(e.target.value)}
            disabled={disabled}
          />
          <button
            type="submit"
            className="btn btn-primary"
            disabled={disabled || !targetId.trim()}
          >
            <Phone size={16} />
            <span>Start Audio Call</span>
          </button>
        </div>
      </form>
    </div>
  );
};
