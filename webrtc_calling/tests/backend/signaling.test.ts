import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { CallManager } from '../../backend/src/calls/CallManager.js';

describe('CallManager', () => {
  it('creates call sessions and tracks active participants', () => {
    const cm = new CallManager();
    const session = cm.createCall('call-123', 'alice', 'bob');

    assert.equal(session.callId, 'call-123');
    assert.equal(session.callerId, 'alice');
    assert.equal(session.receiverId, 'bob');
    assert.equal(session.state, 'CALLING');

    assert.equal(cm.isUserInCall('alice'), true);
    assert.equal(cm.isUserInCall('bob'), true);
    assert.equal(cm.isUserInCall('charlie'), false);
  });

  it('transitions call states correctly', () => {
    const cm = new CallManager();
    cm.createCall('call-123', 'alice', 'bob');

    cm.updateCallState('call-123', 'RINGING');
    assert.equal(cm.getCall('call-123')?.state, 'RINGING');

    cm.updateCallState('call-123', 'CONNECTED');
    assert.equal(cm.getCall('call-123')?.state, 'CONNECTED');
  });

  it('ends call sessions and frees user availability', () => {
    const cm = new CallManager();
    cm.createCall('call-123', 'alice', 'bob');

    cm.endCall('call-123');
    assert.equal(cm.getCall('call-123'), undefined);
    assert.equal(cm.isUserInCall('alice'), false);
    assert.equal(cm.isUserInCall('bob'), false);
  });
});
