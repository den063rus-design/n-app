import 'call_state.dart';

/// Модель одной сессии звонка V2.
///
/// Содержит всё состояние, специфичное для конкретного звонка:
/// - текущее состояние
/// - участники
/// - мета-информация (время начала, длительность)
/// - причина завершения
///
/// Сессия создаётся при старте звонка и уничтожается при переходе в [CallStateV2.idle].
class CallSessionV2 {
  /// Уникальный идентификатор звонка.
  final int callId;

  /// ID пользователя, который инициировал звонок (caller).
  final int? callerUserId;

  /// ID пользователя, который принимает звонок (callee).
  final int? calleeUserId;

  /// Имя звонящего.
  final String? callerName;

  /// Имя принимающего.
  final String? calleeName;

  /// Текущее состояние звонка.
  final CallStateV2 state;

  /// Время создания сессии.
  final DateTime createdAt;

  /// Время перехода в состояние [CallStateV2.inCall] (начало разговора).
  final DateTime? callStartedAt;

  /// Время завершения звонка.
  final DateTime? endedAt;

  /// Причина завершения (заполняется при переходе в ended/failed).
  final CallEndReasonV2? endReason;

  /// Тип звонка (например, 'audio', 'video').
  final String? callType;

  CallSessionV2({
    required this.callId,
    this.callerUserId,
    this.calleeUserId,
    this.callerName,
    this.calleeName,
    this.state = CallStateV2.idle,
    DateTime? createdAt,
    this.callStartedAt,
    this.endedAt,
    this.endReason,
    this.callType,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Скопировать сессию с изменениями.
  CallSessionV2 copyWith({
    int? callId,
    int? callerUserId,
    int? calleeUserId,
    String? callerName,
    String? calleeName,
    CallStateV2? state,
    DateTime? callStartedAt,
    DateTime? endedAt,
    CallEndReasonV2? endReason,
    String? callType,
  }) {
    return CallSessionV2(
      callId: callId ?? this.callId,
      callerUserId: callerUserId ?? this.callerUserId,
      calleeUserId: calleeUserId ?? this.calleeUserId,
      callerName: callerName ?? this.callerName,
      calleeName: calleeName ?? this.calleeName,
      state: state ?? this.state,
      createdAt: createdAt,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      callType: callType ?? this.callType,
    );
  }

  /// Длительность разговора (если звонок состоялся).
  Duration? get callDuration {
    if (callStartedAt == null || endedAt == null) return null;
    return endedAt!.difference(callStartedAt!);
  }

  /// Является ли сессия активной.
  bool get isActive => state.isActive;

  /// Является ли сессия завершённой.
  bool get isFinal => state.isFinal;

  @override
  String toString() =>
      'CallSessionV2(callId: $callId, state: $state, '
      'callerUserId: $callerUserId, calleeUserId: $calleeUserId)';
}

/// Стандартизированные причины завершения звонка V2.
enum CallEndReasonV2 {
  /// Пользователь завершил звонок.
  localEnd('local_end', 'Вы завершили звонок'),

  /// Удалённый пользователь завершил звонок.
  remoteEnd('remote_end', 'Собеседник завершил звонок'),

  /// Вызов отклонён.
  rejected('rejected', 'Звонок отклонён'),

  /// Вызов не принят (таймаут).
  timeoutNoAnswer('timeout_no_answer', 'Собеседник не ответил'),

  /// Потеря соединения.
  connectionLost('connection_lost', 'Соединение потеряно'),

  /// Ошибка медиа (WebRTC).
  mediaFailed('media_failed', 'Ошибка подключения'),

  /// Системная ошибка.
  systemError('system_error', 'Системная ошибка'),

  /// Звонок отменён (исходящий отменён до ответа).
  cancelled('cancelled', 'Звонок отменён'),

  /// Неизвестная причина.
  unknown('unknown', 'Неизвестная причина');

  final String value;
  final String label;

  const CallEndReasonV2(this.value, this.label);
}
