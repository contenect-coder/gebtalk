import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import { WebSocket } from 'ws';
import { SignalingServer } from '../../backend/src/signaling/SignalingServer.js';

describe('End-to-End Dual-Client WebRTC Signaling Flow', () => {
  let server: http.Server;
  let signalingServer: SignalingServer;
  let serverPort: number;

  before(async () => {
    server = http.createServer();
    signalingServer = new SignalingServer(server);

    await new Promise<void>((resolve) => {
      server.listen(0, '127.0.0.1', () => {
        const addr = server.address() as any;
        serverPort = addr.port;
        resolve();
      });
    });
  });

  after(async () => {
    await signalingServer.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it('completes the full call lifecycle between Alice and Bob', async () => {
    const wsUrl = `ws://127.0.0.1:${serverPort}`;

    const clientA = new WebSocket(wsUrl);
    const clientB = new WebSocket(wsUrl);

    await Promise.all([
      new Promise((res) => clientA.on('open', res)),
      new Promise((res) => clientB.on('open', res)),
    ]);

    const messagesA: any[] = [];
    const messagesB: any[] = [];

    clientA.on('message', (d) => messagesA.push(JSON.parse(d.toString())));
    clientB.on('message', (d) => messagesB.push(JSON.parse(d.toString())));

    // Step 1: Register both clients
    clientA.send(JSON.stringify({ type: 'register', userId: 'alice', displayName: 'Alice' }));
    clientB.send(JSON.stringify({ type: 'register', userId: 'bob', displayName: 'Bob' }));

    await new Promise((r) => setTimeout(r, 100));

    assert.equal(signalingServer.getPresenceManager().isUserAvailable('alice'), true);
    assert.equal(signalingServer.getPresenceManager().isUserAvailable('bob'), true);

    // Step 2: Alice initiates call to Bob
    const callId = 'CALL-TEST-001';
    clientA.send(
      JSON.stringify({
        type: 'call-request',
        from: 'alice',
        to: 'bob',
        callId,
        callerName: 'Alice',
      })
    );

    await new Promise((r) => setTimeout(r, 100));

    const callReqB = messagesB.find((m) => m.type === 'call-request');
    assert.notEqual(callReqB, undefined);
    assert.equal(callReqB.from, 'alice');
    assert.equal(callReqB.callId, callId);

    // Step 3: Bob sends ringing & accepts
    clientB.send(JSON.stringify({ type: 'call-ringing', from: 'bob', to: 'alice', callId }));
    clientB.send(JSON.stringify({ type: 'call-accepted', from: 'bob', to: 'alice', callId }));

    await new Promise((r) => setTimeout(r, 100));

    const callAccA = messagesA.find((m) => m.type === 'call-accepted');
    assert.notEqual(callAccA, undefined);

    // Step 4: Alice sends WebRTC SDP Offer
    const fakeOfferSdp = 'v=0\r\no=alice 12345 2 IN IP4 127.0.0.1\r\ns=PureAudioCall\r\nt=0 0\r\n';
    clientA.send(
      JSON.stringify({
        type: 'offer',
        from: 'alice',
        to: 'bob',
        callId,
        sdp: fakeOfferSdp,
      })
    );

    await new Promise((r) => setTimeout(r, 100));

    const offerB = messagesB.find((m) => m.type === 'offer');
    assert.notEqual(offerB, undefined);
    assert.equal(offerB.sdp, fakeOfferSdp);

    // Step 5: Bob sends WebRTC SDP Answer
    const fakeAnswerSdp = 'v=0\r\no=bob 67890 2 IN IP4 127.0.0.1\r\ns=PureAudioCall\r\nt=0 0\r\n';
    clientB.send(
      JSON.stringify({
        type: 'answer',
        from: 'bob',
        to: 'alice',
        callId,
        sdp: fakeAnswerSdp,
      })
    );

    await new Promise((r) => setTimeout(r, 100));

    const answerA = messagesA.find((m) => m.type === 'answer');
    assert.notEqual(answerA, undefined);
    assert.equal(answerA.sdp, fakeAnswerSdp);

    // Step 6: ICE Candidate Exchange
    const fakeCandidate = { candidate: 'candidate:1 1 UDP 2130706431 127.0.0.1 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 };
    clientA.send(
      JSON.stringify({
        type: 'ice-candidate',
        from: 'alice',
        to: 'bob',
        callId,
        candidate: fakeCandidate,
      })
    );

    await new Promise((r) => setTimeout(r, 100));

    const iceB = messagesB.find((m) => m.type === 'ice-candidate');
    assert.notEqual(iceB, undefined);
    assert.equal(iceB.candidate.candidate, fakeCandidate.candidate);

    // Step 7: Alice hangs up
    clientA.send(
      JSON.stringify({
        type: 'call-ended',
        from: 'alice',
        to: 'bob',
        callId,
        reason: 'Call completed',
      })
    );

    await new Promise((r) => setTimeout(r, 100));

    const endedB = messagesB.find((m) => m.type === 'call-ended');
    assert.notEqual(endedB, undefined);
    assert.equal(endedB.reason, 'Call completed');

    // Verify both participants return to IDLE availability
    assert.equal(signalingServer.getPresenceManager().isUserAvailable('alice'), true);
    assert.equal(signalingServer.getPresenceManager().isUserAvailable('bob'), true);
    assert.equal(signalingServer.getCallManager().isUserInCall('alice'), false);

    clientA.close();
    clientB.close();
  });
});
