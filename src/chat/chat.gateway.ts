import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';

@WebSocketGateway({
  cors: { origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000', credentials: true },
  namespace: '/',
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private userSockets: Map<number, string> = new Map();

  handleConnection(client: Socket) {
    try {
      const userId = client.handshake.query.userId as string;
      if (userId) {
        this.userSockets.set(parseInt(userId, 10), client.id);
        console.log(`User ${userId} connected`);
      }
    } catch (error) {
      console.error('Connection error:', error);
    }
  }

  handleDisconnect(client: Socket) {
    for (const [userId, socketId] of this.userSockets.entries()) {
      if (socketId === client.id) {
        this.userSockets.delete(userId);
        console.log(`User ${userId} disconnected`);
        break;
      }
    }
  }

  // Отправить событие конкретному пользователю
  sendToUser(userId: number, event: string, data: unknown) {
    const socketId = this.userSockets.get(userId);
    if (socketId) {
      this.server.to(socketId).emit(event, data);
    }
  }

  // Отправить событие всем
  sendToAll(event: string, data: unknown) {
    this.server.emit(event, data);
  }

  // Отправить событие обоим участникам чата
  sendToChatParticipants(senderId: number, receiverId: number, event: string, data: unknown) {
    this.sendToUser(senderId, event, data);
    this.sendToUser(receiverId, event, data);
  }
}
