import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Role, UserStatus } from '@prisma/client';
import { JwtService } from '@nestjs/jwt';
import { DefaultEventsMap, Server, Socket } from 'socket.io';
import { jwtConstants } from '../config/constants';
import { PrismaService } from '../prisma/prisma.service';
import { ChatService } from './chat.service';
import { CreateMessageDto } from './dto/create-message.dto';

type SocketUser = {
  id: number;
  role: Role;
  login: string;
  status: UserStatus;
};

type AuthedSocket = Socket<
  DefaultEventsMap,
  DefaultEventsMap,
  DefaultEventsMap,
  {
    user?: SocketUser;
  }
>;

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly userSockets = new Map<number, Set<string>>();

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly chatService: ChatService,
  ) {}

  async handleConnection(client: AuthedSocket) {
    const token = this.extractToken(client);

    if (!token) {
      client.disconnect(true);
      return;
    }

    try {
      const payload = await this.jwtService.verifyAsync<{
        sub: number;
        login: string;
        role: Role;
      }>(token, {
        secret: jwtConstants.secret,
      });

      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: {
          id: true,
          login: true,
          role: true,
          status: true,
        },
      });

      if (!user || user.status !== UserStatus.ACTIVE) {
        client.disconnect(true);
        return;
      }

      client.data.user = user;
      const firstConnection = this.addSocket(user.id, client.id);
      if (firstConnection) {
        this.server.emit('user:online', { userId: user.id, login: user.login });
      }
    } catch {
      client.disconnect(true);
    }
  }

  handleDisconnect(client: AuthedSocket) {
    const user = client.data.user;

    if (!user) {
      return;
    }

    this.removeSocket(user.id, client.id);
  }

  @SubscribeMessage('message:send')
  async handleSendMessage(client: AuthedSocket, payload: CreateMessageDto) {
    const user = client.data.user;

    if (!user) {
      client.disconnect(true);
      return;
    }

    const message = await this.chatService.createMessage(user.id, user.role, payload);
    this.emitToUser(message.senderId, 'message:new', message);
    this.emitToUser(message.receiverId, 'message:new', message);

    const receiverSockets = this.userSockets.get(message.receiverId);
    if (receiverSockets && receiverSockets.size > 0) {
      const deliveredMessage = await this.chatService.markDelivered(message.id);
      this.emitToUser(message.senderId, 'message:delivered', deliveredMessage);
      this.emitToUser(message.receiverId, 'message:delivered', deliveredMessage);
    }

    return message;
  }

  @SubscribeMessage('message:read')
  async handleReadMessage(client: AuthedSocket, payload: { messageId: number }) {
    const user = client.data.user;

    if (!user) {
      client.disconnect(true);
      return;
    }

    const message = await this.chatService.markRead(payload.messageId, user.id);
    this.emitToUser(message.senderId, 'message:read', message);
    this.emitToUser(message.receiverId, 'message:read', message);
    return message;
  }

  private extractToken(client: Socket) {
    const handshakeAuth = client.handshake.auth as { token?: unknown } | undefined;
    const authToken = handshakeAuth?.token;
    if (typeof authToken === 'string' && authToken.length > 0) {
      return authToken;
    }

    const header = client.handshake.headers.authorization;
    if (typeof header === 'string' && header.startsWith('Bearer ')) {
      return header.slice(7);
    }

    return null;
  }

  private addSocket(userId: number, socketId: string) {
    const sockets = this.userSockets.get(userId) ?? new Set<string>();
    const wasOffline = sockets.size === 0;
    sockets.add(socketId);
    this.userSockets.set(userId, sockets);
    return wasOffline;
  }

  private removeSocket(userId: number, socketId: string) {
    const sockets = this.userSockets.get(userId);
    if (!sockets) {
      return;
    }

    sockets.delete(socketId);

    if (sockets.size === 0) {
      this.userSockets.delete(userId);
      this.server.emit('user:offline', { userId });
    } else {
      this.userSockets.set(userId, sockets);
    }
  }

  private emitToUser(userId: number, event: string, data: unknown) {
    const sockets = this.userSockets.get(userId);

    if (!sockets) {
      return;
    }

    for (const socketId of sockets) {
      this.server.to(socketId).emit(event, data);
    }
  }
}
