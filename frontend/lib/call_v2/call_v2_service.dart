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

    // Replay pending startup event (cold-start: push tap до init)
    if (_pendingStartupEvent != null) {
      final pending = _pendingStartupEvent!;
      _pendingStartupEvent = null; // очищаем ДО replay, чтобы избежать цикла
      debugPrint('[V2] REPLAY pending startup event: ${pending.runtimeType}');
      _handle(pending);
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

    // Guard: не обрабатывать события в финальном состоянии (кроме ResetEvent)
    if (oldState == CallStateV2.ended || oldState == CallStateV2.failed) {
      if (event is! ResetEvent) {
        debugPrint('[V2] SKIP event ${event.runtimeType} — already in $oldState');
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