import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { CallStatus } from '@prisma/client';
import { Namespace, Socket } from 'socket.io';
import { NotificationsService } from '../notifications/notifications.service';
import { CallService } from './call.service';

@WebSocketGateway({
  cors: { origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000', credentials: true },
  namespace: '/',
})
export class CallGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(CallGateway.name);

  @WebSocketServer()
  server!: Namespace;

  private callTimeouts: Map<number, NodeJS.Timeout> = new Map();

  constructor(
    private readonly jwtService: JwtService,
    private readonly callService: CallService,
    private readonly notificationsService: NotificationsService,
  ) {}

  handleConnection(client: Socket) {
    try {
      const userId = this.getUserIdFromToken(client);
      if (!userId) {
        this.logger.warn(`[CALL_GATEWAY] CONNECT skipped clientId=${client.id} reason=no_token`);
        return;
      }

      const roomName = this.getUserRoomName(userId);
      client.join(roomName);

      this.logger.log(
        `[CALL_GATEWAY] CONNECT user=${userId} clientId=${client.id} room=${roomName} roomSize=${this.getRoomSize(roomName)} transport=${client.conn.transport.name}`,
      );
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CONNECT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  async handleDisconnect(client: Socket) {
    try {
      const userId = this.getUserIdFromToken(client);
      if (!userId) {
        this.logger.warn(`[CALL_GATEWAY] DISCONNECT anonymous clientId=${client.id}`);
        return;
      }

      const roomName = this.getUserRoomName(userId);
      const socketsLeft = this.getRoomSize(roomName);

      this.logger.warn(
        `[CALL_GATEWAY] DISCONNECT user=${userId} clientId=${client.id} room=${roomName} socketsLeft=${socketsLeft}`,
      );

      if (socketsLeft > 0) {
        this.logger.log(
          `[CALL_GATEWAY] DISCONNECT keep_alive user=${userId} room=${roomName} socketsLeft=${socketsLeft}`,
        );
        return;
      }

      const activeCall = await this.callService.findActiveCallByUserId(userId);
      if (!activeCall) {
        this.logger.log(`[CALL_GATEWAY] DISCONNECT no_active_call user=${userId}`);
        return;
      }

      const { call, otherUserId } = activeCall;
      this.clearCallTimeout(call.id);
      await this.callService.endCall(call.id);

      this.logger.warn(
        `[CALL_GATEWAY] DISCONNECT ending_call callId=${call.id} user=${userId} otherUserId=${otherUserId}`,
      );

      this.sendToBoth(userId, otherUserId, 'call:ended', {
        callId: call.id,
        reason: 'peer_disconnected',
      });
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] DISCONNECT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /** Отправляет call:incoming и создаёт push-уведомление для callee.
   *  Вынесено в отдельный метод, чтобы не дублировать код
   *  для нового звонка и для reused pending звонка. */
  private async notifyIncomingCall(call: any) {
    const calleeId = call.calleeId;

    this.logger.log(
      `[CALL_GATEWAY] notifyIncomingCall callId=${call.id} calleeId=${calleeId} callerName=${call.caller.fio}`,
    );

    this.sendToUser(calleeId, 'call:incoming', {
      callId: call.id,
      callerId: call.callerId,
      callerName: call.caller.fio,
    });

    await this.notificationsService.createNotification({
      userId: calleeId,
      type: 'CALL',
      title: 'Входящий звонок',
      body: `Вам звонит ${call.caller.fio}`,
      data: {
        callId: call.id,
        callerId: call.callerId,
        callerName: call.caller.fio,
      },
    });
  }

  /** Устанавливает таймаут 30 секунд на PENDING звонок.
   *  Если за это время звонок не принят — завершает его. */
  private setupCallTimeout(callId: number) {
    const timeout = setTimeout(async () => {
      try {
        const currentCall = await this.callService.findCallById(callId);
        if (currentCall && currentCall.status === CallStatus.PENDING) {
          this.logger.warn(`[CALL_GATEWAY] NO_ANSWER timeout callId=${callId}`);
          await this.callService.endCall(callId);
          this.sendToBoth(currentCall.callerId, currentCall.calleeId, 'call:ended', {
            callId,
            reason: 'no_answer',
          });
        }
      } catch (error) {
        this.logger.error(
          `[CALL_GATEWAY] NO_ANSWER failed callId=${callId} error=${error instanceof Error ? error.message : String(error)}`,
        );
      } finally {
        this.callTimeouts.delete(callId);
      }
    }, 30000);

    this.callTimeouts.set(callId, timeout);
  }

  /** Проверяет, является ли PENDING звонок stale (старше STALE_CALL_TIMEOUT_MS).
   *  Используется для автоматической очистки залипших звонков после перезапуска backend. */
  private isStalePendingCall(call: any): boolean {
    if (call.status !== CallStatus.PENDING) {
      return false;
    }

    const age = Date.now() - new Date(call.createdAt).getTime();
    return age > CallService.STALE_CALL_TIMEOUT_MS;
  }

  @SubscribeMessage('call:start')
  async handleCallStart(client: Socket, payload: { calleeId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_START clientId=${client.id} calleeId=${payload.calleeId}`,
    );

    try {
      const callerId = this.requireUserIdFromToken(client);

      this.logger.log(
        `[CALL_GATEWAY] CALL_START resolved callerId=${callerId} calleeId=${payload.calleeId}`,
      );

      // ========== Проверка активных звонков caller ==========
      const callerCalls = await this.callService.findActiveCallsByUserId(callerId);

      // Фильтруем: ищем реальный ACCEPTED (не stale PENDING)
      const callerAcceptedCall = callerCalls.find(
        (c) => c.status === CallStatus.ACCEPTED,
      );
      if (callerAcceptedCall) {
        this.logger.warn(
          `[CALL_GATEWAY] CALL_START blocked active accepted callId=${callerAcceptedCall.id} callerId=${callerId}`,
        );
        return { success: false, error: 'У вас уже есть активный звонок' };
      }

      // Stale PENDING — автоматически завершаем
      for (const c of callerCalls) {
        if (this.isStalePendingCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale pending cleaned callId=${c.id} callerId=${callerId} createdAt=${c.createdAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // ========== Проверка активных звонков callee ==========
      const calleeCalls = await this.callService.findActiveCallsByUserId(payload.calleeId);

      // Фильтруем: ищем реальный ACCEPTED
      const calleeAcceptedCall = calleeCalls.find(
        (c) => c.status === CallStatus.ACCEPTED,
      );
      if (calleeAcceptedCall) {
        this.logger.warn(
          `[CALL_GATEWAY] CALL_START blocked callee accepted callId=${calleeAcceptedCall.id} calleeId=${payload.calleeId}`,
        );
        return { success: false, error: 'Пользователь уже занят другим звонком' };
      }

      // Stale PENDING у callee — автоматически завершаем
      for (const c of calleeCalls) {
        if (this.isStalePendingCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale pending cleaned callId=${c.id} calleeId=${payload.calleeId} createdAt=${c.createdAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // ========== Перечитываем данные после очистки stale ==========
      // После endCall() stale-звонков нужно получить актуальное состояние,
      // чтобы existingPendingBetween гарантированно был не-stale.
      const freshCallerCalls = await this.callService.findActiveCallsByUserId(callerId);

      // ========== Сценарий B: reuse существующего PENDING между теми же пользователями ==========
      // Ищем PENDING звонок, где caller=callerId, callee=calleeId
      const existingPendingBetween = freshCallerCalls.find(
        (c) =>
          c.status === CallStatus.PENDING &&
          c.callerId === callerId &&
          c.calleeId === payload.calleeId,
      );

      if (existingPendingBetween) {
        this.logger.log(
          `[CALL_GATEWAY] CALL_START reused pending callId=${existingPendingBetween.id} callerId=${callerId} calleeId=${payload.calleeId}`,
        );

        // Очищаем старый таймаут, если он ещё висит (in-memory timeout мог сохраниться)
        this.clearCallTimeout(existingPendingBetween.id);

        // Переиспользуем существующий звонок — повторно отправляем call:incoming
        await this.notifyIncomingCall(existingPendingBetween);

        // Переустанавливаем таймаут (старый мог быть потерян при перезапуске backend)
        this.setupCallTimeout(existingPendingBetween.id);

        return { success: true, callId: existingPendingBetween.id, reused: true };
      }

      // ========== Сценарий: новый звонок ==========
      const call = await this.callService.createCall(callerId, payload.calleeId);

      this.logger.log(
        `[CALL_GATEWAY] CALL_START created callId=${call.id} callerId=${callerId} calleeId=${payload.calleeId}`,
      );

      await this.notifyIncomingCall(call);
      this.setupCallTimeout(call.id);

      return { success: true, callId: call.id };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_START failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'Не удалось инициировать звонок' };
    }
  }

  @SubscribeMessage('call:accept')
  async handleCallAccept(client: Socket, payload: { callId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_ACCEPT clientId=${client.id} callId=${payload.callId}`,
    );

    try {
      const acceptorId = this.requireUserIdFromToken(client);
      const existingCall = await this.callService.findCallById(payload.callId);

      if (!existingCall) {
        this.logger.warn(`[CALL_GATEWAY] CALL_ACCEPT missing callId=${payload.callId}`);
        return { success: false, error: 'Звонок не найден' };
      }

      if (existingCall.status !== CallStatus.PENDING) {
        this.logger.warn(
          `[CALL_GATEWAY] CALL_ACCEPT expired callId=${payload.callId} status=${existingCall.status}`,
        );
        this.sendToUser(acceptorId, 'call:ended', {
          callId: payload.callId,
          reason: 'expired',
        });
        return { success: false, error: 'Звонок уже неактивен' };
      }

      this.clearCallTimeout(payload.callId);

      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.ACCEPTED,
        new Date(),
      );

      this.logger.log(
        `[CALL_GATEWAY] CALL_ACCEPT notify callerId=${call.callerId} callId=${call.id}`,
      );

      this.sendToUser(call.callerId, 'call:accepted', {
        callId: call.id,
        calleeId: call.calleeId,
      });

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_ACCEPT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'Не удалось принять звонок' };
    }
  }

  @SubscribeMessage('call:reject')
  async handleCallReject(client: Socket, payload: { callId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_REJECT clientId=${client.id} callId=${payload.callId}`,
    );

    try {
      this.clearCallTimeout(payload.callId);

      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.REJECTED,
      );

      await this.callService.endCall(call.id);

      this.sendToUser(call.callerId, 'call:rejected', {
        callId: call.id,
        reason: 'rejected',
      });

      this.sendToUser(call.calleeId, 'call:ended', {
        callId: call.id,
        reason: 'rejected',
      });

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_REJECT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'Не удалось отклонить звонок' };
    }
  }

  @SubscribeMessage('call:end')
  async handleCallEnd(client: Socket, payload: { callId: number }) {
    this.logger.log(`[CALL_GATEWAY] CALL_END clientId=${client.id} callId=${payload.callId}`);

    try {
      if (payload.callId == null) {
        return { success: false, error: 'callId is required' };
      }

      this.clearCallTimeout(payload.callId);

      const call = await this.callService.getCallById(payload.callId);
      const now = new Date();
      const duration = call.startedAt
        ? Math.floor((now.getTime() - call.startedAt.getTime()) / 1000)
        : 0;

      await this.callService.updateCallStatus(payload.callId, CallStatus.ENDED, undefined, now);

      this.sendToBoth(call.callerId, call.calleeId, 'call:ended', {
        callId: call.id,
        duration,
        reason: 'ended_by_caller',
      });

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_END failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'Не удалось завершить звонок' };
    }
  }

  @SubscribeMessage('call:signal')
  async handleCallSignal(
    client: Socket,
    payload: {
      callId: number;
      type: string;
      sdp?: string;
      candidate?: string;
      sdpMid?: string;
      sdpMLineIndex?: number;
    },
  ) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_SIGNAL clientId=${client.id} type=${payload.type} callId=${payload.callId}`,
    );

    try {
      const fromUserId = this.getUserIdFromToken(client);
      if (!fromUserId) {
        this.logger.warn(`[CALL_GATEWAY] CALL_SIGNAL skipped clientId=${client.id} reason=no_user`);
        return { success: false, error: 'Не удалось определить отправителя' };
      }

      const call = await this.callService.getCallById(payload.callId);
      const toUserId = call.callerId === fromUserId ? call.calleeId : call.callerId;

      this.sendToUser(toUserId, 'call:signal', {
        callId: payload.callId,
        type: payload.type,
        sdp: payload.sdp,
        candidate: payload.candidate,
        sdpMid: payload.sdpMid,
        sdpMLineIndex: payload.sdpMLineIndex,
        fromUserId,
      });

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_SIGNAL failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'Не удалось передать сигнал' };
    }
  }

  private sendToUser(userId: number, event: string, data: unknown) {
    const roomName = this.getUserRoomName(userId);
    const roomSize = this.getRoomSize(roomName);

    this.logger.log(
      `[CALL_GATEWAY] SEND user=${userId} room=${roomName} event=${event} sockets=${roomSize} payload=${JSON.stringify(data)}`,
    );

    this.server.to(roomName).emit(event, data);
  }

  private sendToBoth(callerId: number, calleeId: number, event: string, data: unknown) {
    this.sendToUser(callerId, event, data);
    this.sendToUser(calleeId, event, data);
  }

  private clearCallTimeout(callId: number) {
    const timeout = this.callTimeouts.get(callId);
    if (!timeout) {
      return;
    }

    clearTimeout(timeout);
    this.callTimeouts.delete(callId);
  }

  private getUserRoomName(userId: number) {
    return `user:${userId}`;
  }

  private getRoomSize(roomName: string) {
    return this.server.adapter.rooms.get(roomName)?.size ?? 0;
  }

  private requireUserIdFromToken(client: Socket) {
    const userId = this.getUserIdFromToken(client);
    if (!userId) {
      throw new Error('JWT token is missing or invalid');
    }
    return userId;
  }

  private getUserIdFromToken(client: Socket): number | null {
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        return null;
      }

      const payload = this.jwtService.verify<{ sub: number }>(token);
      return payload.sub;
    } catch {
      return null;
    }
  }
}
