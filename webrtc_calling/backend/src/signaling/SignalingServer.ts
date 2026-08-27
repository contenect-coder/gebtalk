import { WebSocketServer, WebSocket } from 'ws';
import { Server as HttpServer } from 'http';
import { PresenceManager } from '../presence/PresenceManager.js';
import { CallManager } from '../calls/CallManager.js';
import { MessageRouter } from './MessageRouter.js';
import { SignalingMessage } from '../types/signaling.js';

interface ExtWebSocket extends WebSocket {
  isAlive?: boolean;
}

export class SignalingServer {
  private wss: WebSocketServer;
  private presence: PresenceManager;
  private callManager: CallManager;
  private router: MessageRouter;
  private heartbeatInterval?: NodeJS.Timeout;

  constructor(server: HttpServer) {
    this.presence = new PresenceManager();
    this.callManager = new CallManager();

    this.router = new MessageRouter(
      this.presence,
      this.callManager,
      (msg, excludeSocket) => this.broadcast(msg, excludeSocket)
    );

    this.wss = new WebSocketServer({ server });
    this.init();
  }

  private init(): void {
    this.wss.on('connection', (socket: ExtWebSocket) => {
      socket.isAlive = true;

      socket.on('pong', () => {
        socket.isAlive = true;
      });

      socket.on('message', (data: Buffer | string) => {
        const raw = typeof data === 'string' ? data : data.toString('utf-8');
        this.router.handleMessage(socket, raw);
      });

      socket.on('close', () => {
        this.router.handleDisconnect(socket);
      });

      socket.on('error', (err) => {
        console.error('[Signaling] WebSocket client error:', err);
      });
    });

    // Heartbeat ping-pong every 30 seconds
    this.heartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        const extWs = ws as ExtWebSocket;
        if (extWs.isAlive === false) {
          extWs.terminate();
          return;
        }
        extWs.isAlive = false;
        extWs.ping();
      });
    }, 30000);

    this.wss.on('close', () => {
      if (this.heartbeatInterval) {
        clearInterval(this.heartbeatInterval);
      }
    });

    console.log('[Signaling] WebSocket Signaling Server initialized');
  }

  public broadcast(message: SignalingMessage, excludeSocket?: WebSocket): void {
    const raw = JSON.stringify(message);
    this.wss.clients.forEach((client) => {
      if (client !== excludeSocket && client.readyState === WebSocket.OPEN) {
        try {
          client.send(raw);
        } catch (err) {
          console.error('[Signaling] Broadcast send error:', err);
        }
      }
    });
  }

  public getPresenceManager(): PresenceManager {
    return this.presence;
  }

  public getCallManager(): CallManager {
    return this.callManager;
  }

  public close(): Promise<void> {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    return new Promise((resolve) => {
      this.wss.close(() => resolve());
    });
  }
}
