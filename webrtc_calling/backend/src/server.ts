import http from 'http';
import dotenv from 'dotenv';
import { SignalingServer } from './signaling/SignalingServer.js';

dotenv.config();

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';

const server = http.createServer((req, res) => {
  // CORS Headers for HTTP endpoints
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.url === '/health' || req.url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        status: 'ok',
        service: 'webrtc-signaling-server',
        timestamp: Date.now(),
        uptime: process.uptime(),
        activeUsers: signalingServer.getPresenceManager().getActiveCount(),
        activeCalls: signalingServer.getCallManager().getActiveCalls().length,
      })
    );
    return;
  }

  if (req.url === '/ice-config' || req.url === '/api/ice-config') {
    const stunUrls = (process.env.STUN_SERVER_URL || 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302')
      .split(',')
      .map((u) => u.trim());

    const iceServers: RTCIceServer[] = [
      {
        urls: stunUrls,
      },
    ];

    if (process.env.TURN_SERVER_URL) {
      iceServers.push({
        urls: process.env.TURN_SERVER_URL.split(',').map((u) => u.trim()),
        username: process.env.TURN_USERNAME || '',
        credential: process.env.TURN_CREDENTIAL || '',
      });
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ iceServers }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found' }));
});

const signalingServer = new SignalingServer(server);

server.listen(PORT, HOST, () => {
  console.log(`====================================================`);
  console.log(`🌐 WebRTC Signaling Server listening on http://${HOST}:${PORT}`);
  console.log(`📡 WebSocket endpoint ready at ws://${HOST}:${PORT}`);
  console.log(`🩺 Health check endpoint at http://${HOST}:${PORT}/health`);
  console.log(`🧊 ICE Config endpoint at http://${HOST}:${PORT}/ice-config`);
  console.log(`====================================================`);
});

export { server, signalingServer };
