import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
import { CallService } from './call.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CallStatus } from '@prisma/client';

@WebSocketGateway({
  cors: { origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000', credentials: true },
  namespace: '/',
})
export class CallGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private userSockets: Map<number, string> = new Map();

  constructor(
    private readonly jwtService: JwtService,
    private readonly callService: CallService,
    private readonly notificationsService: NotificationsService,
  ) {}

  handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        console.error('CallGateway: connection rejected — no token provided');
        client.disconnect();
        return;
      }

      const payload = this.jwtService.verify<{ sub: number }>(token);
      const userId = payload.sub;

      if (userId) {
        this.userSockets.set(userId, client.id);
        console.log(`CallGateway: user ${userId} connected`);
      }
    } catch (error) {
      console.error('CallGateway: connection rejected — invalid token', error);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    for (const [userId, socketId] of this.userSockets.entries()) {
      if (socketId === client.id) {
        this.userSockets.delete(userId);
        console.log(`CallGateway: user ${userId} disconnected`);
        break;
      }
    }
  }

  // ========== Вспомогательные методы ==========

  private sendToUser(userId: number, event: string, data: unknown) {
    const socketId = this.userSockets.get(userId);
    if (socketId) {
      this.server.to(socketId).emit(event, data);
    }
  }

  private sendToBoth(callerId: number, calleeId: number, event: string, data: unknown) {
    this.sendToUser(callerId, event, data);
    this.sendToUser(calleeId, event, data);
  }

  // ========== Входящие события ==========

  @SubscribeMessage('call:start')
  async handleCallStart(client: Socket, payload: { calleeId: number }) {
    try {
      const token = client.handshake.auth?.token as string;
      const callerPayload = this.jwtService.verify<{ sub: number }>(token);
      const callerId = callerPayload.sub;

      const call = await this.callService.createCall(callerId, payload.calleeId);

      // Отправляем входящий звонок вызываемому пользователю
      this.sendToUser(payload.calleeId, 'call:incoming', {
        callId: call.id,
        callerId: call.callerId,
        callerName: call.caller.fio,
      });

      // Создаём уведомление о входящем звонке (realtime-событие отправляется внутри createNotification)
      await this.notificationsService.createNotification({
        userId: payload.calleeId,
        type: 'CALL',
        title: 'Входящий звонок',
        body: `Вам звонит ${call.caller.fio}`,
        data: { callId: call.id, callerId: call.callerId },
      });

      return { success: true, callId: call.id };
    } catch (error) {
      console.error('call:start error:', error);
      return { success: false, error: 'Не удалось инициировать звонок' };
    }
  }

  @SubscribeMessage('call:accept')
  async handleCallAccept(client: Socket, payload: { callId: number }) {
    try {
      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.ACCEPTED,
        new Date(),
      );

      this.sendToUser(call.callerId, 'call:accepted', {
        callId: call.id,
        calleeId: call.calleeId,
      });

      return { success: true };
    } catch (error) {
      console.error('call:accept error:', error);
      return { success: false, error: 'Не удалось принять звонок' };
    }
  }

  @SubscribeMessage('call:reject')
  async handleCallReject(client: Socket, payload: { callId: number }) {
    try {
      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.REJECTED,
      );

      this.sendToUser(call.callerId, 'call:rejected', {
        callId: call.id,
      });

      return { success: true };
    } catch (error) {
      console.error('call:reject error:', error);
      return { success: false, error: 'Не удалось отклонить звонок' };
    }
  }

  @SubscribeMessage('call:end')
  async handleCallEnd(client: Socket, payload: { callId: number }) {
    try {
      const call = await this.callService.getCallById(payload.callId);

      const now = new Date();
      const duration = call.startedAt
        ? Math.floor((now.getTime() - call.startedAt.getTime()) / 1000)
        : 0;

      await this.callService.updateCallStatus(payload.callId, CallStatus.ENDED, undefined, now);

      this.sendToBoth(call.callerId, call.calleeId, 'call:ended', {
        callId: call.id,
        duration,
      });

      return { success: true };
    } catch (error) {
      console.error('call:end error:', error);
      return { success: false, error: 'Не удалось завершить звонок' };
    }
  }

  @SubscribeMessage('call:signal')
  async handleCallSignal(
    client: Socket,
    payload: { callId: number; type: string; sdp?: string; candidate?: string; sdpMid?: string; sdpMLineIndex?: number },
  ) {
    try {
      const fromUserId = this.getUserIdFromToken(client);
      if (!fromUserId) {
        return { success: false, error: 'Не удалось определить отправителя' };
      }

      // Получаем информацию о звонке, чтобы определить получателя
      const call = await this.callService.getCallById(payload.callId);
      const toUserId = call.callerId === fromUserId ? call.calleeId : call.callerId;

      // Пересылаем сигнал получателю (поля на верхнем уровне, без обёртки signal)
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
      console.error('call:signal error:', error);
      return { success: false, error: 'Не удалось передать сигнал' };
    }
  }

  @SubscribeMessage('call:missed')
  async handleCallMissed(client: Socket, payload: { callId: number }) {
    try {
      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.MISSED,
      );

      this.sendToUser(call.callerId, 'call:missed', {
        callId: call.id,
      });

      return { success: true };
    } catch (error) {
      console.error('call:missed error:', error);
      return { success: false, error: 'Не удалось отметить звонок как пропущенный' };
    }
  }

  // ========== Вспомогательные методы ==========

  private getUserIdFromToken(client: Socket): number | null {
    try {
      const token = client.handshake.auth?.token as string;
      const payload = this.jwtService.verify<{ sub: number }>(token);
      return payload.sub;
    } catch {
      return null;
    }
  }
}