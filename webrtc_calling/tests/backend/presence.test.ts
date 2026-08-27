import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { PresenceManager } from '../../backend/src/presence/PresenceManager.js';
import { WebSocket } from 'ws';

describe('PresenceManager', () => {
  it('registers users and reports presence correctly', () => {
    const pm = new PresenceManager();
    const mockSocket = { readyState: WebSocket.OPEN } as any;

    const user = pm.registerUser('alice', 'Alice Smith', mockSocket);
    assert.equal(user.userId, 'alice');
    assert.equal(user.displayName, 'Alice Smith');
    assert.equal(user.status, 'online');

    assert.equal(pm.isUserAvailable('alice'), true);
    assert.equal(pm.getAllUsers().length, 1);
  });

  it('updates user status to busy when on a call', () => {
    const pm = new PresenceManager();
    const mockSocket = { readyState: WebSocket.OPEN } as any;

    pm.registerUser('bob', 'Bob Jones', mockSocket);
    assert.equal(pm.isUserAvailable('bob'), true);

    pm.setUserStatus('bob', 'busy');
    assert.equal(pm.isUserAvailable('bob'), false);

    pm.setUserStatus('bob', 'online');
    assert.equal(pm.isUserAvailable('bob'), true);
  });

  it('unregisters users cleanly on disconnect', () => {
    const pm = new PresenceManager();
    const mockSocket = { readyState: WebSocket.OPEN } as any;

    pm.registerUser('charlie', 'Charlie', mockSocket);
    assert.equal(pm.getActiveCount(), 1);

    const result = pm.unregisterBySocket(mockSocket);
    assert.notEqual(result, null);
    assert.equal(result?.userId, 'charlie');
    assert.equal(pm.getActiveCount(), 0);
  });
});
