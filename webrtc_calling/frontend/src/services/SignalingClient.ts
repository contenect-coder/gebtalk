import { SignalingMessage } from '../types/calling.js';

type MessageHandler = (msg: SignalingMessage) => void;

export class SignalingClient {
  private ws: WebSocket | null = null;
  private serverUrl: string;
  private userId: string = '';
  private displayName: string = '';
  private handlers: Map<string, Set<MessageHandler>> = new Map();
  private reconnectTimer?: number;
  private isExplicitDisconnect = false;
  private onConnectionChange?: (connected: boolean) => void;

  constructor(serverUrl: string) {
    this.serverUrl = serverUrl;
  }

  public connect(
    userId: string,
    displayName: string,
    onConnectionChange?: (connected: boolean) => void
  ): void {
    this.userId = userId;
    this.displayName = displayName || userId;
    this.isExplicitDisconnect = false;
    this.onConnectionChange = onConnectionChange;

    if (this.ws) {
      try {
        this.ws.close();
      } catch (_) {}
    }

    try {
      this.ws = new WebSocket(this.serverUrl);

      this.ws.onopen = () => {
        console.log('[SignalingClient] Connected to signaling server');
        this.onConnectionChange?.(true);

        // Register immediately on open
        this.send({
          type: 'register',
          userId: this.userId,
          displayName: this.displayName,
        });
      };

      this.ws.onmessage = (event) => {
        try {
          const msg: SignalingMessage = JSON.parse(event.data);
          this.emit(msg.type, msg);
          this.emit('*', msg);
        } catch (err) {
          console.error('[SignalingClient] Parse error:', err);
        }
      };

      this.ws.onclose = () => {
        console.warn('[SignalingClient] Disconnected from signaling server');
        this.onConnectionChange?.(false);
        if (!this.isExplicitDisconnect) {
          this.scheduleReconnect();
        }
      };

      this.ws.onerror = (err) => {
        console.error('[SignalingClient] WebSocket error:', err);
      };
    } catch (err) {
      console.error('[SignalingClient] Connection error:', err);
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = window.setTimeout(() => {
      if (!this.isExplicitDisconnect && this.userId) {
        console.log('[SignalingClient] Attempting reconnect...');
        this.connect(this.userId, this.displayName, this.onConnectionChange);
      }
    }, 3000);
  }

  public send(msg: SignalingMessage): boolean {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
      return true;
    }
    console.warn('[SignalingClient] Cannot send message, WebSocket not open:', msg);
    return false;
  }

  public on(type: string, handler: MessageHandler): () => void {
    if (!this.handlers.has(type)) {
      this.handlers.set(type, new Set());
    }
    this.handlers.get(type)!.add(handler);

    return () => {
      const set = this.handlers.get(type);
      if (set) {
        set.delete(handler);
      }
    };
  }

  private emit(type: string, msg: SignalingMessage): void {
    const set = this.handlers.get(type);
    if (set) {
      set.forEach((handler) => {
        try {
          handler(msg);
        } catch (err) {
          console.error(`[SignalingClient] Error in handler for ${type}:`, err);
        }
      });
    }
  }

  public isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  public disconnect(): void {
    this.isExplicitDisconnect = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.ws) {
      try {
        this.ws.close();
      } catch (_) {}
      this.ws = null;
    }
  }
}
