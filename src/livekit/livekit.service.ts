import {
  Injectable,
  Logger,
  NotFoundException,
  ForbiddenException,
  GoneException,
} from '@nestjs/common';
import { AccessToken } from 'livekit-server-sdk';
import { CallStatus } from '@prisma/client';
import { CallService } from '../call/call.service';

export interface CurrentUserType {
  id: number;
  fio: string;
  role: string;
}

export interface LiveKitTokenResponse {
  token: string;
  roomName: string;
  wsUrl: string;
}

@Injectable()
export class LiveKitService {
  private readonly logger = new Logger(LiveKitService.name);
  private readonly apiKey: string;
  private readonly apiSecret: string;
  private readonly wsUrl: string;

  constructor(private readonly callService: CallService) {
    this.apiKey = process.env.LIVEKIT_API_KEY ?? '';
    this.apiSecret = process.env.LIVEKIT_API_SECRET ?? '';
    this.wsUrl = process.env.LIVEKIT_URL ?? '';

    if (!this.apiKey) {
      this.logger.warn('LIVEKIT_API_KEY не задан в .env');
    }
    if (!this.apiSecret) {
      this.logger.warn('LIVEKIT_API_SECRET не задан в .env');
    }
    if (!this.wsUrl) {
      this.logger.warn('LIVEKIT_URL не задан в .env');
    }
  }

  /**
   * Формирует имя комнаты для звонка
   */
  buildRoomName(callId: number): string {
    return `call_${callId}`;
  }

  /**
   * Создаёт LiveKit AccessToken для участника звонка.
   *
   * Проверяет:
   * - звонок существует
   * - пользователь является участником (caller или callee)
   * - звонок не завершён
   * - статус звонка допускает подключение (PENDING или ACCEPTED)
   */
  async createTokenForCall(
    callId: number,
    user: CurrentUserType,
  ): Promise<LiveKitTokenResponse> {
    this.logger.log(
      `[LIVEKIT_SERVICE] createTokenForCall begin userId=${user.id} callId=${callId}`,
    );

    // 1. Проверяем, что звонок существует и пользователь участвует
    const call = await this.callService.findCallForParticipant(
      callId,
      user.id,
    );

    if (!call) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall call not found userId=${user.id} callId=${callId}`,
      );
      throw new NotFoundException('Звонок не найден');
    }

    this.logger.log(
      `[LIVEKIT_SERVICE] createTokenForCall call found callId=${call.id} status=${call.status} callerId=${call.callerId} calleeId=${call.calleeId}`,
    );

    // 2. Проверяем, что пользователь — участник звонка
    if (call.callerId !== user.id && call.calleeId !== user.id) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall forbidden userId=${user.id} not participant of callId=${callId}`,
      );
      throw new ForbiddenException('Вы не являетесь участником этого звонка');
    }

    // 3. Проверяем, что звонок не завершён
    if (call.status === CallStatus.ENDED) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall ended userId=${user.id} callId=${callId}`,
      );
      throw new GoneException('Звонок уже завершён');
    }

    if (call.status === CallStatus.REJECTED) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall rejected userId=${user.id} callId=${callId}`,
      );
      throw new GoneException('Звонок был отклонён');
    }

    if (call.status === CallStatus.MISSED) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall missed userId=${user.id} callId=${callId}`,
      );
      throw new GoneException('Звонок был пропущен');
    }

    // 4. Проверяем, что статус допускает подключение
    if (
      call.status !== CallStatus.PENDING &&
      call.status !== CallStatus.ACCEPTED
    ) {
      this.logger.warn(
        `[LIVEKIT_SERVICE] createTokenForCall invalid status userId=${user.id} callId=${callId} status=${call.status}`,
      );
      throw new ForbiddenException(
        'Статус звонка не допускает подключение',
      );
    }

    // 5. Создаём LiveKit AccessToken
    const roomName = this.buildRoomName(callId);
    this.logger.log(
      `[LIVEKIT_SERVICE] createTokenForCall roomName=${roomName} userId=${user.id} callId=${callId}`,
    );

    const at = new AccessToken(this.apiKey, this.apiSecret, {
      identity: String(user.id),
      name: user.fio,
    });

    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
    });

    const token = await at.toJwt();

    this.logger.log(
      `[LIVEKIT_SERVICE] LIVEKIT_TOKEN success userId=${user.id} callId=${callId} roomName=${roomName}`,
    );

    return {
      token,
      roomName,
      wsUrl: this.wsUrl,
    };
  }

  /**
   * Удаляет комнату на LiveKit сервере (опционально).
   * Может использоваться при завершении звонка для очистки.
   */
  async deleteRoom(roomName: string): Promise<void> {
    try {
      const { RoomServiceClient } = await import('livekit-server-sdk');
      const client = new RoomServiceClient(this.wsUrl, this.apiKey, this.apiSecret);
      await client.deleteRoom(roomName);
      this.logger.log(`Комната ${roomName} удалена с LiveKit сервера`);
    } catch (error) {
      this.logger.error(
        `Ошибка при удалении комнаты ${roomName}: ${(error as Error).message}`,
      );
    }
  }
}