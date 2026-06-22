import { Injectable, NotFoundException } from '@nestjs/common';
import { CallStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CallService {
  /** Максимальный возраст PENDING звонка в миллисекундах.
   *  Если PENDING звонок старше этого значения — он считается stale
   *  и автоматически завершается при новой попытке звонка. */
  static readonly STALE_CALL_TIMEOUT_MS = 45_000;

  constructor(private readonly prisma: PrismaService) {}

  async createCall(callerId: number, calleeId: number) {
    return this.prisma.call.create({
      data: {
        callerId,
        calleeId,
        status: CallStatus.PENDING,
      },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async updateCallStatus(
    callId: number,
    status: CallStatus,
    startedAt?: Date,
    endedAt?: Date,
  ) {
    const call = await this.prisma.call.findUnique({ where: { id: callId } });
    if (!call) {
      throw new NotFoundException('Звонок не найден');
    }

    return this.prisma.call.update({
      where: { id: callId },
      data: {
        status,
        ...(startedAt !== undefined ? { startedAt } : {}),
        ...(endedAt !== undefined ? { endedAt } : {}),
      },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async getUserCalls(userId: number) {
    return this.prisma.call.findMany({
      where: {
        OR: [{ callerId: userId }, { calleeId: userId }],
      },
      orderBy: { createdAt: 'desc' },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async getCallById(callId: number) {
    const call = await this.prisma.call.findUnique({
      where: { id: callId },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });

    if (!call) {
      throw new NotFoundException('Звонок не найден');
    }

    return call;
  }

  getIceConfig(userId?: number) {
    const stunUrls = (process.env.WEBRTC_STUN_URLS ??
            'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302,stun:stun2.l.google.com:19302,stun:global.stun.twilio.com:3478')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);

    const iceServers: Array<Record<string, unknown>> = [];

    if (stunUrls.length > 0) {
      iceServers.push({
        urls: stunUrls,
      });
    }

    const turnUrls = (process.env.WEBRTC_TURN_URLS ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    const turnUsername = process.env.WEBRTC_TURN_USERNAME?.trim();
    const turnCredential = process.env.WEBRTC_TURN_CREDENTIAL?.trim();

    if (turnUrls.length > 0 && turnUsername && turnCredential) {
      iceServers.push({
        urls: turnUrls,
        username: turnUsername,
        credential: turnCredential,
      });
    }

    console.log(
      `[CALL_SERVICE] getIceConfig user=${userId ?? 'unknown'} stun=${stunUrls.length} turn=${turnUrls.length > 0 ? 'configured' : 'missing'}`,
    );

    return {
      iceServers,
    };
  }

  /**
   * Находит ВСЕ активные (PENDING или ACCEPTED) звонки пользователя,
   * отсортированные от самого свежего к самому старому.
   * Возвращает массив, чтобы caller мог обработать несколько залипших звонков.
   */
  async findActiveCallsByUserId(userId: number): Promise<any[]> {
    const calls = await this.prisma.call.findMany({
      where: {
        OR: [{ callerId: userId }, { calleeId: userId }],
        status: { in: [CallStatus.PENDING, CallStatus.ACCEPTED] },
      },
      orderBy: { createdAt: 'desc' },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });

    // Диагностика: логируем каждый найденный звонок
    for (const c of calls) {
      console.log(
        `[CALL_SERVICE] findActiveCallsByUserId user=${userId} ` +
        `callId=${c.id} status=${c.status} callerId=${c.callerId} calleeId=${c.calleeId} ` +
        `createdAt=${c.createdAt?.toISOString?.() ?? c.createdAt} ` +
        `startedAt=${c.startedAt?.toISOString?.() ?? c.startedAt ?? 'null'} ` +
        `endedAt=${c.endedAt?.toISOString?.() ?? c.endedAt ?? 'null'}`,
      );
    }

    return calls;
  }

  /**
   * Находит самый свежий активный (PENDING или ACCEPTED) звонок пользователя.
   * Используется в handleDisconnect для проверки, есть ли активный звонок.
   */
  async findActiveCallByUserId(userId: number): Promise<{ call: any; otherUserId: number } | null> {
    const calls = await this.findActiveCallsByUserId(userId);
    if (calls.length === 0) {
      return null;
    }

    const call = calls[0]; // Самый свежий (orderBy: createdAt desc)
    const otherUserId = this.getOtherParticipant(call, userId);
    return { call, otherUserId };
  }

  /**
   * Находит звонок по ID без включения связанных данных
   */
  async findCallById(callId: number) {
    return this.prisma.call.findUnique({
      where: { id: callId },
    });
  }

  /**
   * Находит звонок по ID и проверяет, что пользователь является участником.
   * Возвращает полный объект звонка с включёнными данными участников.
   * Если звонок не найден или пользователь не участник — возвращает null.
   */
  async findCallForParticipant(
    callId: number,
    userId: number,
  ): Promise<{
    id: number;
    callerId: number;
    calleeId: number;
    status: string;
    startedAt: Date | null;
    endedAt: Date | null;
    createdAt: Date;
    caller: { id: number; fio: string };
    callee: { id: number; fio: string };
  } | null> {
    const call = await this.prisma.call.findUnique({
      where: { id: callId },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });

    if (!call) {
      return null;
    }

    // Проверяем, что пользователь — caller или callee
    if (call.callerId !== userId && call.calleeId !== userId) {
      return null;
    }

    return call;
  }

  /**
   * Завершает звонок: устанавливает статус ENDED и endedAt.
   * Защита от дублирования: если звонок уже ENDED — пропускаем update.
   */
  async endCall(callId: number): Promise<any> {
    // Проверяем текущий статус, чтобы избежать двойного завершения
    const existing = await this.prisma.call.findUnique({
      where: { id: callId },
      select: { id: true, status: true },
    });

    if (!existing) {
      throw new NotFoundException('Звонок не найден');
    }

    if (existing.status === CallStatus.ENDED) {
      // Звонок уже завершён — не делаем лишний update
      return existing;
    }

    return this.prisma.call.update({
      where: { id: callId },
      data: {
        status: CallStatus.ENDED,
        endedAt: new Date(),
      },
    });
  }

  /**
   * Возвращает ID второго участника звонка
   */
  getOtherParticipant(call: any, disconnectedUserId: number): number {
    return call.callerId === disconnectedUserId ? call.calleeId : call.callerId;
  }
}
