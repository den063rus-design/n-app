import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { MessageStatus, Role, UserStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChatGateway } from './chat.gateway';
import { CreateMessageDto } from './dto/create-message.dto';
import { ChatHistoryQueryDto } from './dto/chat-history-query.dto';

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly chatGateway: ChatGateway,
  ) {}

  private readonly messageSelect = {
    id: true,
    senderId: true,
    receiverId: true,
    text: true,
    status: true,
    createdAt: true,
    updatedAt: true,
    attachments: true,
  } as const;

  async create(dto: CreateMessageDto, senderId: number) {
    const sender = await this.prisma.user.findUnique({
      where: { id: senderId },
    });

    if (!sender || sender.status !== UserStatus.ACTIVE) {
      throw new ForbiddenException('Пользователь недоступен');
    }

    const receiver = await this.resolveReceiver(sender.role, dto.userId);

    if (sender.id === receiver.id) {
      throw new BadRequestException('Нельзя отправить сообщение самому себе');
    }

    this.assertAdminUserChat(sender.role, receiver.role);

    const message = await this.prisma.message.create({
      data: {
        senderId: sender.id,
        receiverId: receiver.id,
        text: dto.text,
        status: MessageStatus.SENT,
      },
      select: this.messageSelect,
    });

    // Эмитим событие через gateway
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:new',
      message,
    );

    return message;
  }

  async getHistory(
    userId: number,
    query: ChatHistoryQueryDto,
    currentUserId: number,
    currentUserRole: string,
  ) {
    // Если роль USER — проверяем, что userId === currentUserId
    if (currentUserRole !== 'ADMIN' && userId !== currentUserId) {
      throw new ForbiddenException('Доступ запрещён');
    }

    const page = query.page ?? 1;
    const limit = query.limit ?? 50;
    const skip = (page - 1) * limit;

    const where = {
      OR: [
        { senderId: userId, receiverId: currentUserId },
        { senderId: currentUserId, receiverId: userId },
      ] as Array<{ senderId: number; receiverId: number }>,
    };

    const [data, total] = await Promise.all([
      this.prisma.message.findMany({
        where,
        orderBy: { createdAt: 'asc' },
        skip,
        take: limit,
        select: this.messageSelect,
      }),
      this.prisma.message.count({ where }),
    ]);

    return { data, total, page, limit };
  }

  async findAll() {
    return this.prisma.message.findMany({
      orderBy: { createdAt: 'asc' },
      select: this.messageSelect,
    });
  }

  async findByUser(userId: number) {
    return this.prisma.message.findMany({
      where: {
        OR: [{ senderId: userId }, { receiverId: userId }],
      },
      orderBy: { createdAt: 'asc' },
      select: this.messageSelect,
    });
  }

  async deleteMessage(messageId: number, currentUserId: number, currentUserRole: string) {
    if (currentUserRole !== 'ADMIN') {
      throw new ForbiddenException('Только администратор может удалять сообщения');
    }

    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      select: {
        ...this.messageSelect,
        sender: { select: { id: true } },
        receiver: { select: { id: true } },
      },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    await this.prisma.message.delete({
      where: { id: messageId },
    });

    // Эмитим событие удаления обоим участникам
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:deleted',
      { messageId },
    );

    return {
      message: { senderId: message.senderId, receiverId: message.receiverId },
      response: { message: 'Сообщение удалено' },
    };
  }

  async markAsDelivered(messageId: number) {
    return this.updateStatus(messageId, MessageStatus.DELIVERED, 'message:delivered');
  }

  async markAsRead(messageId: number) {
    return this.updateStatus(messageId, MessageStatus.READ, 'message:read');
  }

  async remove(messageId: number, userId: number, userRole: string) {
    return this.deleteMessage(messageId, userId, userRole);
  }

  private async updateStatus(messageId: number, status: MessageStatus, event: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: { status },
      select: this.messageSelect,
    });

    // Эмитим событие обоим участникам
    this.chatGateway.sendToChatParticipants(updated.senderId, updated.receiverId, event, updated);

    return updated;
  }

  private async resolveReceiver(senderRole: Role, receiverId?: number) {
    if (senderRole === Role.ADMIN) {
      if (!receiverId) {
        throw new BadRequestException('Для администратора необходимо указать получателя');
      }

      const receiver = await this.prisma.user.findUnique({
        where: { id: receiverId },
      });

      if (!receiver) {
        throw new NotFoundException('Получатель не найден');
      }

      if (receiver.status !== UserStatus.ACTIVE) {
        throw new BadRequestException('Получатель недоступен');
      }

      return receiver;
    }

    const admin = await this.prisma.user.findFirst({
      where: {
        role: Role.ADMIN,
        status: UserStatus.ACTIVE,
      },
      orderBy: { createdAt: 'asc' },
    });

    if (!admin) {
      throw new NotFoundException('Активный администратор не найден');
    }

    return admin;
  }

  private assertAdminUserChat(senderRole: Role, receiverRole: Role) {
    const validPair =
      (senderRole === Role.ADMIN && receiverRole === Role.USER) ||
      (senderRole === Role.USER && receiverRole === Role.ADMIN);

    if (!validPair) {
      throw new BadRequestException('Чат доступен только между пользователем и администратором');
    }
  }
}
