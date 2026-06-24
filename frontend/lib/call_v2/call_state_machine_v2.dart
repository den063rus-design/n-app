import 'call_state.dart';
import 'call_event.dart';
import 'call_session_v2.dart';

/// Результат обработки события state machine.
///
/// Содержит новое состояние и опциональную причину завершения.
class StateMachineResult {
  final CallStateV2 newState;
  final CallEndReasonV2? endReason;

  const StateMachineResult({
    required this.newState,
    this.endReason,
  });
}

/// V2 State Machine для звонков.
///
/// Чистая функция: на вход получает текущее состояние + событие,
/// на выход — новое состояние + опциональную причину завершения.
///
/// Не содержит сайд-эффектов, не вызывает coordinator, не знает про UI.
///
/// ## Lifecycle
///
/// ### Исходящий звонок
///   idle → outgoing → accepting → inCall → ending → ended
///   idle → outgoing → ended (rejected / cancelled / timeout)
///   idle → outgoing → failed (connection lost)
///
/// ### Входящий звонок
///   idle → incoming → accepting → inCall → ending → ended
///   idle → incoming → ended (rejected / timeout / remote end)
///   idle → incoming → failed (connection lost)
///
/// ### Восстановление после финала
///   ended → idle (только через ResetEvent)
///   failed → idle (только через ResetEvent)
class CallStateMachineV2 {
  /// Обработать событие и вернуть результат перехода.
  ///
  /// Если переход не определён для данной пары (state, event),
  /// возвращается [StateMachineResult] с тем же состоянием.
  static StateMachineResult transition(
    CallStateV2 currentState,
    CallEventV2 event,
  ) {
    return _transitions[currentState]?.call(event) ??
        StateMachineResult(newState: currentState);
  }

  /// Таблица переходов: текущее состояние -> функция(event) -> новое состояние.
  ///
  /// Каждая функция возвращает [StateMachineResult] с новым состоянием
  /// и опциональной причиной завершения (для ended/failed).
  static final Map<CallStateV2, StateMachineResult Function(CallEventV2)>
      _transitions = {
    // ================================================================
    // idle
    // ================================================================
    CallStateV2.idle: (event) {
      if (event is StartOutgoingEvent) {
        return const StateMachineResult(newState: CallStateV2.outgoing);
      }
      if (event is ReceiveIncomingEvent) {
        return const StateMachineResult(newState: CallStateV2.incoming);
      }
      return const StateMachineResult(newState: CallStateV2.idle);
    },

    // ================================================================
    // outgoing
    // ================================================================
    CallStateV2.outgoing: (event) {
      if (event is RemoteAcceptedEvent) {
        return const StateMachineResult(newState: CallStateV2.accepting);
      }
      if (event is RemoteRejectedEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.rejected,
        );
      }
      if (event is LocalEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.cancelled,
        );
      }
      if (event is TimeoutNoAnswerEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.timeoutNoAnswer,
        );
      }
      if (event is SocketLostEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      return const StateMachineResult(newState: CallStateV2.outgoing);
    },

    // ================================================================
    // incoming
    // ================================================================
    CallStateV2.incoming: (event) {
      if (event is AcceptEvent) {
        return const StateMachineResult(newState: CallStateV2.accepting);
      }
      if (event is RejectEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.rejected,
        );
      }
      if (event is TimeoutNoAnswerEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.timeoutNoAnswer,
        );
      }
      if (event is RemoteEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.remoteEnd,
        );
      }
      if (event is SocketLostEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      return const StateMachineResult(newState: CallStateV2.incoming);
    },

    // ================================================================
    // accepting
    // ================================================================
    CallStateV2.accepting: (event) {
      if (event is MediaConnectedEvent) {
        return const StateMachineResult(newState: CallStateV2.inCall);
      }
      if (event is MediaFailedEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.mediaFailed,
        );
      }
      if (event is LocalEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.localEnd,
        );
      }
      if (event is RemoteEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.remoteEnd,
        );
      }
      if (event is PeerDisconnectedEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      if (event is SocketLostEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      return const StateMachineResult(newState: CallStateV2.accepting);
    },

    // ================================================================
    // connecting — НЕ ИСПОЛЬЗУЕТСЯ в переходах.
    // Оставлен для обратной совместимости enum'а.
    // Lifecycle: accepting → inCall (без промежуточного connecting).
    // ================================================================
    CallStateV2.connecting: (event) {
      return const StateMachineResult(newState: CallStateV2.connecting);
    },

    // ================================================================
    // inCall
    // ================================================================
    CallStateV2.inCall: (event) {
      if (event is LocalEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.localEnd,
        );
      }
      if (event is RemoteEndEvent) {
        return const StateMachineResult(
          newState: CallStateV2.ended,
          endReason: CallEndReasonV2.remoteEnd,
        );
      }
      if (event is PeerDisconnectedEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      if (event is SocketLostEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.connectionLost,
        );
      }
      if (event is MediaFailedEvent) {
        return const StateMachineResult(
          newState: CallStateV2.failed,
          endReason: CallEndReasonV2.mediaFailed,
        );
      }
      return const StateMachineResult(newState: CallStateV2.inCall);
    },

    // ================================================================
    // ending
    // ================================================================
    CallStateV2.ending: (event) {
      // В ending мы уже пришли с конкретной причиной (localEnd или remoteEnd).
      // State machine НЕ подменяет endReason — она сохраняет тот,
      // который был установлен при входе в ending.
      // Coordinator отвечает за то, чтобы endReason из inCall → ending
      // был корректно передан в ended.
      return const StateMachineResult(newState: CallStateV2.ended);
    },

    // ================================================================
    // ended (финальное)
    // ================================================================
    CallStateV2.ended: (event) {
      if (event is ResetEvent) {
        return const StateMachineResult(newState: CallStateV2.idle);
      }
      if (event is StartOutgoingEvent) {
        return const StateMachineResult(newState: CallStateV2.outgoing);
      }
      if (event is ReceiveIncomingEvent) {
        return const StateMachineResult(newState: CallStateV2.incoming);
      }
      return const StateMachineResult(newState: CallStateV2.ended);
    },

    // ================================================================
    // failed (финальное)
    // ================================================================
    CallStateV2.failed: (event) {
      if (event is ResetEvent) {
        return const StateMachineResult(newState: CallStateV2.idle);
      }
      if (event is StartOutgoingEvent) {
        return const StateMachineResult(newState: CallStateV2.outgoing);
      }
      if (event is ReceiveIncomingEvent) {
        return const StateMachineResult(newState: CallStateV2.incoming);
      }
      return const StateMachineResult(newState: CallStateV2.failed);
    },
  };
}
