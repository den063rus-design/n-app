# N App — контекст проекта

Этот файл нужен для быстрого входа в проект новому разработчику или другому ИИ.

## Что это за проект

Закрытая система общения администратора с пользователями.

- самостоятельной регистрации нет
- пользователей создаёт только администратор
- пользователь видит только свой чат
- пользователи не видят друг друга
- удалять сообщения может только администратор

## Текущий стек

### Backend

- `NestJS`
- `TypeScript`
- `Prisma`
- `PostgreSQL`
- `Socket.IO`
- `JWT`
- `bcrypt`

### Frontend

- `Flutter`
- `Provider`
- `Dio`
- `socket_io_client`
- `flutter_webrtc`
- `file_picker`
- `image_picker`
- `record`
- `audioplayers`
- `video_player`
- `scrollable_positioned_list`

## Что уже реализовано

- логин по JWT
- управление пользователями
- чат admin ↔ user
- вложения: фото, видео, голосовые, документы
- хранение сообщений в БД
- realtime-доставка через `Socket.IO`
- статусы сообщений
- online/offline
- in-app уведомления
- WebRTC-звонки
- поиск по чату

## Что важно помнить

### Файлы

Сейчас основной режим хранения файлов — локальный `uploads/`.

Новая схема:

```text
uploads/{userId}_{slug}/uuid.ext
```

Пример:

```text
uploads/12_ivanov_ivan_ivanovich/3f2c8d9a.jpg
```

Старые файлы со старыми плоскими ключами тоже поддерживаются.

Если сообщение удаляется администратором, backend должен удалять и физический файл.

### MinIO

`MinIO` пока не обязателен.
Он используется только если явно включён через:

```env
FILE_STORAGE_DRIVER=minio
```

### Уведомления

Сейчас есть только in-app уведомления через `Socket.IO`.
`FCM` push пока не подключён.

### Звонки

Сейчас есть только `STUN`, без `TURN`.
Поэтому в некоторых сетях звонки могут работать нестабильно.

## Важные backend-модули

```text
src/
  auth/
  users/
  chat/
  files/
  call/
  notifications/
  prisma/
```

## Важные frontend-файлы

```text
frontend/lib/
  services/api_service.dart
  services/socket_service.dart
  services/call_service.dart
  providers/chat_provider.dart
  screens/chat_screen.dart
  screens/user_screen.dart
  screens/chat_search_delegate.dart
  widgets/message_bubble.dart
  widgets/attachment_viewer.dart
```

## Текущие хвосты и ограничения

- нет `FCM`
- нет `TURN`
- нет repository-слоя поверх `PrismaService`
- пользовательские сценарии проверяются вручную, а не тестами

## Быстрый запуск backend локально

```bash
npm install
npx prisma generate
npx prisma migrate dev
npx prisma db seed
npm run start:dev
```

## Быстрый запуск frontend локально

```bash
cd frontend
flutter pub get
flutter run
```

## Серверное обновление

Команда, которую использует владелец проекта:

```bash
cd /opt/n-app
git pull
npm run build
pm2 restart n-app-backend
```
