import 'notification_event_v2.dart';

/// Результат обработки tap на уведомлении.
///
/// Содержит:
/// - [NotificationActionV2] — что делать после tap
/// - флаг, нужно ли передать управление call coordinator'у
class TapHandlingResult {
  final NotificationActionV2 action;
  final bool shouldRouteToCallCoordinator;

  const TapHandlingResult({
    required this.action,
    this.shouldRouteToCallCoordinator = false,
  });
}

/// Роутер для обработки tap на уведомлении.
///
/// Отвечает за:
/// 1. Приём [NotificationRoutingDecisionV2] (уже распарсенного роутером).
/// 2. Принятие решения: что открыть после tap.
/// 3. Возврат [TapHandlingResult] с действием.
///
/// Разделение:
/// - Роутер (incoming_call / message) решает, что показать.
/// - TapRouter решает, что открыть после tap пользователя.
/// - Это позволяет переиспользовать TapRouter для разных transport-слоёв.
class NotificationTapRouterV2 {
  /// Обработать tap на уведомлении.
  ///
  /// [decision] — результат роутинга (уже распарсенное уведомление).
  TapHandlingResult handleTap(NotificationRoutingDecisionV2 decision) {
    switch (decision.category) {
      case NotificationCategoryV2.incomingCall:
        return _handleIncomingCallTap(decision);
      case NotificationCategoryV2.message:
        return _handleMessageTap(decision);
      case NotificationCategoryV2.system:
        return _handleSystemTap(decision);
      case NotificationCategoryV2.unknown:
        return _handleUnknownTap(decision);
    }
  }

  TapHandlingResult _handleIncomingCallTap(
    NotificationRoutingDecisionV2 decision,
  ) {
    // Tap на уведомлении о входящем звонке → открыть экран звонка
    // и передать управление call coordinator'у
    return TapHandlingResult(
      action: ShowIncomingCallAction(
        callerId: decision.callerId ?? '',
        sessionId: decision.callSessionId ?? '',
        callerName: decision.callerName,
        callType: decision.callType,
      ),
      shouldRouteToCallCoordinator: true,
    );
  }

  TapHandlingResult _handleMessageTap(
    NotificationRoutingDecisionV2 decision,
  ) {
    // Tap на уведомлении о сообщении → открыть чат
    return TapHandlingResult(
      action: OpenChatAction(
        chatId: decision.chatId ?? '',
        messageId: decision.messageId,
      ),
      shouldRouteToCallCoordinator: false,
    );
  }

  TapHandlingResult _handleSystemTap(
    NotificationRoutingDecisionV2 decision,
  ) {
    // Системное уведомление — пока игнорируем
    return const TapHandlingResult(
      action: IgnoreAction(),
      shouldRouteToCallCoordinator: false,
    );
  }

  TapHandlingResult _handleUnknownTap(
    NotificationRoutingDecisionV2 decision,
  ) {
    // Неизвестное уведомление — игнорируем
    return const TapHandlingResult(
      action: IgnoreAction(),
      shouldRouteToCallCoordinator: false,
    );
  }
}
