import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationType } from '@prisma/client';
import { NotificationsGateway } from './notifications.gateway';
import { PushService } from '../push/push.service';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsGateway: NotificationsGateway,
    private readonly pushService: PushService,
  ) {}

  async createNotification(data: {
    userId: number;
    type: 'MESSAGE' | 'CALL';
    title: string;
    body?: string;
    data?: any;
  }) {
    this.logger.log(
      `[NOTIFICATIONS] CREATE_NOTIFICATION type=${data.type} userId=${data.userId} title="${data.title}" body="${data.body}"`,
    );

    const notification = await this.prisma.notification.create({
      data: {
        userId: data.userId,
        type: data.type as NotificationType,
        title: data.title,
        body: data.body,
        data: data.data ?? {},
      },
    });

    this.logger.log(
      `[NOTIFICATIONS] CREATE_NOTIFICATION done id=${notification.id} userId=${data.userId} type=${data.type}`,
    );

    // Realtime-уведомление через WebSocket
    this.notificationsGateway.sendNotification(data.userId, notification);

    // Обновляем unread count для пользователя
    const unreadCount = await this.prisma.notification.count({
      where: { userId: data.userId, isRead: false },
    });
    this.notificationsGateway.sendUnreadCount(data.userId, unreadCount);

    // FCM push-уведомление
    await this.sendFcmPush(data.userId, data);

    return notification;
  }

  private async sendFcmPush(
    userId: number,
    data: { type: 'MESSAGE' | 'CALL'; title: string; body?: string; data?: any },
  ) {
    try {
      this.logger.log(
        `[NOTIFICATIONS] SEND_FCM begin userId=${userId} type=${data.type}`,
      );

      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { fcmToken: true },
      });

      if (!user?.fcmToken) {
        this.logger.warn(
          `[NOTIFICATIONS] SEND_FCM missing token userId=${userId} — skipping FCM push`,
        );
        return;
      }

      const pushData: Record<string, string> = {
        type: data.type === 'MESSAGE' ? 'message' : 'call',
        userId: String(userId),
      };

      if (data.type === 'CALL') {
        const callId = data.data?.callId;
        const callerId = data.data?.callerId;
        const callerName = data.data?.callerName;

        if (!callId || !callerId || !callerName) {
          this.logger.warn(
            `[NOTIFICATIONS] SEND_FCM skipped because missing required call fields userId=${userId} callId=${callId} callerId=${callerId} callerName=${callerName}`,
          );
          return;
        }

        pushData['callId'] = String(callId);
        pushData['callerId'] = String(callerId);
        pushData['callerName'] = callerName;
      }

      if (data.data) {
        if (data.data.messageId) pushData['messageId'] = String(data.data.messageId);
        if (data.data.senderId) pushData['senderId'] = String(data.data.senderId);
        if (data.data.senderName) pushData['senderName'] = String(data.data.senderName);
      }

      this.logger.log(
        `[NOTIFICATIONS] SEND_FCM payload userId=${userId} type=${pushData['type']} callId=${pushData['callId']} callerId=${pushData['callerId']} callerName=${pushData['callerName']}`,
      );

      await this.pushService.sendPush({
        token: user.fcmToken,
        title: data.title,
        body: data.body ?? '',
        data: pushData,
      });

      this.logger.log(
        `[NOTIFICATIONS] SEND_FCM success userId=${userId}`,
      );
    } catch (error) {
      this.logger.error(
        `[NOTIFICATIONS] SEND_FCM failed userId=${userId} error=${error instanceof Error ? error.message : String(error)}`,
      );
    }
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