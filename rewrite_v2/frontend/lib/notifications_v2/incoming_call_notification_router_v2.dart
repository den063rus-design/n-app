import 'dart:convert';

import 'notification_event_v2.dart';

/// Роутер для уведомлений о входящих звонках.
///
/// Отвечает за:
/// 1. Парсинг transport event в routing decision.
/// 2. Принятие решения: показать уведомление или экран звонка.
/// 3. Возврат [NotificationActionV2] для выполнения.
///
/// Логика:
/// - Если приложение в foreground → показать экран входящего звонка.
/// - Если приложение в background → показать system notification.
class IncomingCallNotificationRouterV2 {
  /// Обработать transport event и вернуть действие.
  NotificationActionV2 route(NotificationTransportEventV2 event) {
    final decision = _parse(event);

    if (decision.category != NotificationCategoryV2.incomingCall) {
      return const IgnoreAction();
    }

    return _decideAction(event.transportType, decision);
  }

  /// Распарсить transport event в routing decision.
  ///
  /// Ожидаемый JSON payload:
  /// ```json
  /// {"type":"incoming_call","caller_id":"user_123","session_id":"sess_456","call_type":"video"}
  /// ```
  NotificationRoutingDecisionV2 _parse(NotificationTransportEventV2 event) {
    try {
      final json = jsonDecode(event.payload) as Map<String, dynamic>;

      final type = json['type'] as String?;
      if (type != 'incoming_call') {
        return NotificationRoutingDecisionV2(
          category: NotificationCategoryV2.unknown,
          rawPayload: event.payload,
        );
      }

      final callerId = json['caller_id'] as String?;
      final callerName = json['caller_name'] as String?;
      final sessionId = json['session_id'] as String?;
      final callType = json['call_type'] as String?;

      if (callerId == null || sessionId == null) {
        return NotificationRoutingDecisionV2(
          category: NotificationCategoryV2.unknown,
          rawPayload: event.payload,
        );
      }

      return NotificationRoutingDecisionV2(
        category: NotificationCategoryV2.incomingCall,
        callSessionId: sessionId,
        callerId: callerId,
        callerName: callerName,
        callType: callType,
        rawPayload: event.payload,
      );
    } catch (_) {
      // Ошибка парсинга JSON — unknown
      return NotificationRoutingDecisionV2(
        category: NotificationCategoryV2.unknown,
        rawPayload: event.payload,
      );
    }
  }

  /// Принять решение: показать экран или system notification.
  NotificationActionV2 _decideAction(
    NotificationTransportTypeV2 transportType,
    NotificationRoutingDecisionV2 decision,
  ) {
    if (transportType == NotificationTransportTypeV2.pushForeground) {
      // Приложение активно — показываем экран входящего звонка
      return ShowIncomingCallAction(
        callerId: decision.callerId ?? '',
        sessionId: decision.callSessionId ?? '',
        callerName: decision.callerName,
        callType: decision.callType,
      );
    }

    // Приложение в background или локальное — system notification
    return ShowNotificationAction(
      title: 'Входящий звонок',
      body: decision.callerName != null
          ? 'Звонок от ${decision.callerName}'
          : (decision.callerId != null
              ? 'Звонок от ${decision.callerId}'
              : 'Входящий звонок'),
      payload: decision.rawPayload,
    );
  }
}
