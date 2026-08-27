import { WebSocket } from 'ws';
import { UserPresence, UserStatus } from '../types/signaling.js';

export interface ConnectedUser {
  userId: string;
  displayName: string;
  status: UserStatus;
  socket: WebSocket;
  lastSeen: number;
}

export class PresenceManager {
  private users: Map<string, ConnectedUser> = new Map();
  private socketToUserId: Map<WebSocket, string> = new Map();

  public registerUser(userId: string, displayName: string, socket: WebSocket): UserPresence {
    const existing = this.users.get(userId);
    if (existing && existing.socket !== socket && existing.socket.readyState === WebSocket.OPEN) {
      try {
        existing.socket.close(4001, 'Replaced by new connection');
      } catch (_) {}
    }

    const now = Date.now();
    const cleanDisplayName = displayName.trim() || userId;
    const user: ConnectedUser = {
      userId,
      displayName: cleanDisplayName,
      status: 'online',
      socket,
      lastSeen: now,
    };

    this.users.set(userId, user);
    this.socketToUserId.set(socket, userId);

    return {
      userId: user.userId,
      displayName: user.displayName,
      status: user.status,
      lastSeen: user.lastSeen,
    };
  }

  public unregisterBySocket(socket: WebSocket): { userId: string; presence: UserPresence } | null {
    const userId = this.socketToUserId.get(socket);
    if (!userId) return null;

    this.socketToUserId.delete(socket);
    const user = this.users.get(userId);
    if (user && user.socket === socket) {
      this.users.delete(userId);
      return {
        userId,
        presence: {
          userId,
          displayName: user.displayName,
          status: 'offline',
          lastSeen: Date.now(),
        },
      };
    }
    return null;
  }

  public setUserStatus(userId: string, status: UserStatus): UserPresence | null {
    const user = this.users.get(userId);
    if (!user) return null;

    user.status = status;
    user.lastSeen = Date.now();

    return {
      userId: user.userId,
      displayName: user.displayName,
      status: user.status,
      lastSeen: user.lastSeen,
    };
  }

  public getUser(userId: string): ConnectedUser | undefined {
    return this.users.get(userId);
  }

  public getUserIdBySocket(socket: WebSocket): string | undefined {
    return this.socketToUserId.get(socket);
  }

  public getUserBySocket(socket: WebSocket): ConnectedUser | undefined {
    const userId = this.socketToUserId.get(socket);
    return userId ? this.users.get(userId) : undefined;
  }

  public isUserAvailable(userId: string): boolean {
    const user = this.users.get(userId);
    if (!user) return false;
    return user.status === 'online' && user.socket.readyState === WebSocket.OPEN;
  }

  public getAllUsers(excludeUserId?: string): UserPresence[] {
    const list: UserPresence[] = [];
    for (const [id, u] of this.users.entries()) {
      if (excludeUserId && id === excludeUserId) continue;
      list.push({
        userId: u.userId,
        displayName: u.displayName,
        status: u.status,
        lastSeen: u.lastSeen,
      });
    }
    return list;
  }

  public getSocket(userId: string): WebSocket | undefined {
    const user = this.users.get(userId);
    return user?.socket;
  }

  public getActiveCount(): number {
    return this.users.size;
  }
}
