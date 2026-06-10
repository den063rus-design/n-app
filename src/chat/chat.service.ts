import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateMessageDto } from './dto/create-message.dto';

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly messageSelect = {
    id: true,
    text: true,
    userId: true,
    isDeleted: true,
    createdAt: true,
    updatedAt: true,
  } as const;

  async create(dto: CreateMessageDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: dto.userId },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    return this.prisma.message.create({
      data: {
        text: dto.text,
        userId: dto.userId,
      },
      select: this.messageSelect,
    });
  }

  async findByUser(userId: number) {
    return this.prisma.message.findMany({
      where: { userId, isDeleted: false },
      orderBy: { createdAt: 'asc' },
      select: this.messageSelect,
    });
  }

  async findAll() {
    return this.prisma.message.findMany({
      where: { isDeleted: false },
      orderBy: { createdAt: 'asc' },
      select: {
        ...this.messageSelect,
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });
  }

  async remove(messageId: number, userId: number, userRole: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Сообщение не найдено');
    }

    // Только администратор может удалять сообщения
    if (userRole !== 'admin') {
      throw new ForbiddenException('Только администратор может удалять сообщения');
    }

    // Soft delete — помечаем как удалённое
    return this.prisma.message.update({
      where: { id: messageId },
      data: { isDeleted: true },
      select: this.messageSelect,
    });
  }
}