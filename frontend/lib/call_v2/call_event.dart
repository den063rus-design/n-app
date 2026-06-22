/// События V2 звонка.
///
/// Каждое событие относится к одной из групп-сценариев:
/// - [CallScenarioV2.outgoing] — исходящий звонок
/// - [CallScenarioV2.incoming] — входящий звонок
/// - [CallScenarioV2.media] — медиа-соединение
/// - [CallScenarioV2.network] — сетевые проблемы
/// - [CallScenarioV2.notification] — уведомления
/// - [CallScenarioV2.internal] — внутренние события
abstract class CallEventV2 {
  final CallScenarioV2 scenario;

  const CallEventV2(this.scenario);
}

/// Сценарий, к которому относится событие.
enum CallScenarioV2 {
  outgoing,
  incoming,
  media,
  network,
  notification,
  internal,
}

// ===================================================================
// Исходящий звонок
// ===================================================================

/// Пользователь инициировал исходящий звонок.
class StartOutgoingEvent extends CallEventV2 {
  final int calleeId;
  final String? callType;
  final int? callId;

  const StartOutgoingEvent({
    required this.calleeId,
    this.callType,
    this.callId,
  }) : super(CallScenarioV2.outgoing);
}

/// Удалённая сторона приняла звонок.
class RemoteAcceptedEvent extends CallEventV2 {
  final int remoteCallId;

  const RemoteAcceptedEvent({required this.remoteCallId})
      : super(CallScenarioV2.outgoing);
}

/// Удалённая сторона отклонила звонок.
class RemoteRejectedEvent extends CallEventV2 {
  final String? reason;

  const RemoteRejectedEvent({this.reason}) : super(CallScenarioV2.outgoing);
}

// ===================================================================
// Входящий звонок
// ===================================================================

/// Получен входящий звонок (от socket или push).
class ReceiveIncomingEvent extends CallEventV2 {
  final int callerUserId;
  final int callId;
  final String? callType;
  final String? callerName;

  const ReceiveIncomingEvent({
    required this.callerUserId,
    required this.callId,
    this.callType,
    this.callerName,
  }) : super(CallScenarioV2.incoming);
}

/// Пользователь принял входящий звонок.
class AcceptEvent extends CallEventV2 {
  const AcceptEvent() : super(CallScenarioV2.incoming);
}

/// Пользователь отклонил входящий звонок.
class RejectEvent extends CallEventV2 {
  final String? reason;

  const RejectEvent({this.reason}) : super(CallScenarioV2.incoming);
}

// ===================================================================
// Медиа-соединение
// ===================================================================

/// Медиа-поток установлен (WebRTC connected).
class MediaConnectedEvent extends CallEventV2 {
  const MediaConnectedEvent() : super(CallScenarioV2.media);
}

/// Ошибка медиа-соединения (WebRTC failed).
class MediaFailedEvent extends CallEventV2 {
  final String error;

  const MediaFailedEvent({required this.error}) : super(CallScenarioV2.media);
}

// ===================================================================
// Сеть / транспорт
// ===================================================================

/// Потеряно socket-соединение.
class SocketLostEvent extends CallEventV2 {
  final String? error;

  const SocketLostEvent({this.error}) : super(CallScenarioV2.network);
}

/// Удалённый участник отключился (peer disconnected).
class PeerDisconnectedEvent extends CallEventV2 {
  final String? reason;

  const PeerDisconnectedEvent({this.reason}) : super(CallScenarioV2.network);
}

// ===================================================================
// Завершение звонка
// ===================================================================

/// Локальное завершение звонка (пользователь нажал "завершить").
class LocalEndEvent extends CallEventV2 {
  const LocalEndEvent() : super(CallScenarioV2.internal);
}

/// Удалённая сторона завершила звонок.
class RemoteEndEvent extends CallEventV2 {
  final String? reason;

  const RemoteEndEvent({this.reason}) : super(CallScenarioV2.internal);
}

// ===================================================================
// Уведомления
// ===================================================================

/// Пользователь нажал на push-уведомление о звонке.
class PushTappedEvent extends CallEventV2 {
  final String payload;

  const PushTappedEvent({required this.payload})
      : super(CallScenarioV2.notification);
}

/// Уведомление было отменено (свайпнули / системная отмена).
class NotificationCancelledEvent extends CallEventV2 {
  final String? notificationId;

  const NotificationCancelledEvent({this.notificationId})
      : super(CallScenarioV2.notification);
}

// ===================================================================
// Сброс
// ===================================================================

/// Явный сброс сессии в idle.
///
/// Единственный способ выйти из финальных состояний [ended] и [failed].
/// Вызывается coordinator'ом после того, как UI-слой обработал завершение звонка.
class ResetEvent extends CallEventV2 {
  const ResetEvent() : super(CallScenarioV2.internal);
}

// ===================================================================
// Таймауты
// ===================================================================

/// Истекло время ожидания ответа (входящий или исходящий).
class TimeoutNoAnswerEvent extends CallEventV2 {
  final String direction; // 'incoming' | 'outgoing'

  const TimeoutNoAnswerEvent({required this.direction})
      : super(CallScenarioV2.internal);
}
