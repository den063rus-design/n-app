import 'dart:convert';

import 'notification_event_v2.dart';

/// Роутер для уведомлений о новых сообщениях.
///
/// Отвечает за:
/// 1. Парсинг transport event в routing decision.
/// 2. Принятие решения: показать system notification или открыть чат.
/// 3. Возврат [NotificationActionV2] для выполнения.
///
/// Логика:
/// - Если приложение в foreground → можно сразу открыть чат (опционально).
/// - Если приложение в background → показать system notification.
class MessageNotificationRouterV2 {
  /// Обработать transport event и вернуть действие.
  NotificationActionV2 route(NotificationTransportEventV2 event) {
    final decision = _parse(event);

    if (decision.category != NotificationCategoryV2.message) {
      return const IgnoreAction();
    }

    return _decideAction(event.transportType, decision);
  }

  /// Распарсить transport event в routing decision.
  ///
  /// Ожидаемый JSON payload:
  /// ```json
  /// {"type":"message","chat_id":"chat_123","message_id":"msg_456"}
  /// ```
  NotificationRoutingDecisionV2 _parse(NotificationTransportEventV2 event) {
    try {
      final json = jsonDecode(event.payload) as Map<String, dynamic>;

      final type = json['type'] as String?;
      if (type != 'message') {
        return NotificationRoutingDecisionV2(
          category: NotificationCategoryV2.unknown,
          rawPayload: event.payload,
        );
      }

      final chatId = json['chat_id'] as String?;
      if (chatId == null) {
        return NotificationRoutingDecisionV2(
          category: NotificationCategoryV2.unknown,
          rawPayload: event.payload,
        );
      }

      final messageId = json['message_id'] as String?;
      final senderName = json['sender_name'] as String?;
      final messageText = json['message_text'] as String?;

      return NotificationRoutingDecisionV2(
        category: NotificationCategoryV2.message,
        chatId: chatId,
        messageId: messageId,
        senderName: senderName,
        messageText: messageText,
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

  /// Принять решение: показать system notification или открыть чат.
  NotificationActionV2 _decideAction(
    NotificationTransportTypeV2 transportType,
    NotificationRoutingDecisionV2 decision,
  ) {
    if (transportType == NotificationTransportTypeV2.pushForeground) {
      // Приложение активно — можно сразу открыть чат
      return OpenChatAction(
        chatId: decision.chatId ?? '',
        messageId: decision.messageId,
      );
    }

    // Приложение в background — system notification
    return ShowNotificationAction(
      title: decision.senderName ?? 'Новое сообщение',
      body: decision.messageText ?? 'У вас новое сообщение',
      payload: decision.rawPayload,
    );
  }
}
