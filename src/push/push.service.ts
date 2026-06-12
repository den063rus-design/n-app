import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getMessaging, Message } from 'firebase-admin/messaging';

@Injectable()
export class PushService implements OnModuleInit {
  private readonly logger = new Logger(PushService.name);

  onModuleInit() {
    const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
    if (!serviceAccountPath) {
      this.logger.warn(
        'FIREBASE_SERVICE_ACCOUNT_PATH Р Р…Р Вµ Р В·Р В°Р Т‘Р В°Р Р…. FCM push-РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ Р С•РЎвЂљР С”Р В»РЎР‹РЎвЂЎР ВµР Р…РЎвЂ№.',
      );
      return;
    }

    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const serviceAccount = require(serviceAccountPath);
      initializeApp({
        credential: cert(serviceAccount),
      });
      this.logger.log('Firebase Admin Р С‘Р Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р С‘РЎР‚Р С•Р Р†Р В°Р Р… РЎС“РЎРѓР С—Р ВµРЎв‚¬Р Р…Р С•');
    } catch (error) {
      this.logger.error(
        `Р С›РЎв‚¬Р С‘Р В±Р С”Р В° Р С‘Р Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р В°РЎвЂ Р С‘Р С‘ Firebase Admin: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Р С›РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµРЎвЂљ push-РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ РЎвЂЎР ВµРЎР‚Р ВµР В· FCM.
   * Р СњР Вµ Р В±РЎР‚Р С•РЎРѓР В°Р ВµРЎвЂљ Р С‘РЎРѓР С”Р В»РЎР‹РЎвЂЎР ВµР Р…Р С‘Р в„– РІР‚вЂќ РЎвЂљР С•Р В»РЎРЉР С”Р С• Р В»Р С•Р С–Р С‘РЎР‚РЎС“Р ВµРЎвЂљ Р С•РЎв‚¬Р С‘Р В±Р С”Р С‘.
   */
  async sendPush(payload: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<void> {
    if (!getApps().length) {
      this.logger.warn('Firebase Admin Р Р…Р Вµ Р С‘Р Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р С‘РЎР‚Р С•Р Р†Р В°Р Р…. Push Р Р…Р Вµ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»Р ВµР Р….');
      return;
    }

    try {
      // Определяем тип уведомления для выбора Android-канала
      const isCall = payload.data?.type === 'call';

      const message: Message = {
        token: payload.token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: payload.data ?? {},
        android: {
          priority: 'high',
          notification: {
            channelId: isCall ? 'incoming_call_channel' : 'default_notification_channel',
            priority: isCall ? 'max' : 'high',
            defaultSound: true,
            defaultVibrateTimings: true,
            ...(isCall ? {
              notificationPriority: 'max',
              visibility: 'public',
              ticker: payload.title,
            } : {}),
          },
        },
      };

      const response = await getMessaging().send(message);
      this.logger.log(`FCM push Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»Р ВµР Р… РЎС“РЎРѓР С—Р ВµРЎв‚¬Р Р…Р С•: ${response}`);
    } catch (error) {
      this.logger.error(
        `Р С›РЎв‚¬Р С‘Р В±Р С”Р В° Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р С”Р С‘ FCM push: ${(error as Error).message}`,
      );
    }
  }
}