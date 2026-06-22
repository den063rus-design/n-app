# Backend Call V2

Изолированная зона нового backend call contract.

## Файлы

| Файл | Роль |
|------|------|
| [`call-v2.types.ts`](call-v2.types.ts) | Базовые типы: состояния, end reasons, участники, мета-информация сессии |
| [`call-v2.events.ts`](call-v2.events.ts) | Все socket-события: client→server и server→client с payload и ack |
| [`call-v2.state.ts`](call-v2.state.ts) | Состояние сессии на backend + in-memory store |
| [`call-v2.contract.md`](call-v2.contract.md) | Полный контракт: lifecycle, события, ack, end reasons, таймауты, примеры |

## События

### Client → Server (7)

| Событие | Описание |
|---------|----------|
| `call:start` | Инициировать звонок |
| `call:accept` | Принять входящий звонок |
| `call:reject` | Отклонить входящий звонок |
| `call:end` | Завершить звонок |
| `media:offer` | WebRTC offer |
| `media:answer` | WebRTC answer |
| `media:ice_candidate` | ICE candidate |

### Server → Client (8)

| Событие | Описание |
|---------|----------|
| `call:incoming` | Новый входящий звонок |
| `call:remote_accepted` | Удалённая сторона приняла звонок |
| `call:remote_rejected` | Удалённая сторона отклонила звонок |
| `call:remote_end` | Удалённая сторона завершила звонок |
| `media:connected` | WebRTC соединение установлено |
| `media:failed` | WebRTC соединение не удалось |
| `call:timeout` | Таймаут ожидания ответа |
| `call:peer_disconnected` | Удалённый участник отключился |

## Причины завершения (9)

`local_end`, `remote_end`, `rejected`, `timeout_no_answer`, `connection_lost`, `media_failed`, `system_error`, `cancelled`, `unknown`

## Таймауты

- CALL_TIMEOUT_MS: 30s
- MEDIA_TIMEOUT_MS: 15s
- RECONNECT_GRACE_MS: 10s

## Принципы

- Нет интеграции с реальным gateway.
- Нет подключения к БД.
- In-memory store для активных сессий.
- Все события типизированы.
- Контракт описан в markdown для согласования.
