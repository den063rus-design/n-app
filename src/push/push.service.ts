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
   * Returns result object so caller can react to specific errors.
   * Does not throw — errors are caught and returned.
   */
  async sendPush(payload: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<{ success: boolean; errorCode?: string; errorMessage?: string }> {
    if (!getApps().length) {
      this.logger.warn('Firebase Admin is not initialized. Push not sent.');
      return { success: false, errorCode: 'not_initialized', errorMessage: 'Firebase Admin not initialized' };
    }

    try {
      // Determine notification type for Android channel selection
      const isCall = payload.data?.type === 'call';
      const senderId = payload.data?.senderId;

      const message: Message = {
        token: payload.token,
        data: payload.data ?? {},
        android: isCall
          ? {
              priority: 'high',
            }
          : {
              priority: 'high',
              collapseKey: senderId ? `message_sender_${senderId}` : 'message',
            },
      };

      const response = await getMessaging().send(message);
      this.logger.log(
        `[PUSH_SERVICE] FCM sent successfully: ${response} token=${payload.token?.substring(0, 20)}... type=${payload.data?.type}`,
      );
      return { success: true };
    } catch (error) {
      const errMsg = (error as Error).message;
      this.logger.error(
        `[PUSH_SERVICE] FCM send failed: ${errMsg} token=${payload.token?.substring(0, 20)}...`,
      );

      // Определяем тип ошибки для caller
      const isTokenInvalid =
        errMsg.includes('Requested entity was not found') ||
        errMsg.includes('registration-token-not-registered') ||
        errMsg.includes('InvalidRegistration') ||
        errMsg.includes('NotRegistered') ||
        errMsg.includes('UNREGISTERED');

      return {
        success: false,
        errorCode: isTokenInvalid ? 'token_invalid' : 'other',
        errorMessage: errMsg,
      };
    }
  }
}
