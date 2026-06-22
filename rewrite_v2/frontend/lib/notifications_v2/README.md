# Frontend Notifications V2

Изолированная зона нового notification-flow.

## Архитектура

Разделение на три уровня:

```
Transport event → Routing decision → Notification action
```

### 1. Transport event ([`notification_event_v2.dart`](notification_event_v2.dart))

Сырое событие от push-сервиса (FCM, APNs) или локального уведомления.

- [`NotificationTransportEventV2`](notification_event_v2.dart) — содержит тип транспорта (foreground/background/local) и сырой payload.
- [`NotificationTransportTypeV2`](notification_event_v2.dart) — enum: pushForeground, pushBackground, local, unknown.

### 2. Routing decision ([`notification_event_v2.dart`](notification_event_v2.dart))

Результат парсинга transport event в структурированное решение.

- [`NotificationRoutingDecisionV2`](notification_event_v2.dart) — категория (incomingCall/message/system/unknown), sessionId, callerId, chatId.
- [`NotificationCategoryV2`](notification_event_v2.dart) — enum категорий.

### 3. Notification action ([`notification_event_v2.dart`](notification_event_v2.dart))

Конкретное действие, которое нужно выполнить.

- [`ShowNotificationAction`](notification_event_v2.dart) — показать system notification.
- [`ShowIncomingCallAction`](notification_event_v2.dart) — показать экран входящего звонка.
- [`OpenChatAction`](notification_event_v2.dart) — открыть чат.
- [`IgnoreAction`](notification_event_v2.dart) — ничего не делать.

## Роутеры

### [`IncomingCallNotificationRouterV2`](incoming_call_notification_router_v2.dart)

- Принимает [`NotificationTransportEventV2`](notification_event_v2.dart).
- Парсит payload, извлекает callerId и sessionId.
- Если foreground → [`ShowIncomingCallAction`](notification_event_v2.dart).
- Если background → [`ShowNotificationAction`](notification_event_v2.dart).

### [`MessageNotificationRouterV2`](message_notification_router_v2.dart)

- Принимает [`NotificationTransportEventV2`](notification_event_v2.dart).
- Парсит payload, извлекает chatId и messageId.
- Если foreground → [`OpenChatAction`](notification_event_v2.dart).
- Если background → [`ShowNotificationAction`](notification_event_v2.dart).

### [`NotificationTapRouterV2`](notification_tap_router_v2.dart)

- Принимает [`NotificationRoutingDecisionV2`](notification_event_v2.dart) (уже распарсенное).
- Решает, что открыть после tap пользователя.
- Возвращает [`TapHandlingResult`](notification_tap_router_v2.dart) с action и флагом shouldRouteToCallCoordinator.

## Принципы

- Нет интеграции с реальными push-сервисами.
- Нет вызова Navigator/setState.
- Каждый роутер можно тестировать изолированно.
- Парсинг payload — через jsonDecode с валидацией полей.
