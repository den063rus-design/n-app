import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../users/users.service';
import { PrismaService } from '../prisma/prisma.service';

@WebSocketGateway({
  cors: { origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000', credentials: true },
  namespace: '/',
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private userSockets = new Map<number, Set<string>>();

  constructor(
    private readonly jwtService: JwtService,
    private readonly usersService: UsersService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(client: Socket) {
    try {
      // Читаем JWT токен из handshake.auth.token
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        console.error('Connection rejected: no token provided');
        client.disconnect();
        return;
      }

      // Валидируем токен
      const payload = this.jwtService.verify<{ sub: number }>(token);
      const userId = payload.sub;

      // Сохраняем сокет (поддержка множественных подключений)
      if (!this.userSockets.has(userId)) {
        this.userSockets.set(userId, new Set());
      }
      this.userSockets.get(userId)!.add(client.id);

      console.log(`User ${userId} connected via WebSocket (socket: ${client.id})`);

      // Обновляем статус на онлайн
      await this.usersService.updateOnlineStatus(userId, true);

      // Уведомляем всех о новом статусе
      client.broadcast.emit('user:online', { userId, isOnline: true });

      // Heartbeat — обновляем lastSeenAt
      client.on('heartbeat', () => {
        this.prisma.user.update({
          where: { id: userId },
          data: { lastSeenAt: new Date() },
        }).catch((err) => console.error('Heartbeat update error:', err));
      });

      // Обработка отключения
      client.on('disconnect', async () => {
        const sockets = this.userSockets.get(userId);
        if (sockets) {
          sockets.delete(client.id);
          if (sockets.size === 0) {
            this.userSockets.delete(userId);
            await this.usersService.updateOnlineStatus(userId, false);
            this.server.emit('user:offline', { userId, isOnline: false });
            console.log(`User ${userId} disconnected (all sockets closed)`);
          } else {
            console.log(`User ${userId} disconnected one socket (${sockets.size} remaining)`);
          }
        }
      });
    } catch (error) {
      console.error('Connection rejected: invalid token', error);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    // Логика disconnect теперь обрабатывается в client.on('disconnect') внутри handleConnection
    // Этот метод оставлен для совместимости с интерфейсом
  }

  // Отправить событие конкретному пользователю (всем его сокетам)
  sendToUser(userId: number, event: string, data: unknown) {
    const sockets = this.userSockets.get(userId);
    if (sockets) {
      for (const socketId of sockets) {
        this.server.to(socketId).emit(event, data);
      }
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
