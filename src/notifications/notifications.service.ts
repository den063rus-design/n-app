import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationType } from '@prisma/client';
import { NotificationsGateway } from './notifications.gateway';
import { PushService } from '../push/push.service';

@Injectable()
export class NotificationsService {
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
    const notification = await this.prisma.notification.create({
      data: {
        userId: data.userId,
        type: data.type as NotificationType,
        title: data.title,
        body: data.body,
        data: data.data ?? {},
      },
    });

    // Realtime-РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ РЎвЂЎР ВµРЎР‚Р ВµР В· WebSocket
    this.notificationsGateway.sendNotification(data.userId, notification);

    // Р С›Р В±Р Р…Р С•Р Р†Р В»РЎРЏР ВµР С unread count Р Т‘Р В»РЎРЏ Р С—Р С•Р В»РЎС“РЎвЂЎР В°РЎвЂљР ВµР В»РЎРЏ
    const unreadCount = await this.prisma.notification.count({
      where: { userId: data.userId, isRead: false },
    });
    this.notificationsGateway.sendUnreadCount(data.userId, unreadCount);

    // FCM push-РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ
    await this.sendFcmPush(data.userId, data);

    return notification;
  }

  private async sendFcmPush(
    userId: number,
    data: { type: 'MESSAGE' | 'CALL'; title: string; body?: string; data?: any },
  ) {
    try {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { fcmToken: true },
      });

      if (!user?.fcmToken) {
        return; // Р СњР ВµРЎвЂљ FCM token РІР‚вЂќ Р Р…Р С‘РЎвЂЎР ВµР С–Р С• Р Р…Р Вµ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµР С
      }

      const pushData: Record<string, string> = {
        type: data.type === 'MESSAGE' ? 'message' : 'call',
        userId: String(userId),
      };

      if (data.data) {
        if (data.data.messageId) pushData['messageId'] = String(data.data.messageId);
        if (data.data.senderId) pushData['senderId'] = String(data.data.senderId);
        if (data.data.senderName) pushData['senderName'] = String(data.data.senderName);
        if (data.data.callId) pushData['callId'] = String(data.data.callId);
        if (data.data.callerId) pushData['callerId'] = String(data.data.callerId);
        if (data.data.callerName) pushData['callerName'] = String(data.data.callerName);
      }

      await this.pushService.sendPush({
        token: user.fcmToken,
        title: data.title,
        body: data.body ?? '',
        data: pushData,
      });
    } catch (error) {
      // Р СњР Вµ Р Р†Р В°Р В»Р С‘Р С Р С•РЎРѓР Р…Р С•Р Р†Р Р…Р С•Р в„– flow
      console.error('FCM push error:', (error as Error).message);
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
    // Р РЋР Р…Р В°РЎвЂЎР В°Р В»Р В° Р С—Р С•Р В»РЎС“РЎвЂЎР В°Р ВµР С РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ, РЎвЂЎРЎвЂљР С•Р В±РЎвЂ№ РЎС“Р В·Р Р…Р В°РЎвЂљРЎРЉ userId
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

    // Realtime-Р С•Р В±Р Р…Р С•Р Р†Р В»Р ВµР Р…Р С‘Р Вµ unread count Р С—Р С•РЎРѓР В»Р Вµ Р С—РЎР‚Р С•РЎвЂЎРЎвЂљР ВµР Р…Р С‘РЎРЏ
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