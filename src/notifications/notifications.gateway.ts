import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';

@WebSocketGateway({
  cors: { origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000', credentials: true },
  namespace: '/',
})
export class NotificationsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private userSockets: Map<number, string> = new Map();

  constructor(private readonly jwtService: JwtService) {}

  handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        console.error('NotificationsGateway: connection rejected — no token provided');
        client.disconnect();
        return;
      }

      const payload = this.jwtService.verify<{ sub: number }>(token);
      const userId = payload.sub;

      if (userId) {
        this.userSockets.set(userId, client.id);
        console.log(`NotificationsGateway: user ${userId} connected`);
      }
    } catch (error) {
      console.error('NotificationsGateway: connection rejected — invalid token', error);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    for (const [userId, socketId] of this.userSockets.entries()) {
      if (socketId === client.id) {
        this.userSockets.delete(userId);
        console.log(`NotificationsGateway: user ${userId} disconnected`);
        break;
      }
    }
  }

  sendNotification(userId: number, notification: any) {
    const socketId = this.userSockets.get(userId);
    if (socketId) {
      this.server.to(socketId).emit('notification:new', notification);
    }
  }

  sendUnreadCount(userId: number, count: number) {
    const socketId = this.userSockets.get(userId);
    if (socketId) {
      this.server.to(socketId).emit('notification:unread_count', { count });
    }
  }
}