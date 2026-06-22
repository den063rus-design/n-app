# Call V2 Contract

## Общее описание

Документ описывает транспортный контракт между клиентом и сервером для V2 call-flow.

**Протокол:** Socket (WebSocket)  
**Формат:** JSON  
**Кодировка:** UTF-8  
**Версия:** 2.0

---

## 1. Lifecycle звонка

### 1.1 Исходящий звонок (outgoing)

```
Client                  Server                  Remote Client
  |                       |                       |
  |-- call:start -------->|                       |
  |                       |-- call:incoming ----->|
  |                       |                       |
  |                       |   (ожидание ответа)   |
  |                       |                       |
  |<-- call:remote_ack ---|                       |
  |    (или timeout)      |                       |
  |                       |                       |
  |                       |<-- call:accept -------| (или reject)
  |                       |                       |
  |<-- call:remote_acc ---|                       |
  |    (или remote_rej)   |                       |
  |                       |                       |
  |-- media:offer ------->|                       |
  |                       |-- media:offer ------->|
  |<-- media:answer ------|<-- media:answer ------|
  |                       |                       |
  |-- media:ice --------->|                       |
  |                       |-- media:ice --------->|
  |                       |                       |
  |<-- media:connected ---|                       |
  |                       |                       |
  |     === IN CALL ===   |                       |
  |                       |                       |
  |-- call:end ---------->|                       |
  |                       |-- call:remote_end --->|
  |                       |                       |
```

### 1.2 Входящий звонок (incoming)

```
Client                  Server                  Remote Client
  |                       |                       |
  |<-- call:incoming -----|                       |
  |                       |                       |
  |-- call:accept ------->|                       |
  |    (или reject)       |                       |
  |                       |-- call:remote_acc --->|
  |                       |    (или remote_rej)   |
  |                       |                       |
  |     ... media signaling ...                    |
  |                       |                       |
  |<-- media:connected ---|                       |
  |                       |                       |
  |     === IN CALL ===   |                       |
```

### 1.3 Завершение звонка

```
Любая сторона может инициировать завершение:

Client                  Server                  Remote Client
  |                       |                       |
  |-- call:end ---------->|                       |
  |                       |-- call:remote_end --->|
  |                       |                       |
  |     или               |                       |
  |                       |                       |
  |<-- call:remote_end ---|<-- call:end ----------|
  |                       |                       |
```

### 1.4 Потеря соединения

```
Client                  Server
  |                       |
  |     (socket lost)     |
  |                       |
  |                       |-- call:peer_disconnected --> (если есть remote)
  |                       |
  |                       |-- call:timeout (через N сек)
```

---

## 2. События

### 2.1 Client → Server

| Событие | Payload | Ack | Описание |
|---------|---------|-----|----------|
| `call:start` | `{ calleeId, callType }` | `{ success, sessionId }` | Инициировать звонок |
| `call:accept` | `{ sessionId, timestamp }` | `{ success }` | Принять входящий звонок |
| `call:reject` | `{ sessionId, timestamp, reason? }` | `{ success }` | Отклонить входящий звонок |
| `call:end` | `{ sessionId, timestamp, reason }` | `{ success }` | Завершить звонок |
| `media:offer` | `{ sessionId, timestamp, sdp }` | `{ success }` | WebRTC offer |
| `media:answer` | `{ sessionId, timestamp, sdp }` | `{ success }` | WebRTC answer |
| `media:ice_candidate` | `{ sessionId, timestamp, iceCandidate }` | `{ success }` | ICE candidate |

### 2.2 Server → Client

| Событие | Payload | Описание |
|---------|---------|----------|
| `call:incoming` | `{ sessionId, callerId, callerName?, callType, timestamp }` | Новый входящий звонок |
| `call:remote_accepted` | `{ sessionId, timestamp }` | Удалённая сторона приняла звонок |
| `call:remote_rejected` | `{ sessionId, timestamp, reason? }` | Удалённая сторона отклонила звонок |
| `call:remote_end` | `{ sessionId, timestamp, reason }` | Удалённая сторона завершила звонок |
| `media:connected` | `{ sessionId, timestamp }` | WebRTC соединение установлено |
| `media:failed` | `{ sessionId, timestamp, error }` | WebRTC соединение не удалось |
| `call:timeout` | `{ sessionId, timestamp, direction }` | Таймаут ожидания ответа |
| `call:peer_disconnected` | `{ sessionId, timestamp, reason? }` | Удалённый участник отключился |

---

## 3. Ack-события

Ack — это ответ сервера на client → server событие.

| Событие | Успешный ack | Ошибка |
|---------|-------------|--------|
| `call:start` | `{ success: true, sessionId: "sess_xxx" }` | `{ success: false, error: "callee_busy" }` |
| `call:accept` | `{ success: true }` | `{ success: false, error: "session_not_found" }` |
| `call:reject` | `{ success: true }` | `{ success: false, error: "session_not_found" }` |
| `call:end` | `{ success: true }` | `{ success: false, error: "session_not_found" }` |
| `media:*` | `{ success: true }` | `{ success: false, error: "invalid_sdp" }` |

### Возможные ошибки ack

| Код ошибки | Описание |
|-----------|----------|
| `callee_busy` | Пользователь занят (уже в звонке) |
| `callee_offline` | Пользователь не в сети |
| `session_not_found` | Сессия не найдена или уже завершена |
| `invalid_sdp` | Некорректный SDP |
| `media_timeout` | Таймаут медиа-соединения |
| `internal_error` | Внутренняя ошибка сервера |

---

## 4. Причины завершения (End Reasons)

Стандартизированный набор причин завершения звонка.

| Код | Описание | Инициатор | Когда возникает |
|-----|----------|-----------|----------------|
| `local_end` | Пользователь завершил звонок | Клиент | Нажатие кнопки "завершить" |
| `remote_end` | Собеседник завершил звонок | Сервер | Получено `call:end` от remote |
| `rejected` | Звонок отклонён | Сервер | Получено `call:reject` |
| `timeout_no_answer` | Собеседник не ответил | Сервер | Таймаут N секунд |
| `connection_lost` | Потеря соединения | Сервер | Socket disconnect > N сек |
| `media_failed` | Ошибка WebRTC | Сервер | media:failed |
| `system_error` | Системная ошибка | Сервер | Внутренняя ошибка |
| `cancelled` | Звонок отменён (до ответа) | Клиент | Отмена исходящего |
| `unknown` | Неизвестная причина | — | Fallback |

---

## 5. Таймауты

| Таймаут | Значение | Описание |
|---------|----------|----------|
| `CALL_TIMEOUT_MS` | 30000 (30s) | Ожидание ответа на входящий/исходящий звонок |
| `MEDIA_TIMEOUT_MS` | 15000 (15s) | Ожидание WebRTC соединения |
| `RECONNECT_GRACE_MS` | 10000 (10s) | Grace period после потери socket |

---

## 6. Примеры payload

### call:start (client → server)
```json
{
  "event": "call:start",
  "payload": {
    "calleeId": "user_456",
    "callType": "video"
  }
}
```

### call:incoming (server → client)
```json
{
  "event": "call:incoming",
  "payload": {
    "sessionId": "sess_abc123",
    "callerId": "user_123",
    "callerName": "John",
    "callType": "video",
    "timestamp": "2026-06-22T10:00:00.000Z"
  }
}
```

### call:end (client → server)
```json
{
  "event": "call:end",
  "payload": {
    "sessionId": "sess_abc123",
    "timestamp": "2026-06-22T10:05:00.000Z",
    "reason": "local_end"
  }
}
```

---

## 7. Примечания

- Все timestamp в формате ISO 8601 (UTC).
- Сервер НЕ хранит историю звонков — это задача отдельного сервиса.
- Media signaling (offer/answer/ICE) проксируется через сервер.
- При потере соединения сервер ждёт RECONNECT_GRACE_MS, затем завершает звонок.
- Одна сессия = один звонок. Нет поддержки конференций в V2.
