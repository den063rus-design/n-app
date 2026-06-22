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
  private callDeliveryTimeouts: Map<number, NodeJS.Timeout> = new Map();
  private deliveredIncomingCalls: Set<number> = new Set();

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
      this.clearCallDeliveryTimeout(call.id);
      await this.callService.endCall(call.id);

      this.logger.warn(
        `[CALL_GATEWAY] DISCONNECT ending_call callId=${call.id} user=${userId} otherUserId=${otherUserId}`,
      );

      this.sendToBoth(userId, otherUserId, 'call:ended', {
        callId: call.id,
        reason: 'peer_disconnected',
      });
      await this.notifyCallEndedPush(call.id, userId, otherUserId);
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] DISCONNECT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /** РћС‚РїСЂР°РІР»СЏРµС‚ call:incoming Рё СЃРѕР·РґР°С‘С‚ push-СѓРІРµРґРѕРјР»РµРЅРёРµ РґР»СЏ callee.
   *  Р’С‹РЅРµСЃРµРЅРѕ РІ РѕС‚РґРµР»СЊРЅС‹Р№ РјРµС‚РѕРґ, С‡С‚РѕР±С‹ РЅРµ РґСѓР±Р»РёСЂРѕРІР°С‚СЊ РєРѕРґ
   *  РґР»СЏ РЅРѕРІРѕРіРѕ Р·РІРѕРЅРєР° Рё РґР»СЏ reused pending Р·РІРѕРЅРєР°. */
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
      title: 'Р’С…РѕРґСЏС‰РёР№ Р·РІРѕРЅРѕРє',
      body: `Р’Р°Рј Р·РІРѕРЅРёС‚ ${call.caller.fio}`,
      data: {
        callId: call.id,
        callerId: call.callerId,
        callerName: call.caller.fio,
      },
    });
  }

  private async notifyCallEndedPush(callId: number, ...userIds: number[]) {
    await Promise.all(
      userIds.map((userId) =>
        this.notificationsService.sendCallEndPush(userId, callId),
      ),
    );
  }

  /** РЈСЃС‚Р°РЅР°РІР»РёРІР°РµС‚ С‚Р°Р№РјР°СѓС‚ 30 СЃРµРєСѓРЅРґ РЅР° PENDING Р·РІРѕРЅРѕРє.
   *  Р•СЃР»Рё Р·Р° СЌС‚Рѕ РІСЂРµРјСЏ Р·РІРѕРЅРѕРє РЅРµ РїСЂРёРЅСЏС‚ вЂ” Р·Р°РІРµСЂС€Р°РµС‚ РµРіРѕ. */
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
          await this.notifyCallEndedPush(callId, currentCall.callerId, currentCall.calleeId);
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

  private setupCallDeliveryTimeout(callId: number) {
    const timeout = setTimeout(async () => {
      try {
        if (this.deliveredIncomingCalls.has(callId)) {
          this.logger.log(`[CALL_GATEWAY] CALL_DELIVERY_TIMEOUT skipped callId=${callId} reason=already_delivered`);
          return;
        }

        const currentCall = await this.callService.findCallById(callId);
        if (currentCall && currentCall.status === CallStatus.PENDING) {
          this.logger.warn(`[CALL_GATEWAY] CALL_DELIVERY_TIMEOUT fired callId=${callId}`);
          await this.callService.endCall(callId);
          this.sendToBoth(currentCall.callerId, currentCall.calleeId, 'call:ended', {
            callId,
            reason: 'no_answer',
          });
          await this.notifyCallEndedPush(callId, currentCall.callerId, currentCall.calleeId);
        }
      } catch (error) {
        this.logger.error(`[CALL_GATEWAY] CALL_DELIVERY_TIMEOUT failed callId=${callId} error=${error instanceof Error ? error.message : String(error)}`);
      } finally {
        this.callDeliveryTimeouts.delete(callId);
        this.deliveredIncomingCalls.delete(callId);
      }
    }, 15000);

    this.callDeliveryTimeouts.set(callId, timeout);
  }

  /** РџСЂРѕРІРµСЂСЏРµС‚, СЏРІР»СЏРµС‚СЃСЏ Р»Рё PENDING Р·РІРѕРЅРѕРє stale (СЃС‚Р°СЂС€Рµ STALE_CALL_TIMEOUT_MS).
   *  РСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ РґР»СЏ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРѕР№ РѕС‡РёСЃС‚РєРё Р·Р°Р»РёРїС€РёС… Р·РІРѕРЅРєРѕРІ РїРѕСЃР»Рµ РїРµСЂРµР·Р°РїСѓСЃРєР° backend. */
  private isStalePendingCall(call: any): boolean {
    if (call.status !== CallStatus.PENDING) {
      return false;
    }

    const age = Date.now() - new Date(call.createdAt).getTime();
    return age > CallService.STALE_CALL_TIMEOUT_MS;
  }

  /** РџСЂРѕРІРµСЂСЏРµС‚, СЏРІР»СЏРµС‚СЃСЏ Р»Рё ACCEPTED Р·РІРѕРЅРѕРє stale.
   *  РљСЂРёС‚РµСЂРёРё: СЃС‚Р°С‚СѓСЃ ACCEPTED, РЅРѕ startedAt РѕС‚СЃСѓС‚СЃС‚РІСѓРµС‚ (РЅРёРєРѕРіРґР° РЅРµ Р±С‹Р» СЂРµР°Р»СЊРЅРѕ РЅР°С‡Р°С‚)
   *  РР›Р Р·РІРѕРЅРѕРє СЃС‚Р°СЂС€Рµ 5 РјРёРЅСѓС‚ Р±РµР· endedAt (Р·Р°Р»РёРїС€РёР№).
   *  РўР°РєРёРµ Р·РІРѕРЅРєРё РЅРµ РґРѕР»Р¶РЅС‹ Р±Р»РѕРєРёСЂРѕРІР°С‚СЊ РЅРѕРІС‹Рµ. */
  private isStaleAcceptedCall(call: any): boolean {
    if (call.status !== CallStatus.ACCEPTED) {
      return false;
    }

    // Р•СЃР»Рё Р·РІРѕРЅРѕРє ACCEPTED, РЅРѕ never started вЂ” СЏРІРЅРѕ РјС‘СЂС‚РІС‹Р№
    if (!call.startedAt) {
      const age = Date.now() - new Date(call.createdAt).getTime();
      return age > CallService.STALE_CALL_TIMEOUT_MS;
    }

    // Р•СЃР»Рё Р·РІРѕРЅРѕРє ACCEPTED Рё startedAt РµСЃС‚СЊ, РЅРѕ РїСЂРѕС€Р»Рѕ Р±РѕР»СЊС€Рµ 5 РјРёРЅСѓС‚
    // СЃ РјРѕРјРµРЅС‚Р° СЃС‚Р°СЂС‚Р° вЂ” СЃС‡РёС‚Р°РµРј РµРіРѕ Р·Р°Р»РёРїС€РёРј (РЅРѕСЂРјР°Р»СЊРЅС‹Р№ Р·РІРѕРЅРѕРє РЅРµ РґР»РёС‚СЃСЏ РІРµС‡РЅРѕ)
    const age = Date.now() - new Date(call.startedAt).getTime();
    return age > 5 * 60 * 1000; // 5 РјРёРЅСѓС‚
  }

  /** Р›РѕРіРёСЂСѓРµС‚ РґРµС‚Р°Р»СЊРЅСѓСЋ РёРЅС„РѕСЂРјР°С†РёСЋ Рѕ Р·РІРѕРЅРєРµ РґР»СЏ РґРёР°РіРЅРѕСЃС‚РёРєРё. */
  private logCallDetail(prefix: string, call: any): void {
    this.logger.log(
      `${prefix} callId=${call.id} status=${call.status} ` +
      `callerId=${call.callerId} calleeId=${call.calleeId} ` +
      `createdAt=${call.createdAt?.toISOString?.() ?? call.createdAt} ` +
      `startedAt=${call.startedAt?.toISOString?.() ?? call.startedAt ?? 'null'} ` +
      `endedAt=${call.endedAt?.toISOString?.() ?? call.endedAt ?? 'null'}`,
    );
  }

  @SubscribeMessage('call:start')
  async handleCallStart(client: Socket, payload: { calleeId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_START begin clientId=${client.id} calleeId=${payload.calleeId}`,
    );

    try {
      const callerId = this.requireUserIdFromToken(client);

      this.logger.log(
        `[CALL_GATEWAY] CALL_START resolved callerId=${callerId} calleeId=${payload.calleeId}`,
      );

      // ========== РџСЂРѕРІРµСЂРєР° Р°РєС‚РёРІРЅС‹С… Р·РІРѕРЅРєРѕРІ caller ==========
      const callerCalls = await this.callService.findActiveCallsByUserId(callerId);
      this.logger.log(
        `[CALL_GATEWAY] CALL_START caller active calls count=${callerCalls.length} callerId=${callerId}`,
      );

      // Р”РёР°РіРЅРѕСЃС‚РёРєР°: Р»РѕРіРёСЂСѓРµРј РєР°Р¶РґС‹Р№ Р·РІРѕРЅРѕРє caller
      for (const c of callerCalls) {
        this.logCallDetail('[CALL_GATEWAY] CALL_START caller call detail', c);
      }

      // Р¤РёР»СЊС‚СЂСѓРµРј: РёС‰РµРј СЂРµР°Р»СЊРЅС‹Р№ ACCEPTED (РЅРµ stale PENDING Рё РЅРµ stale ACCEPTED)
      const callerAcceptedCall = callerCalls.find(
        (c) => c.status === CallStatus.ACCEPTED && !this.isStaleAcceptedCall(c),
      );
      if (callerAcceptedCall) {
        this.logCallDetail(
          '[CALL_GATEWAY] CALL_START blocked caller_busy вЂ” blocking call detail',
          callerAcceptedCall,
        );
        return { success: false, error: 'РЈ РІР°СЃ СѓР¶Рµ РµСЃС‚СЊ Р°РєС‚РёРІРЅС‹Р№ Р·РІРѕРЅРѕРє' };
      }

      // Stale PENDING вЂ” Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё Р·Р°РІРµСЂС€Р°РµРј
      for (const c of callerCalls) {
        if (this.isStalePendingCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale cleaned callId=${c.id} callerId=${callerId} createdAt=${c.createdAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // Stale ACCEPTED вЂ” Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё Р·Р°РІРµСЂС€Р°РµРј (Р·Р°Р»РёРїС€РёРµ Р·РІРѕРЅРєРё Р±РµР· startedAt)
      for (const c of callerCalls) {
        if (this.isStaleAcceptedCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale accepted cleaned callId=${c.id} callerId=${callerId} createdAt=${c.createdAt} startedAt=${c.startedAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // ========== РџСЂРѕРІРµСЂРєР° Р°РєС‚РёРІРЅС‹С… Р·РІРѕРЅРєРѕРІ callee ==========
      const calleeCalls = await this.callService.findActiveCallsByUserId(payload.calleeId);
      this.logger.log(
        `[CALL_GATEWAY] CALL_START callee active calls count=${calleeCalls.length} calleeId=${payload.calleeId}`,
      );

      // Р”РёР°РіРЅРѕСЃС‚РёРєР°: Р»РѕРіРёСЂСѓРµРј РєР°Р¶РґС‹Р№ Р·РІРѕРЅРѕРє callee
      for (const c of calleeCalls) {
        this.logCallDetail('[CALL_GATEWAY] CALL_START callee call detail', c);
      }

      // Р¤РёР»СЊС‚СЂСѓРµРј: РёС‰РµРј СЂРµР°Р»СЊРЅС‹Р№ ACCEPTED (РЅРµ stale)
      const calleeAcceptedCall = calleeCalls.find(
        (c) => c.status === CallStatus.ACCEPTED && !this.isStaleAcceptedCall(c),
      );
      if (calleeAcceptedCall) {
        this.logCallDetail(
          '[CALL_GATEWAY] CALL_START blocked callee_busy вЂ” blocking call detail',
          calleeAcceptedCall,
        );
        return { success: false, error: 'РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ СѓР¶Рµ Р·Р°РЅСЏС‚ РґСЂСѓРіРёРј Р·РІРѕРЅРєРѕРј' };
      }

      // Stale PENDING Сѓ callee вЂ” Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё Р·Р°РІРµСЂС€Р°РµРј
      for (const c of calleeCalls) {
        if (this.isStalePendingCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale cleaned callId=${c.id} calleeId=${payload.calleeId} createdAt=${c.createdAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // Stale ACCEPTED Сѓ callee вЂ” Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё Р·Р°РІРµСЂС€Р°РµРј
      for (const c of calleeCalls) {
        if (this.isStaleAcceptedCall(c)) {
          this.logger.warn(
            `[CALL_GATEWAY] CALL_START stale accepted cleaned callId=${c.id} calleeId=${payload.calleeId} createdAt=${c.createdAt} startedAt=${c.startedAt}`,
          );
          await this.callService.endCall(c.id);
        }
      }

      // ========== РџРµСЂРµС‡РёС‚С‹РІР°РµРј РґР°РЅРЅС‹Рµ РїРѕСЃР»Рµ РѕС‡РёСЃС‚РєРё stale ==========
      // РџРѕСЃР»Рµ endCall() stale-Р·РІРѕРЅРєРѕРІ РЅСѓР¶РЅРѕ РїРѕР»СѓС‡РёС‚СЊ Р°РєС‚СѓР°Р»СЊРЅРѕРµ СЃРѕСЃС‚РѕСЏРЅРёРµ,
      // С‡С‚РѕР±С‹ existingPendingBetween РіР°СЂР°РЅС‚РёСЂРѕРІР°РЅРЅРѕ Р±С‹Р» РЅРµ-stale.
      const freshCallerCalls = await this.callService.findActiveCallsByUserId(callerId);

      // ========== РЎС†РµРЅР°СЂРёР№ B: reuse СЃСѓС‰РµСЃС‚РІСѓСЋС‰РµРіРѕ PENDING РјРµР¶РґСѓ С‚РµРјРё Р¶Рµ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏРјРё ==========
      // РС‰РµРј PENDING Р·РІРѕРЅРѕРє, РіРґРµ caller=callerId, callee=calleeId
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
        this.sendToUser(callerId, 'call:started', {
          callId: existingPendingBetween.id,
          calleeId: payload.calleeId,
        });

        // РћС‡РёС‰Р°РµРј СЃС‚Р°СЂС‹Р№ С‚Р°Р№РјР°СѓС‚, РµСЃР»Рё РѕРЅ РµС‰С‘ РІРёСЃРёС‚ (in-memory timeout РјРѕРі СЃРѕС…СЂР°РЅРёС‚СЊСЃСЏ)
        this.clearCallTimeout(existingPendingBetween.id);

        // РџРµСЂРµРёСЃРїРѕР»СЊР·СѓРµРј СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ Р·РІРѕРЅРѕРє вЂ” РїРѕРІС‚РѕСЂРЅРѕ РѕС‚РїСЂР°РІР»СЏРµРј call:incoming
        await this.notifyIncomingCall(existingPendingBetween);

        // РџРµСЂРµСѓСЃС‚Р°РЅР°РІР»РёРІР°РµРј С‚Р°Р№РјР°СѓС‚ (СЃС‚Р°СЂС‹Р№ РјРѕРі Р±С‹С‚СЊ РїРѕС‚РµСЂСЏРЅ РїСЂРё РїРµСЂРµР·Р°РїСѓСЃРєРµ backend)
        this.setupCallTimeout(existingPendingBetween.id);
        this.setupCallDeliveryTimeout(existingPendingBetween.id);

        this.logger.log(
          `[CALL_GATEWAY] CALL_START done success callId=${existingPendingBetween.id} reused=true`,
        );

        return { success: true, callId: existingPendingBetween.id, reused: true };
      }

      // ========== РЎС†РµРЅР°СЂРёР№: РЅРѕРІС‹Р№ Р·РІРѕРЅРѕРє ==========
      this.logger.log(
        `[CALL_GATEWAY] CALL_START creating new call callerId=${callerId} calleeId=${payload.calleeId}`,
      );

      const call = await this.callService.createCall(callerId, payload.calleeId);

      this.logger.log(
        `[CALL_GATEWAY] CALL_START created callId=${call.id} callerId=${callerId} calleeId=${payload.calleeId}`,
      );

      this.sendToUser(callerId, 'call:started', {
        callId: call.id,
        calleeId: payload.calleeId,
      });

      this.logger.log(
        `[CALL_GATEWAY] CALL_START notifyIncomingCall callId=${call.id} calleeId=${payload.calleeId}`,
      );

      await this.notifyIncomingCall(call);
      this.setupCallTimeout(call.id);
      this.setupCallDeliveryTimeout(call.id);

      this.logger.log(
        `[CALL_GATEWAY] CALL_START done success callId=${call.id}`,
      );

      return { success: true, callId: call.id };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_START failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ РёРЅРёС†РёРёСЂРѕРІР°С‚СЊ Р·РІРѕРЅРѕРє' };
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
        return { success: false, error: 'Р—РІРѕРЅРѕРє РЅРµ РЅР°Р№РґРµРЅ' };
      }

      if (existingCall.status !== CallStatus.PENDING) {
        this.logger.warn(
          `[CALL_GATEWAY] CALL_ACCEPT expired callId=${payload.callId} status=${existingCall.status}`,
        );
        this.sendToUser(acceptorId, 'call:ended', {
          callId: payload.callId,
          reason: 'expired',
        });
        return { success: false, error: 'Р—РІРѕРЅРѕРє СѓР¶Рµ РЅРµР°РєС‚РёРІРµРЅ' };
      }

      this.clearCallTimeout(payload.callId);
      this.clearCallDeliveryTimeout(payload.callId);

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
      return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ РїСЂРёРЅСЏС‚СЊ Р·РІРѕРЅРѕРє' };
    }
  }

  @SubscribeMessage('call:reject')
  async handleCallReject(client: Socket, payload: { callId: number }) {
    this.logger.log(
      `[CALL_GATEWAY] CALL_REJECT clientId=${client.id} callId=${payload.callId}`,
    );

    try {
      this.clearCallTimeout(payload.callId);
      this.clearCallDeliveryTimeout(payload.callId);

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
      await this.notifyCallEndedPush(call.id, call.callerId, call.calleeId);

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_REJECT failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕС‚РєР»РѕРЅРёС‚СЊ Р·РІРѕРЅРѕРє' };
    }
  }

  @SubscribeMessage('call:end')
  async handleCallEnd(client: Socket, payload: { callId: number; reason?: string }) {
    this.logger.log(`[CALL_GATEWAY] CALL_END clientId=${client.id} callId=${payload.callId} reason=${payload.reason || 'none'}`);

    try {
      if (payload.callId == null) {
        return { success: false, error: 'callId is required' };
      }

      this.clearCallTimeout(payload.callId);
      this.clearCallDeliveryTimeout(payload.callId);

      const call = await this.callService.getCallById(payload.callId);
      this.logger.log(`[CALL_GATEWAY] CALL_END received callId=${payload.callId} userId=${this.getUserIdFromToken(client)} reason=${payload.reason || 'none'} statusBefore=${call?.status || 'unknown'}`);
      const now = new Date();
      const duration = call.startedAt
        ? Math.floor((now.getTime() - call.startedAt.getTime()) / 1000)
        : 0;

      await this.callService.updateCallStatus(payload.callId, CallStatus.ENDED, undefined, now);

      // Р•СЃР»Рё РїСЂРёС‡РёРЅР° connect_failed вЂ” РґСЂСѓРіРѕР№ СѓС‡Р°СЃС‚РЅРёРє РІСЃС‘ РµС‰С‘ РЅР° Р·РІРѕРЅРєРµ,
      // РЅРµ РѕС‚РїСЂР°РІР»СЏРµРј РµРјСѓ call:ended, С‡С‚РѕР±С‹ РЅРµ СЃР±СЂРѕСЃРёС‚СЊ РµРіРѕ СЃРѕСЃС‚РѕСЏРЅРёРµ.
      if (payload.reason === 'connect_failed') {
        this.logger.log(`[CALL_GATEWAY] CALL_END reason=connect_failed вЂ” NOT sending call:ended to other participant callId=${payload.callId}`);
        await this.notifyCallEndedPush(payload.callId, call.callerId, call.calleeId);
        return { success: true };
      }

      this.sendToBoth(call.callerId, call.calleeId, 'call:ended', {
        callId: call.id,
        duration,
        reason: 'ended_by_caller',
      });
      await this.notifyCallEndedPush(call.id, call.callerId, call.calleeId);

      return { success: true };
    } catch (error) {
      this.logger.error(
        `[CALL_GATEWAY] CALL_END failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`,
      );
      return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РІРµСЂС€РёС‚СЊ Р·РІРѕРЅРѕРє' };
    }
  }

  @SubscribeMessage('call:incoming_received')
  async handleIncomingReceived(client: Socket, payload: { callId: number }) {
    const userId = this.getUserIdFromToken(client);
    this.logger.log(`[CALL_GATEWAY] CALL_DELIVERY_ACK clientId=${client.id} userId=${userId} callId=${payload.callId}`);

    try {
      if (!payload.callId) {
        return { success: false, error: 'callId is required' };
      }

      this.deliveredIncomingCalls.add(payload.callId);
      this.clearCallDeliveryTimeout(payload.callId);
      return { success: true };
    } catch (error) {
      this.logger.error(`[CALL_GATEWAY] CALL_DELIVERY_ACK failed clientId=${client.id} error=${error instanceof Error ? error.message : String(error)}`);
      return { success: false, error: 'delivery ack failed' };
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
        return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕРїСЂРµРґРµР»РёС‚СЊ РѕС‚РїСЂР°РІРёС‚РµР»СЏ' };
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
      return { success: false, error: 'РќРµ СѓРґР°Р»РѕСЃСЊ РїРµСЂРµРґР°С‚СЊ СЃРёРіРЅР°Р»' };
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

  private clearCallDeliveryTimeout(callId: number) {
    const timeout = this.callDeliveryTimeouts.get(callId);
    if (timeout) {
      clearTimeout(timeout);
      this.callDeliveryTimeouts.delete(callId);
    }
    this.deliveredIncomingCalls.delete(callId);
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
