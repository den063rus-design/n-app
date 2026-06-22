// ===================================================================
// Call V2 — Type definitions
// ===================================================================
// Базовые типы для backend call-flow.

// --- Состояния звонка ---

export type CallStateV2 =
  | 'idle'
  | 'outgoing'
  | 'incoming'
  | 'accepting'
  | 'connecting'
  | 'in_call'
  | 'ending'
  | 'ended'
  | 'failed';

// --- Причины завершения звонка ---

export const CALL_END_REASONS_V2 = [
  'local_end',
  'remote_end',
  'rejected',
  'timeout_no_answer',
  'connection_lost',
  'media_failed',
  'system_error',
  'cancelled',
  'unknown',
] as const;

export type CallEndReasonV2 = (typeof CALL_END_REASONS_V2)[number];

// --- Тип звонка ---

export type CallTypeV2 = 'audio' | 'video';

// --- Направление звонка ---

export type CallDirectionV2 = 'incoming' | 'outgoing';

// --- Участники ---

export interface CallParticipantV2 {
  userId: string;
  displayName?: string;
  avatarUrl?: string;
}

// --- Мета-информация сессии ---

export interface CallSessionMetaV2 {
  sessionId: string;
  caller: CallParticipantV2;
  callee: CallParticipantV2;
  direction: CallDirectionV2;
  callType: CallTypeV2;
  createdAt: string; // ISO 8601
  callStartedAt?: string; // ISO 8601
  endedAt?: string; // ISO 8601
  endReason?: CallEndReasonV2;
  state: CallStateV2;
}
