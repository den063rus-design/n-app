# Архитектура N App

Краткая актуальная архитектурная сводка проекта.

## Общая схема

- Backend: `NestJS`
- База данных: `PostgreSQL` через `Prisma`
- Real-time: `Socket.IO`
- Авторизация: `JWT`
- Пароли: `bcrypt`
- Frontend: `Flutter`
- Файлы: локальная папка `uploads/` по умолчанию
- Опционально: `MinIO` через `FILE_STORAGE_DRIVER=minio`

## Основные модули backend

```text
src/
  auth/
  users/
  chat/
  files/
  call/
  notifications/
  common/
  config/
  prisma/
```

## Логические зоны

### `auth`

- вход по `POST /auth/login`
- JWT-проверка HTTP и WebSocket

### `users`

- создание пользователей администратором
- блокировка, разблокировка, архивирование, восстановление
- смена логина и пароля

### `chat`

- текстовые сообщения
- вложения
- статусы `SENT / DELIVERED / READ`
- удаление сообщений только администратором

### `files`

- `POST /files/upload`
- `GET /files/:key(*)`
- `DELETE /files/:key(*)`
- поддержка старых плоских ключей и новых вложенных путей

### `call`

- WebRTC-звонки
- signaling через `Socket.IO`
- сейчас настроен только `STUN`

### `notifications`

- in-app realtime-уведомления через `Socket.IO`
- push через `FCM` пока не реализован

## База данных

Ключевые сущности:

- `User`
- `Message`
- `Attachment`
- `Call`
- `Notification`
- `UserSession`

## Хранение файлов

### Текущий режим

Файлы хранятся локально в `uploads/`.

Схема ключей:

```text
uploads/{userId}_{slug}/uuid.ext
```

Пример:

```text
uploads/12_ivanov_ivan_ivanovich/3f2c8d9a.jpg
```

Где:

- `userId` — ID пользователя
- `slug` — транслитерированное ФИО

### Совместимость

- старые ключи вида `uuid.jpg` продолжают работать
- новые ключи используют подпапки пользователя

### Удаление

При удалении сообщения backend пытается удалить и физические файлы. Если файла уже нет, запрос не падает.

### MinIO

`MinIO` — только опциональный режим хранения. Он не является обязательной частью текущего запуска проекта.

## Frontend

Основные экраны:

- `login_screen.dart`
- `admin_screen.dart`
- `chat_screen.dart`
- `user_screen.dart`
- `archive_screen.dart`
- `call_screen.dart`
- `notifications_screen.dart`

## Frontend: важные текущие моменты

- поиск по чату вынесен в `frontend/lib/screens/chat_search_delegate.dart`
- для чатов используется `ScrollablePositionedList`
- старый подход с `_scrollController` и расчётом `index * 80` больше не должен использоваться
- composer в чатах синхронизирован: multiline-ввод, отдельные кнопки `send` и `mic`

## Ограничения

### WebRTC

Сейчас настроен только:

```text
stun:stun.l.google.com:19302
```

Без `TURN` звонки могут быть нестабильны в некоторых сетях.

### Уведомления

Сейчас есть только in-app уведомления через `Socket.IO`.
Полноценных push-уведомлений `FCM` пока нет.

## ADR

- `ADR-001`: NestJS + Prisma
- `ADR-002`: PostgreSQL как основная БД
- `ADR-003`: JWT + bcrypt
- `ADR-004`: Socket.IO для realtime
- `ADR-005`: Provider для состояния Flutter
- `ADR-006`: Controller → Service → PrismaService
- `ADR-007`: локальное `uploads/` по умолчанию, `MinIO` как опциональный storage driver
- `ADR-008`: WebRTC для звонков
