import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { isValidTransition, formatDuration } from '../../frontend/src/state/callState.js';

describe('CallState Lifecycle & Transitions', () => {
  it('Test 1: Caller starts call (IDLE -> CALLING)', () => {
    assert.equal(isValidTransition('IDLE', 'CALLING'), true);
  });

  it('Test 2: Receiver receives call (IDLE -> RINGING)', () => {
    assert.equal(isValidTransition('IDLE', 'RINGING'), true);
  });

  it('Test 3: Receiver accepts (RINGING -> CONNECTING)', () => {
    assert.equal(isValidTransition('RINGING', 'CONNECTING'), true);
  });

  it('Test 4: WebRTC connects (CONNECTING -> CONNECTED)', () => {
    assert.equal(isValidTransition('CONNECTING', 'CONNECTED'), true);
  });

  it('Test 5: Hangup (CONNECTED -> ENDING -> DISCONNECTED -> IDLE)', () => {
    assert.equal(isValidTransition('CONNECTED', 'ENDING'), true);
    assert.equal(isValidTransition('ENDING', 'DISCONNECTED'), true);
    assert.equal(isValidTransition('DISCONNECTED', 'IDLE'), true);
  });

  it('Test 6: Decline (RINGING -> DECLINED -> IDLE)', () => {
    assert.equal(isValidTransition('RINGING', 'DECLINED'), true);
    assert.equal(isValidTransition('DECLINED', 'IDLE'), true);
  });

  it('Test 7: Call Failure (CALLING -> FAILED -> IDLE)', () => {
    assert.equal(isValidTransition('CALLING', 'FAILED'), true);
    assert.equal(isValidTransition('FAILED', 'IDLE'), true);
  });

  it('Test 8: Block impossible state transitions', () => {
    // Cannot jump directly from IDLE to CONNECTED without signaling
    assert.equal(isValidTransition('IDLE', 'CONNECTED'), false);
    // Cannot jump from DECLINED to CONNECTED
    assert.equal(isValidTransition('DECLINED', 'CONNECTED'), false);
  });

  it('Test 9: Format duration timer accurately', () => {
    assert.equal(formatDuration(0), '00:00');
    assert.equal(formatDuration(37), '00:37');
    assert.equal(formatDuration(75), '01:15');
    assert.equal(formatDuration(3605), '60:05');
  });
});
