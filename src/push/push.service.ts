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
        'FIREBASE_SERVICE_ACCOUNT_PATH is not set. FCM push notifications will be disabled.',
      );
      return;
    }

    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const serviceAccount = require(serviceAccountPath);
      initializeApp({
        credential: cert(serviceAccount),
      });
      this.logger.log('Firebase Admin initialized successfully');
    } catch (error) {
      this.logger.error(
        `Error initializing Firebase Admin: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Sends a push notification via FCM.
   * Does not throw — errors are logged only.
   */
  async sendPush(payload: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<void> {
    if (!getApps().length) {
      this.logger.warn('Firebase Admin is not initialized. Push not sent.');
      return;
    }

    try {
      // Determine notification type for Android channel selection
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
            ...(isCall
              ? {
                  notificationPriority: 'max',
                  visibility: 'public',
                  ticker: payload.title,
                }
              : {}),
          },
        },
      };

      const response = await getMessaging().send(message);
      this.logger.log(
        `[PUSH_SERVICE] FCM sent successfully: ${response} token=${payload.token?.substring(0, 20)}... type=${payload.data?.type}`,
      );
    } catch (error) {
      this.logger.error(
        `[PUSH_SERVICE] FCM send failed: ${(error as Error).message} token=${payload.token?.substring(0, 20)}...`,
      );
    }
  }
}