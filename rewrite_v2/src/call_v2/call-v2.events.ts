// ===================================================================
// Call V2 — Event definitions
// ===================================================================
// Все socket-события для call-flow.
// Каждое событие имеет:
// - event name (строка для socket-транспорта)
// - payload (типизированные данные)
// - ack (опциональный ответ)

import { CallEndReasonV2, CallTypeV2, CallDirectionV2 } from './call-v2.types';

// ===================================================================
// Базовые типы
// ===================================================================

/** Базовый payload для всех событий. */
interface BaseEventPayloadV2 {
  sessionId: string;
  timestamp: string; // ISO 8601
}

/** Ответ на событие (ack). */
interface AckResponseV2 {
  success: boolean;
  error?: string;
}

// ===================================================================
// Client → Server (исходящие от клиента)
// ===================================================================

// --- Инициировать звонок ---

export const CLIENT_CALL_START = 'call:start' as const;

export interface CallStartPayloadV2 {
  calleeId: string;
  callType: CallTypeV2;
}

export type CallStartAckV2 = AckResponseV2 & {
  sessionId: string;
};

// --- Принять входящий звонок ---

export const CLIENT_CALL_ACCEPT = 'call:accept' as const;

export interface CallAcceptPayloadV2 extends BaseEventPayloadV2 {
  // Клиент принял звонок, дополнительных данных не требуется
}

export type CallAcceptAckV2 = AckResponseV2;

// --- Отклонить входящий звонок ---

export const CLIENT_CALL_REJECT = 'call:reject' as const;

export interface CallRejectPayloadV2 extends BaseEventPayloadV2 {
  reason?: string;
}

export type CallRejectAckV2 = AckResponseV2;

// --- Завершить звонок ---

export const CLIENT_CALL_END = 'call:end' as const;

export interface CallEndPayloadV2 extends BaseEventPayloadV2 {
  reason: CallEndReasonV2;
}

export type CallEndAckV2 = AckResponseV2;

// --- WebRTC offer/answer/ICE (медиа-сигналинг) ---

export const CLIENT_MEDIA_OFFER = 'media:offer' as const;
export const CLIENT_MEDIA_ANSWER = 'media:answer' as const;
export const CLIENT_MEDIA_ICE_CANDIDATE = 'media:ice_candidate' as const;

export interface MediaSignalingPayloadV2 extends BaseEventPayloadV2 {
  sdp?: string;
  iceCandidate?: string;
}

export type MediaSignalingAckV2 = AckResponseV2;

// ===================================================================
// Server → Client (входящие на клиент)
// ===================================================================

// --- Входящий звонок ---

export const SERVER_CALL_INCOMING = 'call:incoming' as const;

export interface CallIncomingPayloadV2 {
  sessionId: string;
  callerId: string;
  callerName?: string;
  callType: CallTypeV2;
  timestamp: string;
}

// --- Звонок принят удалённо ---

export const SERVER_CALL_REMOTE_ACCEPTED = 'call:remote_accepted' as const;

export interface CallRemoteAcceptedPayloadV2 extends BaseEventPayloadV2 {
  // Сервер подтверждает, что удалённая сторона приняла звонок
}

// --- Звонок отклонён удалённо ---

export const SERVER_CALL_REMOTE_REJECTED = 'call:remote_rejected' as const;

export interface CallRemoteRejectedPayloadV2 extends BaseEventPayloadV2 {
  reason?: string;
}

// --- Удалённая сторона завершила звонок ---

export const SERVER_CALL_REMOTE_END = 'call:remote_end' as const;

export interface CallRemoteEndPayloadV2 extends BaseEventPayloadV2 {
  reason: CallEndReasonV2;
}

// --- Медиа-соединение установлено ---

export const SERVER_MEDIA_CONNECTED = 'media:connected' as const;

export interface MediaConnectedPayloadV2 extends BaseEventPayloadV2 {
  // Сервер подтверждает, что WebRTC соединение установлено
}

// --- Медиа-соединение не удалось ---

export const SERVER_MEDIA_FAILED = 'media:failed' as const;

export interface MediaFailedPayloadV2 extends BaseEventPayloadV2 {
  error: string;
}

// --- Таймаут ожидания ответа ---

export const SERVER_CALL_TIMEOUT = 'call:timeout' as const;

export interface CallTimeoutPayloadV2 extends BaseEventPayloadV2 {
  direction: CallDirectionV2;
}

// --- Сокет отключён / потеря соединения ---

export const SERVER_CALL_PEER_DISCONNECTED = 'call:peer_disconnected' as const;

export interface CallPeerDisconnectedPayloadV2 extends BaseEventPayloadV2 {
  reason?: string;
}

// ===================================================================
// Общий тип для всех server → client событий
// ===================================================================

export type ServerToClientEventV2 =
  | { event: typeof SERVER_CALL_INCOMING; payload: CallIncomingPayloadV2 }
  | { event: typeof SERVER_CALL_REMOTE_ACCEPTED; payload: CallRemoteAcceptedPayloadV2 }
  | { event: typeof SERVER_CALL_REMOTE_REJECTED; payload: CallRemoteRejectedPayloadV2 }
  | { event: typeof SERVER_CALL_REMOTE_END; payload: CallRemoteEndPayloadV2 }
  | { event: typeof SERVER_MEDIA_CONNECTED; payload: MediaConnectedPayloadV2 }
  | { event: typeof SERVER_MEDIA_FAILED; payload: MediaFailedPayloadV2 }
  | { event: typeof SERVER_CALL_TIMEOUT; payload: CallTimeoutPayloadV2 }
  | { event: typeof SERVER_CALL_PEER_DISCONNECTED; payload: CallPeerDisconnectedPayloadV2 };

// ===================================================================
// Общий тип для всех client → server событий
// ===================================================================

export type ClientToServerEventV2 =
  | { event: typeof CLIENT_CALL_START; payload: CallStartPayloadV2 }
  | { event: typeof CLIENT_CALL_ACCEPT; payload: CallAcceptPayloadV2 }
  | { event: typeof CLIENT_CALL_REJECT; payload: CallRejectPayloadV2 }
  | { event: typeof CLIENT_CALL_END; payload: CallEndPayloadV2 }
  | { event: typeof CLIENT_MEDIA_OFFER; payload: MediaSignalingPayloadV2 }
  | { event: typeof CLIENT_MEDIA_ANSWER; payload: MediaSignalingPayloadV2 }
  | { event: typeof CLIENT_MEDIA_ICE_CANDIDATE; payload: MediaSignalingPayloadV2 };
