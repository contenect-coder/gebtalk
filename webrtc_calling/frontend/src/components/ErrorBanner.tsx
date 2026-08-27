import React from 'react';
import { AlertCircle, X } from 'lucide-react';

interface ErrorBannerProps {
  message: string | null;
  onDismiss: () => void;
}

export const ErrorBanner: React.FC<ErrorBannerProps> = ({ message, onDismiss }) => {
  if (!message) return null;

  return (
    <div className="error-banner">
      <div className="flex items-center gap-2">
        <AlertCircle size={18} className="text-rose-400 flex-shrink-0" />
        <span className="error-text">{message}</span>
      </div>
      <button className="error-dismiss-btn" onClick={onDismiss} title="Dismiss">
        <X size={16} />
      </button>
    </div>
  );
};
