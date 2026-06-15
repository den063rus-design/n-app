import { Logger } from '@nestjs/common';
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
  private readonly logger = new Logger(CallGateway.name);

  @WebSocketServer()
  server!: Server;

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
        const roomName = `user:${userId}`;
        client.join(roomName);
        const roomSize = this.server.sockets.adapter.rooms.get(roomName)?.size ?? 0;
        this.logger.log(
          `[CALL_GATEWAY] CONNECT user=${userId} clientId=${client.id} room=${roomName} roomSize=${roomSize} transport=${client.conn.transport.name}`,
        );
      }
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CONNECT invalid token clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  async handleDisconnect(client: Socket) {
    // Определяем userId по токену из handshake (если ещё доступен)
    // или просто логируем disconnect
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (token) {
        const payload = this.jwtService.verify<{ sub: number }>(token);
        const userId = payload.sub;
        this.logger.warn(`[CALL_GATEWAY] DISCONNECT user=${userId} clientId=${client.id}`);

        // Проверяем, есть ли у пользователя активный звонок
        // и не осталось ли других сокетов в комнате
        const roomName = `user:${userId}`;
        const room = this.server.sockets.adapter.rooms.get(roomName);
        const socketsLeft = room ? room.size : 0;

        if (socketsLeft === 0) {
          console.log(`[CALL_GATEWAY] 🔌 user ${userId} has no more sockets — checking active call`);

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
            this.logger.error(
              `[CALL_GATEWAY] DISCONNECT error user=${userId} ${error instanceof Error ? error.message : String(error)}`,
            );
          }
        } else {
          this.logger.log(
            `[CALL_GATEWAY] DISCONNECT user=${userId} still has ${socketsLeft} socket(s) -> keeping call alive`,
          );
        }
      } else {
        this.logger.warn(`[CALL_GATEWAY] DISCONNECT anonymous clientId=${client.id}`);
      }
    } catch (error) {
      this.logger.warn(
        `[CALL_GATEWAY] DISCONNECT token invalid/expired clientId=${client.id}`,
      );
    }
  }

  // ========== Вспомогательные методы ==========

  /** Отправляет событие в комнату пользователя (user:<userId>).
   *  Socket.IO сам доставит событие во все активные socket'ы пользователя. */
  private sendToUser(userId: number, event: string, data: unknown) {
    const roomName = `user:${userId}`;
    const roomSize = this.server.sockets.adapter.rooms.get(roomName)?.size ?? 0;
    this.logger.log(
      `[CALL_GATEWAY] SEND room=${roomName} user=${userId} event=${event} sockets=${roomSize} payload=${JSON.stringify(data)}`,
    );
    this.server.to(roomName).emit(event, data);
  }

  private sendToBoth(callerId: number, calleeId: number, event: string, data: unknown) {
    this.sendToUser(callerId, event, data);
    this.sendToUser(calleeId, event, data);
  }

  // ========== Входящие события ==========

  @SubscribeMessage('call:start')
  async handleCallStart(client: Socket, payload: { calleeId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_START clientId=${client.id} calleeId=${payload.calleeId}`,
    );
    try {
      const token = client.handshake.auth?.token as string;
      const callerPayload = this.jwtService.verify<{ sub: number }>(token);
      const callerId = callerPayload.sub;
      this.logger.log(
        `[CALL_GATEWAY] CALL_START resolved callerId=${callerId} -> calleeId=${payload.calleeId}`,
      );

      const existingCallerCall = await this.callService.findActiveCallByUserId(callerId);
      if (existingCallerCall) {
        return { success: false, error: 'У вас уже есть активный звонок' };
      }
      const existingCalleeCall = await this.callService.findActiveCallByUserId(payload.calleeId);
      if (existingCalleeCall) {
        return { success: false, error: 'Пользователь уже занят другим звонком' };
      }

      const call = await this.callService.createCall(callerId, payload.calleeId);

      this.logger.log(`[call:start] Sending call:incoming to user=${payload.calleeId}, callId=${call.id}`);
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
      this.logger.error(
        `[CALL_GATEWAY] CALL_START error clientId=${client.id} ${error instanceof Error ? error.message : String(error)}`,
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

      this.logger.log(
        `[CALL_GATEWAY] CALL_ACCEPT callId=${call.id} notifying callerId=${call.callerId}`,
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
