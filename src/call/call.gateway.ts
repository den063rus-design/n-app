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
    console.log(`[CALL_GATEWAY] 🔌 handleConnection — client.id=${client.id}, transport=${client.conn?.transport?.name || 'unknown'}`);
    console.log(`[CALL_GATEWAY] 🔌 handleConnection — handshake.auth keys: ${Object.keys(client.handshake.auth || {}).join(', ')}`);
    console.log(`[CALL_GATEWAY] 🔌 handleConnection — handshake.query: ${JSON.stringify(client.handshake.query)}`);
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) {
        console.log('[CALL_GATEWAY] 🔌 handleConnection: ⚠️ no token — skipping registration (client stays connected for other gateways)');
        return;
      }

      const payload = this.jwtService.verify<{ sub: number }>(token);
      const userId = payload.sub;
      console.log(`[CALL_GATEWAY] 🔌 handleConnection: token verified — userId=${userId}`);

      if (userId) {
        // Проверяем, не было ли уже зарегистрировано соединение для этого userId
        const existingSocketId = this.userSockets.get(userId);
        if (existingSocketId && existingSocketId !== client.id) {
          console.log(`[CALL_GATEWAY] 🔌 handleConnection: user ${userId} reconnected — old socket ${existingSocketId}, new socket ${client.id}`);
        }
        this.userSockets.set(userId, client.id);
        console.log(`[CALL_GATEWAY] 🔌 handleConnection: ✅ user ${userId} registered with socket ${client.id}`);
        console.log(`[CALL_GATEWAY] 🔌 handleConnection: Current userSockets map: ${JSON.stringify([...this.userSockets.entries()].map(([k, v]) => `user${k}=${v}`))}`);
      }
    } catch (error) {
      // НЕ дисконнектим клиента — это может быть другой gateway
      // Просто логируем и не регистрируем в своей мапе
      console.log(`[CALL_GATEWAY] 🔌 handleConnection: ❌ invalid token — error: ${error instanceof Error ? error.message : error}`);
    }
  }

  handleDisconnect(client: Socket) {
    console.log(`[CALL_GATEWAY] 🔌 handleDisconnect — client.id=${client.id}`);
    console.log(`[CALL_GATEWAY] 🔌 handleDisconnect — userSockets before: ${JSON.stringify([...this.userSockets.entries()].map(([k, v]) => `user${k}=${v}`))}`);
    let found = false;
    for (const [userId, socketId] of this.userSockets.entries()) {
      if (socketId === client.id) {
        this.userSockets.delete(userId);
        console.log(`[CALL_GATEWAY] 🔌 handleDisconnect: ✅ user ${userId} removed (socket ${client.id})`);
        found = true;
        break;
      }
    }
    if (!found) {
      console.log(`[CALL_GATEWAY] 🔌 handleDisconnect: ⚠️ client ${client.id} was NOT registered in userSockets`);
    }
    console.log(`[CALL_GATEWAY] 🔌 handleDisconnect: userSockets after: ${JSON.stringify([...this.userSockets.entries()].map(([k, v]) => `user${k}=${v}`))}`);
  }

  // ========== Вспомогательные методы ==========

  private sendToUser(userId: number, event: string, data: unknown) {
    const socketId = this.userSockets.get(userId);
    console.log(`[CALL_GATEWAY] 📤 sendToUser — event="${event}", userId=${userId}, socketId=${socketId || 'null'}`);
    console.log(`[CALL_GATEWAY] 📤 sendToUser — data: ${JSON.stringify(data)}`);
    console.log(`[CALL_GATEWAY] 📤 sendToUser — full userSockets map: ${JSON.stringify([...this.userSockets.entries()].map(([k, v]) => `user${k}=${v}`))}`);
    if (socketId) {
      console.log(`[CALL_GATEWAY] 📤 sendToUser: emitting "${event}" to user ${userId} (socket ${socketId})`);
      this.server.to(socketId).emit(event, data);
      console.log(`[CALL_GATEWAY] 📤 sendToUser: ✅ "${event}" emitted to user ${userId}`);
    } else {
      console.log(`[CALL_GATEWAY] 📤 sendToUser: ⚠️⚠️⚠️ user ${userId} NOT FOUND in userSockets for event "${event}"`);
      console.log(`[CALL_GATEWAY] 📤 sendToUser: All registered users: ${[...this.userSockets.keys()].join(', ')}`);
      // Проверяем, может быть userId есть в NotificationsGateway?
      console.log(`[CALL_GATEWAY] 📤 sendToUser: 💡 Check if user ${userId} connected via NotificationsGateway instead of CallGateway`);
    }
  }

  private sendToBoth(callerId: number, calleeId: number, event: string, data: unknown) {
    console.log(`[CALL_GATEWAY] 📤 sendToBoth — event="${event}", callerId=${callerId}, calleeId=${calleeId}`);
    this.sendToUser(callerId, event, data);
    this.sendToUser(calleeId, event, data);
    console.log(`[CALL_GATEWAY] 📤 sendToBoth: ✅ "${event}" sent to both users`);
  }

  // ========== Входящие события ==========

  @SubscribeMessage('call:start')
  async handleCallStart(client: Socket, payload: { calleeId: number }) {
    console.log('[CALL_GATEWAY] ===== 📞 call:start RECEIVED =====');
    console.log('[CALL_GATEWAY] 📞 call:start — client.id:', client.id);
    console.log('[CALL_GATEWAY] 📞 call:start — payload:', JSON.stringify(payload));
    console.log('[CALL_GATEWAY] 📞 call:start — handshake.auth keys:', Object.keys(client.handshake.auth || {}).join(', '));
    try {
      const token = client.handshake.auth?.token as string;
      const callerPayload = this.jwtService.verify<{ sub: number }>(token);
      const callerId = callerPayload.sub;
      console.log(`[CALL_GATEWAY] 📞 call:start — callerId=${callerId}, calleeId=${payload.calleeId}`);

      console.log(`[CALL_GATEWAY] 📞 call:start — checking if callee ${payload.calleeId} is in userSockets: ${this.userSockets.has(payload.calleeId)}`);
      console.log(`[CALL_GATEWAY] 📞 call:start — caller ${callerId} is in userSockets: ${this.userSockets.has(callerId)}`);

      const call = await this.callService.createCall(callerId, payload.calleeId);
      console.log(`[CALL_GATEWAY] 📞 call:start — Call created in DB: id=${call.id}, callerId=${call.callerId}, calleeId=${call.calleeId}`);
      console.log(`[CALL_GATEWAY] 📞 call:start — Caller name: ${call.caller.fio}`);

      // Отправляем входящий звонок вызываемому пользователю
      console.log(`[CALL_GATEWAY] 📞 call:start — >>> Sending call:incoming to user ${payload.calleeId} — callId=${call.id}, callerId=${call.callerId}`);
      this.sendToUser(payload.calleeId, 'call:incoming', {
        callId: call.id,
        callerId: call.callerId,
        callerName: call.caller.fio,
      });

      // Создаём уведомление о входящем звонке (realtime + FCM push отправляются внутри createNotification)
      console.log(`[CALL_GATEWAY] 📞 call:start — Creating notification for user ${payload.calleeId}`);
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
      console.log('[CALL_GATEWAY] 📞 call:start — Notification created');

      console.log('[CALL_GATEWAY] ===== ✅ call:start HANDLED SUCCESSFULLY =====');
      return { success: true, callId: call.id };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:start ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:start error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:start stack:', error.stack);
      }
      return { success: false, error: 'Не удалось инициировать звонок' };
    }
  }

  @SubscribeMessage('call:accept')
  async handleCallAccept(client: Socket, payload: { callId: number }) {
    console.log('[CALL_GATEWAY] ===== ✅ call:accept RECEIVED =====');
    console.log('[CALL_GATEWAY] ✅ call:accept — client.id:', client.id);
    console.log('[CALL_GATEWAY] ✅ call:accept — payload:', JSON.stringify(payload));
    try {
      const token = client.handshake.auth?.token as string;
      const acceptorPayload = this.jwtService.verify<{ sub: number }>(token);
      const acceptorId = acceptorPayload.sub;
      console.log(`[CALL_GATEWAY] ✅ call:accept — acceptorId=${acceptorId}`);

      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.ACCEPTED,
        new Date(),
      );
      console.log(`[CALL_GATEWAY] ✅ call:accept — Call ${call.id} status updated to ACCEPTED`);
      console.log(`[CALL_GATEWAY] ✅ call:accept — callerId=${call.callerId}, calleeId=${call.calleeId}`);

      console.log(`[CALL_GATEWAY] ✅ call:accept — >>> Sending call:accepted to caller ${call.callerId}`);
      this.sendToUser(call.callerId, 'call:accepted', {
        callId: call.id,
        calleeId: call.calleeId,
      });

      console.log('[CALL_GATEWAY] ===== ✅ call:accept HANDLED SUCCESSFULLY =====');
      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:accept ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:accept error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:accept stack:', error.stack);
      }
      return { success: false, error: 'Не удалось принять звонок' };
    }
  }

  @SubscribeMessage('call:reject')
  async handleCallReject(client: Socket, payload: { callId: number }) {
    console.log('[CALL_GATEWAY] ===== ❌ call:reject RECEIVED =====');
    console.log('[CALL_GATEWAY] ❌ call:reject — client.id:', client.id);
    console.log('[CALL_GATEWAY] ❌ call:reject — payload:', JSON.stringify(payload));
    try {
      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.REJECTED,
      );
      console.log(`[CALL_GATEWAY] ❌ call:reject — Call ${call.id} status updated to REJECTED`);
      console.log(`[CALL_GATEWAY] ❌ call:reject — callerId=${call.callerId}`);

      console.log(`[CALL_GATEWAY] ❌ call:reject — >>> Sending call:rejected to caller ${call.callerId}`);
      this.sendToUser(call.callerId, 'call:rejected', {
        callId: call.id,
      });

      console.log('[CALL_GATEWAY] ===== ✅ call:reject HANDLED SUCCESSFULLY =====');
      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:reject ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:reject error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:reject stack:', error.stack);
      }
      return { success: false, error: 'Не удалось отклонить звонок' };
    }
  }

  @SubscribeMessage('call:end')
  async handleCallEnd(client: Socket, payload: { callId: number }) {
    console.log('[CALL_GATEWAY] ===== 🔴 call:end RECEIVED =====');
    console.log('[CALL_GATEWAY] 🔴 call:end — client.id:', client.id);
    console.log('[CALL_GATEWAY] 🔴 call:end — payload:', JSON.stringify(payload));
    try {
      // ВАЛИДАЦИЯ: если callId == null — не делаем запрос к БД
      if (payload.callId == null || payload.callId === undefined) {
        console.log('[CALL_GATEWAY] 🔴 call:end — ⚠️⚠️⚠️ callId is NULL/UNDEFINED — skipping DB query, returning success: false');
        return { success: false, error: 'callId is required' };
      }

      console.log(`[CALL_GATEWAY] 🔴 call:end — Fetching call ${payload.callId} from DB`);
      const call = await this.callService.getCallById(payload.callId);
      console.log(`[CALL_GATEWAY] 🔴 call:end — Call found: id=${call.id}, callerId=${call.callerId}, calleeId=${call.calleeId}, status=${call.status}`);

      const now = new Date();
      const duration = call.startedAt
        ? Math.floor((now.getTime() - call.startedAt.getTime()) / 1000)
        : 0;
      console.log(`[CALL_GATEWAY] 🔴 call:end — Duration: ${duration}s`);

      console.log(`[CALL_GATEWAY] 🔴 call:end — Updating call ${payload.callId} status to ENDED`);
      await this.callService.updateCallStatus(payload.callId, CallStatus.ENDED, undefined, now);
      console.log('[CALL_GATEWAY] 🔴 call:end — Status updated');

      console.log(`[CALL_GATEWAY] 🔴 call:end — >>> Sending call:ended to both users (caller=${call.callerId}, callee=${call.calleeId})`);
      this.sendToBoth(call.callerId, call.calleeId, 'call:ended', {
        callId: call.id,
        duration,
      });

      console.log('[CALL_GATEWAY] ===== ✅ call:end HANDLED SUCCESSFULLY =====');
      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:end ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:end error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:end stack:', error.stack);
      }
      return { success: false, error: 'Не удалось завершить звонок' };
    }
  }

  @SubscribeMessage('call:signal')
  async handleCallSignal(
    client: Socket,
    payload: { callId: number; type: string; sdp?: string; candidate?: string; sdpMid?: string; sdpMLineIndex?: number },
  ) {
    console.log('[CALL_GATEWAY] ===== 📡 call:signal RECEIVED =====');
    console.log('[CALL_GATEWAY] 📡 call:signal — client.id:', client.id);
    console.log('[CALL_GATEWAY] 📡 call:signal — payload:', JSON.stringify(payload));
    try {
      const fromUserId = this.getUserIdFromToken(client);
      if (!fromUserId) {
        console.error('[CALL_GATEWAY] 📡 call:signal — ❌ could not determine sender');
        return { success: false, error: 'Не удалось определить отправителя' };
      }
      console.log(`[CALL_GATEWAY] 📡 call:signal — fromUserId=${fromUserId}, type=${payload.type}`);

      // Получаем информацию о звонке, чтобы определить получателя
      console.log(`[CALL_GATEWAY] 📡 call:signal — Fetching call ${payload.callId} from DB`);
      const call = await this.callService.getCallById(payload.callId);
      const toUserId = call.callerId === fromUserId ? call.calleeId : call.callerId;
      console.log(`[CALL_GATEWAY] 📡 call:signal — Relaying signal type=${payload.type} from user ${fromUserId} to user ${toUserId}`);
      console.log(`[CALL_GATEWAY] 📡 call:signal — call info: callerId=${call.callerId}, calleeId=${call.calleeId}, status=${call.status}`);

      // Пересылаем сигнал получателю (поля на верхнем уровне, без обёртки signal)
      console.log(`[CALL_GATEWAY] 📡 call:signal — >>> Sending call:signal type=${payload.type} to user ${toUserId}`);
      this.sendToUser(toUserId, 'call:signal', {
        callId: payload.callId,
        type: payload.type,
        sdp: payload.sdp,
        candidate: payload.candidate,
        sdpMid: payload.sdpMid,
        sdpMLineIndex: payload.sdpMLineIndex,
        fromUserId,
      });
      console.log(`[CALL_GATEWAY] 📡 call:signal — ✅ Signal type=${payload.type} relayed to user ${toUserId}`);

      console.log('[CALL_GATEWAY] ===== ✅ call:signal HANDLED SUCCESSFULLY =====');
      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:signal ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:signal error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:signal stack:', error.stack);
      }
      return { success: false, error: 'Не удалось передать сигнал' };
    }
  }

  @SubscribeMessage('call:missed')
  async handleCallMissed(client: Socket, payload: { callId: number }) {
    console.log('[CALL_GATEWAY] ===== 📞 call:missed RECEIVED =====');
    console.log('[CALL_GATEWAY] 📞 call:missed — client.id:', client.id);
    console.log('[CALL_GATEWAY] 📞 call:missed — payload:', JSON.stringify(payload));
    try {
      const call = await this.callService.updateCallStatus(
        payload.callId,
        CallStatus.MISSED,
      );
      console.log(`[CALL_GATEWAY] 📞 call:missed — Call ${call.id} marked as MISSED`);
      console.log(`[CALL_GATEWAY] 📞 call:missed — callerId=${call.callerId}`);

      console.log(`[CALL_GATEWAY] 📞 call:missed — >>> Sending call:missed to caller ${call.callerId}`);
      this.sendToUser(call.callerId, 'call:missed', {
        callId: call.id,
      });

      console.log('[CALL_GATEWAY] ===== ✅ call:missed HANDLED SUCCESSFULLY =====');
      return { success: true };
    } catch (error) {
      console.error('[CALL_GATEWAY] ===== ❌ call:missed ERROR =====');
      console.error('[CALL_GATEWAY] ❌ call:missed error:', error);
      if (error instanceof Error) {
        console.error('[CALL_GATEWAY] ❌ call:missed stack:', error.stack);
      }
      return { success: false, error: 'Не удалось отметить звонок как пропущенный' };
    }
  }

  // ========== Вспомогательные методы ==========

  private getUserIdFromToken(client: Socket): number | null {
    try {
      const token = client.handshake.auth?.token as string;
      if (!token) {
        console.log('[CALL_GATEWAY] getUserIdFromToken: ⚠️ no token in handshake.auth');
        return null;
      }
      const payload = this.jwtService.verify<{ sub: number }>(token);
      console.log(`[CALL_GATEWAY] getUserIdFromToken: ✅ userId=${payload.sub}`);
      return payload.sub;
    } catch (error) {
      console.log(`[CALL_GATEWAY] getUserIdFromToken: ❌ error: ${error instanceof Error ? error.message : error}`);
      return null;
    }
  }
}