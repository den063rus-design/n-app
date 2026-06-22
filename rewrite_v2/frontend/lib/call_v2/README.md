# Frontend Call V2

Изолированная зона нового call-flow.

## Архитектура

```
Transport event → Coordinator → State Machine → UI Intents
```

### Слои

| Слой | Файл | Роль |
|------|------|------|
| Состояния | [`call_state.dart`](call_state.dart) | Enum состояний с категорией и label |
| События | [`call_event.dart`](call_event.dart) | Типы событий, сгруппированные по сценариям |
| UI Intents | [`call_ui_intent.dart`](call_ui_intent.dart) | Команды для UI-слоя (без Navigator/setState) |
| Сессия | [`call_session_v2.dart`](call_session_v2.dart) | Модель одной сессии звонка |
| State Machine | [`call_state_machine_v2.dart`](call_state_machine_v2.dart) | Чистая таблица переходов |
| Coordinator | [`call_coordinator_v2.dart`](call_coordinator_v2.dart) | Оркестратор: событие → state machine → intents |

### Состояния (9)

`idle → outgoing → accepting → inCall → ending → ended`
`idle → incoming → accepting → inCall → ending → ended`
`idle → outgoing → ended` (rejected/cancelled/timeout)
`idle → incoming → ended` (rejected/timeout/remote end)
`* → failed` (connection lost / media failed)
`ended/failed → idle` (только через ResetEvent)

### События (14)

- **Исходящий**: StartOutgoing, RemoteAccepted, RemoteRejected
- **Входящий**: ReceiveIncoming, Accept, Reject
- **Медиа**: MediaConnected, MediaFailed
- **Сеть**: SocketLost, PeerDisconnected
- **Завершение**: LocalEnd, RemoteEnd
- **Уведомления**: PushTapped, NotificationCancelled
- **Таймаут**: TimeoutNoAnswer

### UI Intents (11)

- Навигация: ShowOutgoingCall, ShowIncomingCall, ShowActiveCall, DismissCallScreen
- Статус: UpdateCallStatus, ShowCallError, ShowCallDuration
- Завершение: ShowCallEnded, ShowCallFailed
- Звук: PlayRingtone, StopRingtone

### Причины завершения (9)

localEnd, remoteEnd, rejected, timeoutNoAnswer, connectionLost, mediaFailed, systemError, cancelled, unknown

## Принципы

- Нет вызова Navigator/setState.
- Нет интеграции с реальными socket/push сервисами.
- State machine — чистая функция без сайд-эффектов.
- Coordinator генерирует intents, UI сам решает, как их обработать.
- Каждый файл — маленький и понятный.
