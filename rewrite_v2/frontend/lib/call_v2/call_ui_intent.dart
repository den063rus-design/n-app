/// UI Intents V2.
///
/// Это "что UI должен сделать" — чистые команды для presentation-слоя.
/// Coordinator НЕ вызывает Navigator/setState напрямую, а только эмитит эти intents.
/// UI-слой сам решает, как их обработать (показать экран, обновить состояние и т.д.).
abstract class CallUiIntentV2 {
  const CallUiIntentV2();
}

// ===================================================================
// Навигация
// ===================================================================

/// Показать экран исходящего звонка.
class ShowOutgoingCallIntent extends CallUiIntentV2 {
  final String calleeId;
  final String? callType;

  const ShowOutgoingCallIntent({
    required this.calleeId,
    this.callType,
  });
}

/// Показать экран входящего звонка.
class ShowIncomingCallIntent extends CallUiIntentV2 {
  final String callerId;
  final String sessionId;
  final String? callType;

  const ShowIncomingCallIntent({
    required this.callerId,
    required this.sessionId,
    this.callType,
  });
}

/// Показать экран активного звонка (разговор).
class ShowActiveCallIntent extends CallUiIntentV2 {
  final String sessionId;
  final int? remoteUserId;
  final String? remoteUserName;
  final String? callType;

  const ShowActiveCallIntent({
    required this.sessionId,
    this.remoteUserId,
    this.remoteUserName,
    this.callType,
  });
}

/// Скрыть все call-экраны, вернуться к предыдущему экрану.
class DismissCallScreenIntent extends CallUiIntentV2 {
  const DismissCallScreenIntent();
}

// ===================================================================
// Состояние звонка
// ===================================================================

/// Обновить статус на UI (например, "connecting...", "ending...").
class UpdateCallStatusIntent extends CallUiIntentV2 {
  final String statusLabel;

  const UpdateCallStatusIntent({required this.statusLabel});
}

/// Показать ошибку звонка.
class ShowCallErrorIntent extends CallUiIntentV2 {
  final String message;

  const ShowCallErrorIntent({required this.message});
}

/// Показать таймер длительности звонка.
class ShowCallDurationIntent extends CallUiIntentV2 {
  final Duration duration;

  const ShowCallDurationIntent({required this.duration});
}

// ===================================================================
// Завершение
// ===================================================================

/// Показать экран "звонок завершён" с причиной.
class ShowCallEndedIntent extends CallUiIntentV2 {
  final String endReason;

  const ShowCallEndedIntent({required this.endReason});
}

/// Показать экран "звонок не удался" с ошибкой.
class ShowCallFailedIntent extends CallUiIntentV2 {
  final String error;

  const ShowCallFailedIntent({required this.error});
}

// ===================================================================
// Разное
// ===================================================================

/// Вибрация / звуковой сигнал (для входящего звонка).
class PlayRingtoneIntent extends CallUiIntentV2 {
  final bool isIncoming;

  const PlayRingtoneIntent({required this.isIncoming});
}

/// Остановить звуковой сигнал.
class StopRingtoneIntent extends CallUiIntentV2 {
  const StopRingtoneIntent();
}
