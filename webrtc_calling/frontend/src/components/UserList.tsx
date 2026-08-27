import React from 'react';
import { UserPresence } from '../types/calling.js';
import { PhoneCall, Radio, User } from 'lucide-react';

interface UserListProps {
  users: UserPresence[];
  currentUserId: string;
  onCallUser: (userId: string, displayName: string) => void;
  disabled: boolean;
}

export const UserList: React.FC<UserListProps> = ({ users, currentUserId, onCallUser, disabled }) => {
  const filteredUsers = users.filter((u) => u.userId !== currentUserId);

  return (
    <div className="card user-list-card">
      <div className="card-header">
        <div className="flex items-center gap-2">
          <Radio className="icon-pulse text-accent" size={18} />
          <h3>Active Network Directory</h3>
        </div>
        <span className="badge badge-accent">{filteredUsers.length} Online</span>
      </div>

      <div className="user-items-container">
        {filteredUsers.length === 0 ? (
          <div className="empty-state">
            <User size={36} className="text-muted mb-2" />
            <p>No other active peers online right now.</p>
            <span className="text-xs text-muted">Open another browser window or invite a peer to call.</span>
          </div>
        ) : (
          filteredUsers.map((user) => {
            const isBusy = user.status === 'busy' || user.status === 'calling';
            return (
              <div key={user.userId} className="user-item">
                <div className="user-avatar-badge">
                  <div className="avatar-circle">
                    {user.displayName.charAt(0).toUpperCase()}
                  </div>
                  <span className={`status-indicator ${user.status}`} />
                </div>

                <div className="user-info">
                  <div className="user-name">{user.displayName}</div>
                  <div className="user-id-mono">{user.userId}</div>
                </div>

                <button
                  className={`btn btn-sm ${isBusy ? 'btn-outline' : 'btn-primary'}`}
                  disabled={disabled || isBusy}
                  onClick={() => onCallUser(user.userId, user.displayName)}
                >
                  <PhoneCall size={14} />
                  <span>{isBusy ? 'On Call' : 'Call'}</span>
                </button>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
