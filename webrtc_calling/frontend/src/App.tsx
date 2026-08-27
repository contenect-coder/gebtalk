import React, { useState } from 'react';
import { useWebRTCCall } from './hooks/useWebRTCCall.js';
import { UserList } from './components/UserList.js';
import { DialUser } from './components/DialUser.js';
import { OutgoingCall } from './components/OutgoingCall.js';
import { IncomingCall } from './components/IncomingCall.js';
import { ActiveCall } from './components/ActiveCall.js';
import { ErrorBanner } from './components/ErrorBanner.js';
import { Phone, Shield, Wifi, UserCheck, RefreshCw, Settings, X, Check } from 'lucide-react';

const getInitialServerUrl = (): string => {
  const saved = localStorage.getItem('webrtc_calling_server_url');
  if (saved) return saved;

  const envUrl = (import.meta as any).env?.VITE_WS_SERVER_URL;
  if (envUrl) return envUrl;

  const host = window.location.hostname || 'localhost';
  if (window.location.protocol === 'https:') {
    return `wss://${host}:8080`;
  }
  return `ws://${host}:8080`;
};

export const App: React.FC = () => {
  const [serverUrl, setServerUrl] = useState<string>(getInitialServerUrl);
  const [isEditingServer, setIsEditingServer] = useState<boolean>(false);
  const [tempServerUrl, setTempServerUrl] = useState<string>(serverUrl);

  // Read User ID from query param or localStorage or generate random
  const [userId, setUserId] = useState<string>(() => {
    const params = new URLSearchParams(window.location.search);
    const queryUser = params.get('user');
    if (queryUser) return queryUser;

    const saved = localStorage.getItem('webrtc_calling_user_id');
    if (saved) return saved;

    const randomId = `user_${Math.random().toString(36).substring(2, 7)}`;
    localStorage.setItem('webrtc_calling_user_id', randomId);
    return randomId;
  });

  const [displayName, setDisplayName] = useState<string>(() => {
    return localStorage.getItem('webrtc_calling_display_name') || userId.toUpperCase();
  });

  const [isEditingProfile, setIsEditingProfile] = useState<boolean>(false);
  const [tempUserId, setTempUserId] = useState<string>(userId);
  const [tempDisplayName, setTempDisplayName] = useState<string>(displayName);

  const {
    isConnected,
    users,
    callState,
    activeCall,
    isMuted,
    errorMessage,
    connectionQuality,
    startCall,
    answerCall,
    declineCall,
    hangUp,
    toggleMute,
    clearError,
  } = useWebRTCCall({
    serverUrl,
    userId,
    displayName,
  });

  const handleSaveProfile = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanId = tempUserId.trim().toLowerCase();
    const cleanName = tempDisplayName.trim() || cleanId;
    if (cleanId) {
      setUserId(cleanId);
      setDisplayName(cleanName);
      localStorage.setItem('webrtc_calling_user_id', cleanId);
      localStorage.setItem('webrtc_calling_display_name', cleanName);
      setIsEditingProfile(false);
    }
  };

  const handleSaveServerUrl = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanUrl = tempServerUrl.trim();
    if (cleanUrl) {
      setServerUrl(cleanUrl);
      localStorage.setItem('webrtc_calling_server_url', cleanUrl);
      setIsEditingServer(false);
    }
  };

  const handleSwitchToDemoUser = (name: string) => {
    const clean = name.toLowerCase();
    setUserId(clean);
    setDisplayName(name);
    setTempUserId(clean);
    setTempDisplayName(name);
    localStorage.setItem('webrtc_calling_user_id', clean);
    localStorage.setItem('webrtc_calling_display_name', name);
  };

  const isCallingOrConnected =
    callState === 'CONNECTING' || callState === 'CONNECTED' || callState === 'ENDING';

  return (
    <div className="app-container">
      {/* Background glow effects */}
      <div className="bg-glow-orb bg-glow-1" />
      <div className="bg-glow-orb bg-glow-2" />

      {/* Top Navbar */}
      <header className="navbar">
        <div className="navbar-brand">
          <div className="brand-icon-wrap">
            <Phone size={22} className="text-primary" />
          </div>
          <div className="brand-text">
            <h1>GEBTALK <span className="brand-badge">VoIP</span></h1>
            <span className="brand-sub">Pure Internet WebRTC Audio Calling</span>
          </div>
        </div>

        <div className="navbar-status flex items-center gap-2">
          <div className={`status-pill ${isConnected ? 'status-online' : 'status-offline'}`}>
            <Wifi size={14} className={isConnected ? 'icon-pulse' : ''} />
            <span>{isConnected ? 'Signaling Online' : 'Connecting...'}</span>
          </div>

          <button
            className="btn btn-outline btn-sm"
            onClick={() => setIsEditingServer(true)}
            title="Configure Signaling Server URL"
          >
            <Settings size={14} />
            <span>Server</span>
          </button>
        </div>
      </header>

      {/* Server URL Settings Modal */}
      {isEditingServer && (
        <div className="call-modal-overlay">
          <div className="call-modal-card" style={{ maxWidth: '480px', textAlign: 'left' }}>
            <div className="flex justify-between items-center mb-3">
              <div className="flex items-center gap-2">
                <Settings size={18} className="text-primary" />
                <h3 style={{ color: '#fff', fontSize: '1.1rem' }}>Signaling Server Connection</h3>
              </div>
              <button
                className="error-dismiss-btn"
                onClick={() => setIsEditingServer(false)}
                title="Close"
              >
                <X size={18} />
              </button>
            </div>

            <p className="text-muted text-xs mb-3">
              Configure the WebSocket signaling endpoint used for real-time peer discovery and WebRTC session negotiation.
            </p>

            <form onSubmit={handleSaveServerUrl}>
              <label className="form-label">WebSocket Server URL</label>
              <input
                type="text"
                className="input-text mono mb-3"
                value={tempServerUrl}
                onChange={(e) => setTempServerUrl(e.target.value)}
                placeholder="ws://localhost:8080 or wss://..."
                required
              />

              <div className="flex gap-2 justify-end mt-3">
                <button
                  type="button"
                  className="btn btn-outline btn-sm"
                  onClick={() => setIsEditingServer(false)}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary btn-sm">
                  <Check size={14} />
                  <span>Save & Reconnect</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Main Content Area */}
      <main className="main-content">
        <ErrorBanner message={errorMessage} onDismiss={clearError} />

        {/* User Identity Card */}
        <section className="card user-profile-card">
          <div className="profile-content">
            <div className="avatar-circle avatar-me">
              {displayName.charAt(0).toUpperCase()}
            </div>

            <div className="profile-details">
              <div className="flex items-center gap-2">
                <h2 className="profile-name">{displayName}</h2>
                <span className="badge badge-success">My Profile</span>
              </div>
              <div className="profile-id-row">
                <span className="text-muted">User ID:</span>
                <span className="user-id-mono">{userId}</span>
              </div>
            </div>

            <div className="profile-actions">
              <button
                className="btn btn-outline btn-sm"
                onClick={() => setIsEditingProfile(!isEditingProfile)}
              >
                <UserCheck size={14} />
                <span>{isEditingProfile ? 'Cancel' : 'Change ID'}</span>
              </button>
            </div>
          </div>

          {/* Quick User Switcher for Local Testing */}
          <div className="demo-users-bar">
            <span className="text-xs text-muted">Quick Test Identities:</span>
            <div className="demo-buttons">
              <button
                className={`btn-tag ${userId === 'alice' ? 'active' : ''}`}
                onClick={() => handleSwitchToDemoUser('Alice')}
              >
                Alice
              </button>
              <button
                className={`btn-tag ${userId === 'bob' ? 'active' : ''}`}
                onClick={() => handleSwitchToDemoUser('Bob')}
              >
                Bob
              </button>
              <button
                className={`btn-tag ${userId === 'frank' ? 'active' : ''}`}
                onClick={() => handleSwitchToDemoUser('Frank')}
              >
                Frank (Staff)
              </button>
              <button
                className={`btn-tag ${userId === 'test01' ? 'active' : ''}`}
                onClick={() => handleSwitchToDemoUser('Test01')}
              >
                Test01 (Customer)
              </button>
              <button
                className={`btn-tag ${userId === 'ernest_ceo' ? 'active' : ''}`}
                onClick={() => handleSwitchToDemoUser('Ernest_CEO')}
              >
                Ernest_CEO
              </button>
            </div>
          </div>

          {isEditingProfile && (
            <form onSubmit={handleSaveProfile} className="profile-edit-form">
              <div className="form-grid">
                <div>
                  <label className="form-label">User ID (Moniker)</label>
                  <input
                    type="text"
                    className="input-text mono"
                    value={tempUserId}
                    onChange={(e) => setTempUserId(e.target.value)}
                    placeholder="e.g. alice, bob, USR-001"
                    required
                  />
                </div>
                <div>
                  <label className="form-label">Display Name</label>
                  <input
                    type="text"
                    className="input-text"
                    value={tempDisplayName}
                    onChange={(e) => setTempDisplayName(e.target.value)}
                    placeholder="e.g. Alice Smith"
                  />
                </div>
              </div>
              <button type="submit" className="btn btn-primary btn-sm mt-3">
                <RefreshCw size={14} />
                <span>Apply Identity & Reconnect</span>
              </button>
            </form>
          )}
        </section>

        {/* Calling Interface Grid */}
        <div className="calling-grid">
          <DialUser
            onStartCall={(targetId) => startCall(targetId)}
            disabled={!isConnected || callState !== 'IDLE'}
          />

          <UserList
            users={users}
            currentUserId={userId}
            onCallUser={(targetId, targetName) => startCall(targetId, targetName)}
            disabled={!isConnected || callState !== 'IDLE'}
          />
        </div>

        {/* Feature & Security Banner */}
        <section className="card feature-specs-card">
          <div className="flex items-center gap-2 mb-2">
            <Shield size={18} className="text-emerald-400" />
            <h3>Pure Internet Calling Architecture</h3>
          </div>
          <p className="text-muted text-sm leading-relaxed">
            This MVP transmits encrypted real-time audio peer-to-peer using <strong>WebRTC (Opus audio codec)</strong> and <strong>WebSocket signaling</strong>. No phone numbers, PSTN telephone networks, SMS verification, or paid telecom SDKs are used.
          </p>
        </section>
      </main>

      {/* Call Modals based on State Machine */}
      {callState === 'CALLING' && activeCall && (
        <OutgoingCall call={activeCall} onCancel={() => hangUp('Cancelled by caller')} />
      )}

      {callState === 'RINGING' && activeCall && (
        <IncomingCall
          call={activeCall}
          onAnswer={answerCall}
          onDecline={() => declineCall('Declined by user')}
        />
      )}

      {isCallingOrConnected && activeCall && (
        <ActiveCall
          call={activeCall}
          callState={callState}
          isMuted={isMuted}
          connectionQuality={connectionQuality}
          onToggleMute={toggleMute}
          onHangUp={() => hangUp('Ended by user')}
        />
      )}
    </div>
  );
};
