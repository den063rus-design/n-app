// ===================================================================
// Call V2 — Session state (backend)
// ===================================================================
// Состояние сессии звонка на стороне backend.
// Используется для трекинга активных звонков в памяти сервера.

import {
  CallStateV2,
  CallEndReasonV2,
  CallTypeV2,
  CallDirectionV2,
  CallParticipantV2,
} from './call-v2.types';

/** Полное состояние сессии звонка на backend. */
export interface CallSessionStateV2 {
  /** Уникальный ID сессии. */
  sessionId: string;

  /** Текущее состояние. */
  state: CallStateV2;

  /** Направление звонка (относительно инициатора). */
  direction: CallDirectionV2;

  /** Тип звонка. */
  callType: CallTypeV2;

  /** Кто инициировал звонок. */
  caller: CallParticipantV2;

  /** Кто принимает звонок. */
  callee: CallParticipantV2;

  /** Время создания сессии. */
  createdAt: string;

  /** Время перехода в in_call. */
  callStartedAt?: string;

  /** Время завершения. */
  endedAt?: string;

  /** Причина завершения. */
  endReason?: CallEndReasonV2;

  /** Флаг: ожидается ли ack от клиента. */
  pendingAck: boolean;

  /** ID комнаты/канала для WebRTC (если используется). */
  roomId?: string;
}

/** In-memory store для активных сессий. */
export class CallSessionStoreV2 {
  private sessions: Map<string, CallSessionStateV2> = new Map();

  /** Создать новую сессию. */
  create(session: CallSessionStateV2): void {
    this.sessions.set(session.sessionId, session);
  }

  /** Получить сессию по ID. */
  get(sessionId: string): CallSessionStateV2 | undefined {
    return this.sessions.get(sessionId);
  }

  /** Обновить состояние сессии. */
  update(sessionId: string, partial: Partial<CallSessionStateV2>): void {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      this.sessions.set(sessionId, { ...existing, ...partial });
    }
  }

  /** Удалить сессию. */
  delete(sessionId: string): void {
    this.sessions.delete(sessionId);
  }

  /** Получить все активные сессии (не финальные). */
  getActive(): CallSessionStateV2[] {
    return Array.from(this.sessions.values()).filter(
      (s) => s.state !== 'ended' && s.state !== 'failed',
    );
  }

  /** Получить все сессии пользователя. */
  getByUserId(userId: string): CallSessionStateV2[] {
    return Array.from(this.sessions.values()).filter(
      (s) => s.caller.userId === userId || s.callee.userId === userId,
    );
  }

  /** Очистить все сессии. */
  clear(): void {
    this.sessions.clear();
  }

  /** Количество активных сессий. */
  get activeCount(): number {
    return this.getActive().length;
  }
}
