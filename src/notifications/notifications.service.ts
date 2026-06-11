import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationType } from '@prisma/client';
import { NotificationsGateway } from './notifications.gateway';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsGateway: NotificationsGateway,
  ) {}

  async createNotification(data: {
    userId: number;
    type: 'MESSAGE' | 'CALL';
    title: string;
    body?: string;
    data?: any;
  }) {
    const notification = await this.prisma.notification.create({
      data: {
        userId: data.userId,
        type: data.type as NotificationType,
        title: data.title,
        body: data.body,
        data: data.data ?? {},
      },
    });

    // Realtime-уведомление через WebSocket
    this.notificationsGateway.sendNotification(data.userId, notification);

    // Обновляем unread count для получателя
    const unreadCount = await this.prisma.notification.count({
      where: { userId: data.userId, isRead: false },
    });
    this.notificationsGateway.sendUnreadCount(data.userId, unreadCount);

    return notification;
  }

  async getUserNotifications(userId: number, page = 1, limit = 20) {
    const skip = (page - 1) * limit;

    const [notifications, total] = await Promise.all([
      this.prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.notification.count({
        where: { userId },
      }),
    ]);

    return {
      data: notifications,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  async markAsRead(notificationId: number) {
    // Сначала получаем уведомление, чтобы узнать userId
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
      select: { userId: true },
    });

    if (!notification) {
      return null;
    }

    const updated = await this.prisma.notification.update({
      where: { id: notificationId },
      data: { isRead: true },
    });

    // Realtime-обновление unread count после прочтения
    const unreadCount = await this.prisma.notification.count({
      where: { userId: notification.userId, isRead: false },
    });
    this.notificationsGateway.sendUnreadCount(notification.userId, unreadCount);

    return updated;
  }

  async markAllAsRead(userId: number) {
    await this.prisma.notification.updateMany({
      where: { userId, isRead: false },
      data: { isRead: true },
    });
  }

  async getUnreadCount(userId: number) {
    return this.prisma.notification.count({
      where: { userId, isRead: false },
    });
  }
}