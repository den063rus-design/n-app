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
  private callTimeouts: Map<number, NodeJS.Timeout> = new Map();

  constructor(
    private readonly jwtService: JwtService,
    private readonly callService: CallService,
    private readonly notificationsService: NotificationsService,
  ) {}

  handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        return;
      }

      const payload = this.jwtService.verify<{ sub: number }>(token);
      const userId = payload.sub;

      if (userId) {
        this.userSockets.set(userId, client.id);
      }
    } catch (error) {
      console.log(`[CALL_GATEWAY] 🔌 invalid token: ${error instanceof Error ? error.message : error}`);
    }
  }

  async handleDisconnect(client: Socket) {
    for (const [userId, socketId] of this.userSockets.entries()) {
      if (socketId === client.id) {
        this.userSockets.delete(userId);
        console.log(`[CALL_GATEWAY] 🔌 user ${userId} disconnected`);

        try {
          const activeCall = await this.callService.findActiveCallByUserId(userId);
          if (activeCall) {
            const { call, otherUserId } = activeCall;
            this.clearCallTimeout(call.id);
            await this.callService.endCall(call.id);
            this.sendToBoth(userId, otherUserId, 'call:ended', {
              callId: call.id,
              reason: 'peer_disconnected',
            });
          }
        } catch (error) {
          console.error(`[CALL_GATEWAY] 🔌 disconnect error for user ${userId}:`, error);
        }

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
    console.log(`[CALL_GATEWAY] 📞 call:start — calleeId=${payload.calleeId}`);
    try {
      const token = client.handshake.auth?.token as string;
      const callerPayload = this.jwtService.verify<{ sub: number }>(token);
      const callerId = callerPayload.sub;

      const existingCallerCall = await this.callService.findActiveCallByUserId(callerId);
      if (existingCallerCall) {
        return { success: false, error: 'У вас уже есть активный звонок' };
      }
      const existingCalleeCall = await this.callService.findActiveCallByUserId(payload.calleeId);
      if (existingCalleeCall) {
        return { success: false, error: 'Пользователь уже занят другим звонком' };
      }

      const call = await this.callService.createCall(callerId, payload.calleeId);

      this.sendToUser(payload.calleeId, 'call:incoming', {
        callId: call.id,
        callerId: call.callerId,
        callerName: call.caller.fio,
      });

      await this.notificationsService.createNotification({
        userId: payload.calleeId,
        type: 'CALL',
        title: 'Входящий звонок',
        body: `Вам звонит ${call.caller.fio}`,
        data: {
          callId: call.id,
          callerId: call.callerId,
          callerName: call.caller.fio,
        },
      });

      const timeout = setTimeout(async () => {
        try {
          const currentCall = await this.callService.findCallById(call.id);
          if (currentCall && currentCall.status === CallStatus.PENDING) {
            console.log(`[CALL_GATEWAY] ⏰ no_answer timeout — call ${call.id}`);
            await this.callService.endCall(call.id);
            this.sendToBoth(call.callerId, call.calleeId, 'call:ended', {
              callId: call.id,
              reason: 'no_answer',
            });
          }
        } catch (err) {
          console.error(`[CALL_GATEWAY] ⏰ timeout error for call ${call.id}:`, err);
        } finally {
          this.callTimeouts.delete(call.id);
        }
      }, 30000);
      this.callTimeouts.set(call.id, timeout);

      return { success: true, callId: call.id };
    } catch (error) {
      console.error('[CALL_GATEWAY] ❌ call:start error:', error);
      return { success: false, error: 'Не удалось инициировать звонок' };
    }
  }

  @SubscribeMessage('call:accept')
  async handleCallAccept(client: Socket, payload: { callId: number }) {
    console.log(`[CALL_GATEWAY] ✅ call:accept — callId=${payload.callId}`);
    try {
      const token = client.handshake.auth?.token as string;
      const acceptorPayload = this.jwtService.verify<{ sub: number }>(token);
      const acceptorId = acceptorPayload.sub;

      const existingCall = await this.callService.findCallById(payload.callId);
      if (!existingCall) {
        return { success: false, error: 'Звонок не найден' };
      }
      if (existingCall.status !== CallStatus.PENDING) {
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

      this.sendToUser(call.callerId, 'call:accepted', {
        callId: call.id,
        calleeId: call.calleeId,
      });

      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ❌ call:accept error:', error);
      return { success: false, error: 'Не удалось принять звонок' };
    }
  }

  @SubscribeMessage('call:reject')
  async handleCallReject(client: Socket, payload: { callId: number }) {
    console.log(`[CALL_GATEWAY] ❌ call:reject — callId=${payload.callId}`);
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
      console.error('[CALL_GATEWAY] ❌ call:reject error:', error);
      return { success: false, error: 'Не удалось отклонить звонок' };
    }
  }

  @SubscribeMessage('call:end')
  async handleCallEnd(client: Socket, payload: { callId: number }) {
    console.log(`[CALL_GATEWAY] 🔴 call:end — callId=${payload.callId}`);
    try {
      if (payload.callId == null || payload.callId === undefined) {
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
      console.error('[CALL_GATEWAY] ❌ call:end error:', error);
      return { success: false, error: 'Не удалось завершить звонок' };
    }
  }

  @SubscribeMessage('call:signal')
  async handleCallSignal(
    client: Socket,
    payload: { callId: number; type: string; sdp?: string; candidate?: string; sdpMid?: string; sdpMLineIndex?: number },
  ) {
    console.log(`[CALL_GATEWAY] 📡 call:signal — type=${payload.type}, callId=${payload.callId}`);
    try {
      const fromUserId = this.getUserIdFromToken(client);
      if (!fromUserId) {
        console.error('[CALL_GATEWAY] 📡 call:signal — could not determine sender');
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
      console.error('[CALL_GATEWAY] ❌ call:signal error:', error);
      return { success: false, error: 'Не удалось передать сигнал' };
    }
  }

  // ========== Вспомогательные методы ==========

  private clearCallTimeout(callId: number) {
    const timeout = this.callTimeouts.get(callId);
    if (timeout) {
      clearTimeout(timeout);
      this.callTimeouts.delete(callId);
    }
  }

  private getUserIdFromToken(client: Socket): number | null {
    try {
      const token = client.handshake.auth?.token as string;
      if (!token) {
        return null;
      }
      const payload = this.jwtService.verify<{ sub: number }>(token);
      return payload.sub;
    } catch (error) {
      return null;
    }
  }
}