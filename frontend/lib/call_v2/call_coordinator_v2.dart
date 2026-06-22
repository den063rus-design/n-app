import 'package:flutter/foundation.dart';
import 'call_state.dart';
import 'call_event.dart';
import 'call_ui_intent.dart';
import 'call_session_v2.dart';
import 'call_state_machine_v2.dart';

/// Результат обработки события coordinator'ом.
///
/// Содержит:
/// - обновлённую сессию (или null, если сессия сброшена в idle)
/// - список UI intents для presentation-слоя
class CoordinatorResult {
  final CallSessionV2? session;
  final List<CallUiIntentV2> intents;

  const CoordinatorResult({
    this.session,
    this.intents = const [],
  });
}

/// V2 Coordinator звонка.
///
/// Отвечает за orchestration:
/// 1. Принимает событие ([CallEventV2]) от transport-слоя или UI.
/// 2. Прокидывает его в state machine.
/// 3. На основе результата генерирует UI intents.
/// 4. Возвращает [CoordinatorResult] с обновлённой сессией и intents.
///
/// Coordinator НЕ:
/// - не вызывает Navigator напрямую
/// - не вызывает setState
/// - не знает про Widget'ы
/// - не подключается к socket/push сервисам
class CallCoordinatorV2 {
  final String localUserId;
  CallSessionV2? _session;

  /// Guard: последнее эмиченное финальное состояние.
  /// Предотвращает повторную эмиссию UI intents для ended/failed.
  CallStateV2? _lastEmittedFinalState;

  /// Текущая сессия (null = idle).
  CallSessionV2? get session => _session;

  CallCoordinatorV2({required this.localUserId});

  /// Обработать событие.
  ///
  /// [onIntent] — колбэк для каждого сгенерированного intent.
  /// Coordinator не хранит список intent'ов, а сразу эмитит их через колбэк.
  /// Это позволяет UI-слою реагировать мгновенно, не дожидаясь возврата.
  CoordinatorResult handleEvent(
    CallEventV2 event, {
    void Function(CallUiIntentV2 intent)? onIntent,
  }) {
    final currentState = _session?.state ?? CallStateV2.idle;

    // 1. Переход в state machine
    final result = CallStateMachineV2.transition(currentState, event);

    // 2. Обновляем сессию
    _session = _buildSession(_session, event, result);

    // 3. Генерируем intents
    final intents = _buildIntents(event, result);

    // 4. Эмитим через колбэк (если передан)
    for (final intent in intents) {
      onIntent?.call(intent);
    }

    return CoordinatorResult(
      session: _session,
      intents: intents,
    );
  }

  /// Сбросить сессию в idle (например, после закрытия экрана).
  void reset() {
    handleEvent(const ResetEvent());
  }

  // ===================================================================
  // Приватные методы
  // ===================================================================

  /// Построить новую сессию на основе текущей + результата перехода.
  CallSessionV2? _buildSession(
    CallSessionV2? current,
    CallEventV2 event,
    StateMachineResult result,
  ) {
    // Если новое состояние — idle, сбрасываем сессию и guard final state.
    if (result.newState == CallStateV2.idle) {
      _lastEmittedFinalState = null;
      return null;
    }

    // Если сессии ещё нет — создаём новую.
    if (current == null) {
      return _createSessionFromEvent(event, result.newState);
    }

    // Иначе — обновляем существующую.
    // Важно: callStartedAt НЕ обнуляется при выходе из inCall.
    // Если callStartedAt уже был установлен, он сохраняется.
    final DateTime? updatedCallStartedAt;
    if (result.newState == CallStateV2.inCall && current.callStartedAt == null) {
      updatedCallStartedAt = DateTime.now();
    } else {
      updatedCallStartedAt = current.callStartedAt;
    }

    // Сохраняем endReason: если state machine вернула null (как при ending → ended),
    // но в текущей сессии уже есть причина — используем её.
    final resolvedEndReason = result.endReason ?? current.endReason;

    return current.copyWith(
      state: result.newState,
      endReason: resolvedEndReason,
      callStartedAt: updatedCallStartedAt,
      endedAt: result.newState.isFinal
          ? (current.endedAt ?? DateTime.now())
          : null,
    );
  }

  /// Создать новую сессию из события.
  CallSessionV2 _createSessionFromEvent(
    CallEventV2 event,
    CallStateV2 state,
  ) {
    if (event is StartOutgoingEvent) {
      return CallSessionV2(
        callId: event.callId ?? 0,
        callerUserId: int.tryParse(localUserId) ?? 0,
        calleeUserId: event.calleeId,
        state: state,
        callType: event.callType,
      );
    }
    if (event is ReceiveIncomingEvent) {
      return CallSessionV2(
        callId: event.callId,
        callerUserId: event.callerUserId,
        calleeUserId: int.tryParse(localUserId) ?? 0,
        callerName: event.callerName,
        state: state,
        callType: event.callType,
      );
    }
    return CallSessionV2(
      callId: 0,
      state: state,
    );
  }

  /// Сгенерировать список UI intents на основе события и результата.
  List<CallUiIntentV2> _buildIntents(
    CallEventV2 event,
    StateMachineResult result,
  ) {
    final intents = <CallUiIntentV2>[];

    // Guard: не эмитить повторные final intents
    if (result.newState == CallStateV2.ended || result.newState == CallStateV2.failed) {
      if (_lastEmittedFinalState == result.newState) {
        debugPrint('[V2_COORD] SKIP intents — already emitted $result.newState');
        return [];
      }
      _lastEmittedFinalState = result.newState;
    }

    switch (result.newState) {
      case CallStateV2.outgoing:
        if (event is StartOutgoingEvent) {
          intents.add(ShowOutgoingCallIntent(
            calleeUserId: event.calleeId,
            callId: event.callId,
            callType: event.callType,
          ));
          intents.add(const PlayRingtoneIntent(isIncoming: false));
        }
        break;

      case CallStateV2.incoming:
        if (event is ReceiveIncomingEvent) {
          intents.add(ShowIncomingCallIntent(
            callerUserId: event.callerUserId,
            callId: event.callId,
            callerName: event.callerName,
            callType: event.callType,
          ));
          intents.add(const PlayRingtoneIntent(isIncoming: true));
        }
        break;

      case CallStateV2.accepting:
        intents.add(const UpdateCallStatusIntent(statusLabel: 'Соединение...'));
        intents.add(const StopRingtoneIntent());
        break;

      case CallStateV2.connecting:
        intents.add(const UpdateCallStatusIntent(statusLabel: 'Подключение...'));
        break;

      case CallStateV2.inCall:
        final localId = int.tryParse(localUserId) ?? 0;
        final int? remoteUserId;
        final String? remoteUserName;
        if (_session?.callerUserId == localId) {
          remoteUserId = _session?.calleeUserId;
          remoteUserName = _session?.calleeName;
        } else {
          remoteUserId = _session?.callerUserId;
          remoteUserName = _session?.callerName;
        }
        intents.add(ShowActiveCallIntent(
          callId: _session?.callId ?? 0,
          remoteUserId: remoteUserId,
          remoteUserName: remoteUserName,
          callType: _session?.callType,
        ));
        intents.add(const StopRingtoneIntent());
        break;

      case CallStateV2.ending:
        intents.add(const UpdateCallStatusIntent(statusLabel: 'Завершение...'));
        break;

      case CallStateV2.ended:
        final reason = result.endReason ?? _session?.endReason ?? CallEndReasonV2.unknown;
        intents.add(ShowCallEndedIntent(endReason: reason.label));
        intents.add(const DismissCallScreenIntent());
        intents.add(const StopRingtoneIntent());
        break;

      case CallStateV2.failed:
        final reason = result.endReason ?? _session?.endReason ?? CallEndReasonV2.unknown;
        intents.add(ShowCallFailedIntent(error: reason.label));
        intents.add(const DismissCallScreenIntent());
        intents.add(const StopRingtoneIntent());
        break;

      case CallStateV2.idle:
        // Ничего не делаем
        break;
    }

    return intents;
  }

}
