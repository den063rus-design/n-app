import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { MessageStatus, Role, UserStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateMessageDto } from './dto/create-message.dto';

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly messageSelect = {
    id: true,
    senderId: true,
    receiverId: true,
    text: true,
    status: true,
    createdAt: true,
  } as const;

  async createMessage(senderId: number, senderRole: Role, dto: CreateMessageDto) {
    const sender = await this.prisma.user.findUnique({
      where: { id: senderId },
    });

    if (!sender || sender.status !== UserStatus.ACTIVE) {
      throw new ForbiddenException('Пользователь недоступен');
    }

    const receiver = await this.resolveReceiver(senderRole, dto.receiverId);

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

    return message;
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

  async markDelivered(messageId: number) {
    return this.updateStatus(messageId, MessageStatus.DELIVERED);
  }

  async markRead(messageId: number, readerId: number) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    if (message.receiverId !== readerId) {
      throw new ForbiddenException('Только получатель может отметить сообщение прочитанным');
    }

    return this.updateStatus(messageId, MessageStatus.READ);
  }

  async getMessageWithParticipants(messageId: number) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      select: {
        ...this.messageSelect,
        sender: {
          select: {
            id: true,
            login: true,
            role: true,
          },
        },
        receiver: {
          select: {
            id: true,
            login: true,
            role: true,
          },
        },
      },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    return message;
  }

  private async updateStatus(messageId: number, status: MessageStatus) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    return this.prisma.message.update({
      where: { id: messageId },
      data: { status },
      select: this.messageSelect,
    });
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
