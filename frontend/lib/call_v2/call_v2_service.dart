import 'dart:async';
import 'package:flutter/foundation.dart';
import 'call_coordinator_v2.dart';
import 'call_event.dart';
import 'call_session_v2.dart';
import 'call_ui_intent.dart';
import 'call_state.dart';

/// V2 Service — тонкий адаптер над CallCoordinatorV2.
///
/// Принимает реальные события приложения, конвертирует их в V2 events,
/// эмитит наружу состояние сессии и UI intents.
///
/// Singleton, стиль — как в текущем проекте.
class CallV2Service {
  CallV2Service._();

  static final CallV2Service instance = CallV2Service._();

  CallCoordinatorV2? _coordinator;
  String? _initializedLocalUserId;

  /// Pending event, сохранённый до инициализации coordinator'а.
  /// Используется для cold-start: push tap приходит до init().
  CallEventV2? _pendingStartupEvent;

  /// Stream состояния сессии.
  final StreamController<CallSessionV2?> _sessionController =
      StreamController<CallSessionV2?>.broadcast();
  Stream<CallSessionV2?> get sessionStream => _sessionController.stream;

  /// Stream UI intents.
  final StreamController<CallUiIntentV2> _intentController =
      StreamController<CallUiIntentV2>.broadcast();
  Stream<CallUiIntentV2> get intentStream => _intentController.stream;

  /// Текущая сессия.
  CallSessionV2? get session => _coordinator?.session;

  /// Инициализация.
  void init({required String localUserId}) {
    debugPrint('[V2] init(localUserId: $localUserId)');
    // Защита от повторной инициализации тем же userId
    if (_initializedLocalUserId == localUserId) return;

    _initializedLocalUserId = localUserId;
    _coordinator = CallCoordinatorV2(localUserId: localUserId);

    // Replay pending startup event (cold-start: push tap до init).
    // Используем scheduleMicrotask, чтобы дать app shell время завершить
    // initState и гарантированно подписаться на intentStream.
    // _pendingStartupEvent очищается ТОЛЬКО после успешного _handle().
    if (_pendingStartupEvent != null) {
      final pending = _pendingStartupEvent;
      _pendingStartupEvent = null; // очищаем ДО replay, чтобы избежать цикла
      debugPrint('[V2] REPLAY pending startup event via scheduleMicrotask: ${pending!.runtimeType}');
      scheduleMicrotask(() {
        _handle(pending);
      });
    }
  }

  /// Обработать событие через coordinator.
  void _handle(CallEventV2 event) {
    // Если coordinator ещё не инициализирован — сохраняем событие для replay
    if (_coordinator == null) {
      if (event is ReceiveIncomingEvent || event is PushTappedEvent) {
        _pendingStartupEvent = event;
        debugPrint('[V2] QUEUED startup event: ${event.runtimeType} (coordinator not ready)');
      }
      return;
    }

    final oldState = _coordinator!.session?.state;

    // Guard: не обрабатывать поздние события прошлого звонка в финальном состоянии.
    // Разрешены: ResetEvent (сброс), StartOutgoingEvent (новый исходящий),
    // ReceiveIncomingEvent (новый входящий).
    if (oldState == CallStateV2.ended || oldState == CallStateV2.failed) {
      if (event is ResetEvent ||
          event is StartOutgoingEvent ||
          event is ReceiveIncomingEvent) {
        // Разрешено — пропускаем.
      } else {
        debugPrint('[V2] SKIP late event ${event.runtimeType} — already in $oldState');
        return;
      }
    }

    debugPrint('[V2] >>> event: ${event.runtimeType} | oldState: $oldState');

    _coordinator!.handleEvent(event, onIntent: (intent) {
      debugPrint('[V2] >>> intent: ${intent.runtimeType}');
      _intentController.add(intent);
    });

    final newState = _coordinator!.session?.state;
    debugPrint('[V2] <<< newState: $newState | endReason: ${_coordinator!.session?.endReason}');

    _sessionController.add(_coordinator!.session);
  }

  // ===================================================================
  // Публичные методы для вызова из call_service.dart / UI
  // ===================================================================

  /// Ранний старт исходящего звонка — создаёт V2 session сразу,
  /// до получения реального callId от backend.
  ///
  /// callId = 0 (placeholder), будет обновлён позже через [updateOutgoingCallId].
  void handleStartOutgoingEarly({
    required int calleeId,
    String? callType,
  }) {
    _handle(StartOutgoingEvent(
      calleeId: calleeId,
      callType: callType,
      callId: 0, // placeholder, будет обновлён
    ));
  }

  /// Обновление реального callId в существующей исходящей V2 session.
  ///
  /// Вызывается из call:started. Не запускает state machine,
  /// не генерирует новые UI intents.
  void updateOutgoingCallId(int callId) {
    if (_coordinator == null) return;
    _coordinator!.updateCallId(callId);
    _sessionController.add(_coordinator!.session);
  }

  void handleStartOutgoing({
    required int calleeId,
    String? callType,
    int? callId,
  }) {
    _handle(StartOutgoingEvent(
      calleeId: calleeId,
      callType: callType,
      callId: callId,
    ));
  }

  void handleIncoming({
    required int callerUserId,
    required int callId,
    String? callType,
    String? callerName,
  }) {
    _handle(ReceiveIncomingEvent(
      callerUserId: callerUserId,
      callId: callId,
      callType: callType,
      callerName: callerName,
    ));
  }

  /// V2 bootstrap для push tap / cold-start.
  ///
  /// Создаёт incoming V2 session из push payload, если:
  /// - нет активной V2 session
  /// - или есть, но это другой callId (старый звонок)
  ///
  /// Не дублирует сессию, если она уже активна по этому callId.
  /// Не конфликтует с socket incoming (ReceiveIncomingEvent).
  ///
  /// Вызывается из push_service.dart при tap по call push,
  /// даже если kUseCallV2=false (но kUseCallV2UiFlow=true).
  void handleIncomingFromPushTap({
    required int callId,
    required int callerId,
    String? callerName,
    String? callType,
  }) {
    final currentSession = session;

    // Если сессия уже есть и это тот же callId — ничего не делаем
    if (currentSession != null && currentSession.callId == callId) {
      debugPrint('[V2] handleIncomingFromPushTap — session already exists for callId=$callId, skipping');
      return;
    }

    // Если сессия уже есть и это другой callId — игнорируем (старый звонок)
    if (currentSession != null && currentSession.callId != callId && currentSession.callId != 0) {
      debugPrint('[V2] handleIncomingFromPushTap — existing session for different callId=${currentSession.callId}, ignoring push tap for callId=$callId');
      return;
    }

    // Если coordinator ещё не инициализирован — сохраняем для replay
    if (_coordinator == null) {
      _pendingStartupEvent = ReceiveIncomingEvent(
        callerUserId: callerId,
        callId: callId,
        callType: callType,
        callerName: callerName,
      );
      debugPrint('[V2] handleIncomingFromPushTap — QUEUED for replay (coordinator not ready)');
      return;
    }

    debugPrint('[V2] handleIncomingFromPushTap — bootstrapping incoming session (callId=$callId, callerId=$callerId)');
    _handle(ReceiveIncomingEvent(
      callerUserId: callerId,
      callId: callId,
      callType: callType,
      callerName: callerName,
    ));
  }

  void handleAccept() {
    _handle(const AcceptEvent());
  }

  void handleReject({String? reason}) {
    _handle(RejectEvent(reason: reason));
  }

  void handleRemoteAccepted({required int remoteCallId}) {
    _handle(RemoteAcceptedEvent(remoteCallId: remoteCallId));
  }

  void handleRemoteRejected({String? reason}) {
    _handle(RemoteRejectedEvent(reason: reason));
  }

  void handleRemoteEnded({String? reason}) {
    _handle(RemoteEndEvent(reason: reason));
  }

  void handleLocalEnd() {
    _handle(const LocalEndEvent());
  }

  void handleTimeout({required String direction}) {
    _handle(TimeoutNoAnswerEvent(direction: direction));
  }

  void handleMediaConnected() {
    _handle(const MediaConnectedEvent());
  }

  void handleMediaFailed({required String error}) {
    _handle(MediaFailedEvent(error: error));
  }

  void handleSocketLost({String? error}) {
    _handle(SocketLostEvent(error: error));
  }

  void handlePeerDisconnected({String? reason}) {
    _handle(PeerDisconnectedEvent(reason: reason));
  }

  void handlePushTapped({required String payload}) {
    _handle(PushTappedEvent(payload: payload));
  }

  void handleNotificationCancelled({String? notificationId}) {
    _handle(NotificationCancelledEvent(notificationId: notificationId));
  }

  /// Сброс сессии через ResetEvent.
  void reset() {
    debugPrint('[V2] reset()');
    _coordinator?.reset();
    _sessionController.add(null);
  }

  /// Освобождение ресурсов.
  void dispose() {
    _sessionController.close();
    _intentController.close();
  }
}