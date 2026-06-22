/// V2 Notification Event.
///
/// Разделение на три уровня:
/// 1. [NotificationTransportEventV2] — сырое событие от транспорта (FCM/APNs/local)
/// 2. [NotificationRoutingDecisionV2] — решение роутера: что делать с уведомлением
/// 3. [NotificationActionV2] — конкретное действие: показать / обработать tap
///
/// Это позволяет:
/// - не смешивать парсинг push с логикой показа
/// - переиспользовать routing для разных transport-слоёв
/// - тестировать каждый уровень изолированно

// ===================================================================
// Transport event — сырое событие от push-сервиса
// ===================================================================

/// Тип источника уведомления.
enum NotificationTransportTypeV2 {
  /// Push-уведомление в foreground (приложение активно).
  pushForeground,

  /// Push-уведомление в background (приложение свёрнуто).
  pushBackground,

  /// Локальное уведомление (создано приложением).
  local,

  /// Тип не определён.
  unknown,
}

/// Сырое событие от transport-слоя (FCM, APNs, local notification).
class NotificationTransportEventV2 {
  final NotificationTransportTypeV2 transportType;
  final String payload; // JSON-строка или сырой payload
  final String? notificationId;

  const NotificationTransportEventV2({
    required this.transportType,
    required this.payload,
    this.notificationId,
  });
}

// ===================================================================
// Routing decision — решение роутера
// ===================================================================

/// Категория уведомления после парсинга.
enum NotificationCategoryV2 {
  /// Входящий звонок.
  incomingCall,

  /// Новое сообщение.
  message,

  /// Системное уведомление.
  system,

  /// Неизвестная категория.
  unknown,
}

/// Решение роутера: что делать с уведомлением.
class NotificationRoutingDecisionV2 {
  final NotificationCategoryV2 category;
  final String? callSessionId;
  final String? callerId;
  final String? callerName;
  final String? callType;
  final String? messageId;
  final String? chatId;
  final String? senderName;
  final String? messageText;
  final String rawPayload;

  const NotificationRoutingDecisionV2({
    required this.category,
    this.callSessionId,
    this.callerId,
    this.callerName,
    this.callType,
    this.messageId,
    this.chatId,
    this.senderName,
    this.messageText,
    required this.rawPayload,
  });
}

// ===================================================================
// Notification action — конкретное действие
// ===================================================================

/// Действие, которое нужно выполнить с уведомлением.
abstract class NotificationActionV2 {
  const NotificationActionV2();
}

/// Показать уведомление в system tray.
class ShowNotificationAction extends NotificationActionV2 {
  final String title;
  final String body;
  final String? payload;

  const ShowNotificationAction({
    required this.title,
    required this.body,
    this.payload,
  });
}

/// Показать экран входящего звонка (для foreground).
class ShowIncomingCallAction extends NotificationActionV2 {
  final String callerId;
  final String sessionId;
  final String? callerName;
  final String? callType;

  const ShowIncomingCallAction({
    required this.callerId,
    required this.sessionId,
    this.callerName,
    this.callType,
  });
}

/// Открыть чат (для message-уведомлений).
class OpenChatAction extends NotificationActionV2 {
  final String chatId;
  final String? messageId;

  const OpenChatAction({
    required this.chatId,
    this.messageId,
  });
}

/// Ничего не делать (уведомление не требует реакции).
class IgnoreAction extends NotificationActionV2 {
  const IgnoreAction();
}
