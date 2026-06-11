# N App — Полный контекст проекта

> **Дата создания:** Июнь 2026  
> **Репозиторий:** `github.com/den063rus-design/n-app`  
> **Назначение:** Полная документация для быстрого погружения нового разработчика или ИИ-ассистента в проект

---

## 📋 Описание проекта

**N App** — это полнофункциональное чат-приложение для коммуникации между администратором и пользователями. Система позволяет администратору управлять пользователями (создавать, блокировать, архивировать, редактировать), общаться с ними в реальном времени через текстовые сообщения с вложениями (фото, видео, голосовые, документы), а также совершать видеозвонки через WebRTC.

**Архитектура:** NestJS (backend) + Flutter (frontend) + PostgreSQL (БД) + MinIO (файловое хранилище)

---

## 🏗 Архитектура

### Frontend (Flutter)

| Компонент | Технология | Версия |
|-----------|-----------|--------|
| Flutter SDK | Flutter | 3.44.1 |
| Dart SDK | Dart | >=3.0.0 |
| State management | Provider | ^6.1.1 |
| HTTP клиент | Dio | ^5.4.0 |
| WebSocket | socket_io_client | ^2.0.3+1 |
| Secure Storage | flutter_secure_storage | ^9.0.0 |
| WebRTC | flutter_webrtc | ^1.0.0 |
| Image picker | image_picker | ^1.0.7 |
| File picker | file_picker | ^8.0.0 |
| Audio record | record | ^7.0.0 |
| Audio player | audioplayers | ^5.2.1 |
| Video player | video_player | ^2.8.2 |
| Permissions | permission_handler | ^11.0.0 |
| Connectivity | connectivity_plus | ^6.0.3 |
| Intl | intl | ^0.19.0 |

**Сборка:** Android APK (release), подпись через apksigner
- **Минимальный SDK:** 21 (Android 5.0+)
- **Target SDK:** 34 (Android 14)
- **Compile SDK:** 34
- **Gradle:** 8.14 (через Tencent mirror: `https://mirrors.cloud.tencent.com/gradle/gradle-8.14-all.zip`)
- **AGP:** 8.9.1
- **Kotlin:** 2.0.0
- **NDK:** 27.0.12077973
- **Keystore:** [`frontend/android/upload-keystore.jks`](frontend/android/upload-keystore.jks) (PKCS12, пароль: `napp123`, alias: `upload`)
- **Подпись:** apksigner.jar из build-tools 34.0.0
- **Application ID:** `com.napp.app`

### Backend (NestJS)

| Компонент | Технология | Версия |
|-----------|-----------|--------|
| Framework | NestJS | ^11.0.1 |
| ORM | Prisma | ^6.19.3 |
| База данных | PostgreSQL (через Prisma) | — |
| Аутентификация | JWT + Passport | ^11.0.2 / ^11.0.5 |
| Хеширование | bcrypt | ^6.0.0 |
| Real-time | Socket.IO | ^4.8.3 |
| Валидация | class-validator + class-transformer | ^0.15.1 / ^0.5.1 |
| Документация API | Swagger | ^11.4.4 |
| S3-клиент | @aws-sdk/client-s3 | ^3.1065.0 |
| UUID | uuid | ^14.0.0 |

### База данных (PostgreSQL)

**Модели:** User, Message, Attachment, Call, Notification, UserSession

**User:**
- `id` (Int, PK, autoincrement)
- `fio` (String) — ФИО
- `age` (Int) — возраст
- `login` (String, @unique) — логин
- `passwordHash` (String) — хеш пароля (bcrypt)
- `role` (Role: ADMIN | USER)
- `status` (UserStatus: ACTIVE | BLOCKED | ARCHIVED)
- `notes` (String?) — заметки администратора
- `isOnline` (Boolean) — онлайн-статус
- `lastSeenAt` (DateTime?) — время последней активности
- `createdAt` / `updatedAt` (DateTime)
- Индексы: `[role]`, `[status]`, `[createdAt]`

**Message:**
- `id` (Int, PK)
- `senderId` / `receiverId` (Int, FK → User, onDelete: Cascade)
- `text` (String) — текст сообщения
- `status` (MessageStatus: SENT | DELIVERED | READ)
- `createdAt` / `updatedAt` (DateTime)
- `attachments` (Attachment[])
- Индексы: `[senderId, createdAt]`, `[receiverId, createdAt]`, `[status]`

**Attachment:**
- `id` (Int, PK)
- `messageId` (Int, FK → Message, onDelete: Cascade)
- `fileName`, `fileType`, `fileSize`, `key` (@unique), `url`
- `createdAt` (DateTime)
- Индексы: `[messageId]`

**Call:**
- `id` (Int, PK)
- `callerId` / `calleeId` (Int, FK → User, onDelete: Cascade)
- `status` (CallStatus: PENDING | ACCEPTED | REJECTED | ENDED | MISSED)
- `startedAt` / `endedAt` (DateTime?)
- `createdAt` (DateTime)
- Индексы: `[callerId]`, `[calleeId]`, `[callerId, calleeId]`, `[status]`, `[createdAt]`

**Notification:**
- `id` (Int, PK)
- `userId` (Int, FK → User, onDelete: Cascade)
- `type` (NotificationType: MESSAGE | CALL)
- `title`, `body?`, `data?` (Json)
- `isRead` (Boolean, default: false)
- `createdAt` (DateTime)
- Индексы: `[userId, isRead]`, `[userId, createdAt]`

**UserSession:**
- `id` (String, PK, cuid)
- `userId` (Int, FK → User, onDelete: Cascade)
- `socketId` (String?)
- `isActive` (Boolean, default: true)
- `createdAt` / `updatedAt`
- Индексы: `[userId, isActive]`, `[socketId]`

---

## 🔌 API Endpoints

### Auth
| Метод | Путь | Доступ | Описание |
|-------|------|--------|----------|
| POST | `/auth/login` | Публичный | Вход (возвращает JWT + user) |

### Users (только ADMIN)
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/users` | Создать пользователя |
| GET | `/users` | Список (с поиском, сортировкой, фильтрацией) |
| GET | `/users/me` | Текущий пользователь по JWT |
| GET | `/users/archive` | Архивные пользователи |
| GET | `/users/:id` | Получить пользователя |
| PATCH | `/users/:id` | Обновить данные |
| PATCH | `/users/:id/block` | Заблокировать |
| PATCH | `/users/:id/unblock` | Разблокировать |
| PATCH | `/users/:id/archive` | Архивировать |
| PATCH | `/users/:id/restore` | Восстановить из архива |
| PATCH | `/users/:id/credentials` | Сменить логин/пароль |
| PATCH | `/users/:id/online` | Обновить онлайн-статус |
| DELETE | `/users/:id` | Удалить (только ARCHIVED) |

### Chat
| Метод | Путь | Доступ | Описание |
|-------|------|--------|----------|
| POST | `/chat` | Любой | Отправить сообщение |
| GET | `/chat/my` | Любой | Свои сообщения |
| GET | `/chat` | ADMIN | Все сообщения |
| GET | `/chat/user/:userId` | ADMIN | Сообщения пользователя |
| GET | `/chat/history/:userId` | Любой | История с пагинацией |
| DELETE | `/chat/:id` | ADMIN | Удалить сообщение |
| DELETE | `/chat/message/:messageId` | ADMIN | Удалить сообщение |

### Files
| Метод | Путь | Доступ | Описание |
|-------|------|--------|----------|
| POST | `/files/upload` | JWT | Загрузить файл (multipart) |
| GET | `/files/:key` | JWT | Получить файл |
| DELETE | `/files/:key` | JWT | Удалить файл |

### Notifications
| Метод | Путь | Доступ | Описание |
|-------|------|--------|----------|
| GET | `/notifications/my` | JWT | Мои уведомления (с пагинацией) |
| PATCH | `/notifications/:id/read` | JWT | Отметить прочитанным |
| PATCH | `/notifications/read-all` | JWT | Всё прочитано |
| GET | `/notifications/unread-count` | JWT | Количество непрочитанных |

### Call
| Метод | Путь | Доступ | Описание |
|-------|------|--------|----------|
| GET | `/call/my` | JWT | Мои звонки |
| GET | `/call/history/:userId` | ADMIN | История звонков пользователя |

### WebSocket (Socket.IO) — порт 3000
- **Аутентификация:** JWT токен через `handshake.auth.token`
- **Gateway'ы:** ChatGateway, CallGateway, NotificationsGateway (все на одном namespace `/`)

**События чата:**
- `message:send` — отправка сообщения (клиент → сервер)
- `message:read` — отметка о прочтении (клиент → сервер)
- `message:new` — новое сообщение (сервер → клиент)
- `message:delivered` — сообщение доставлено (сервер → клиент)
- `message:deleted` — сообщение удалено (сервер → клиент)
- `user:online` / `user:offline` — статус пользователя (сервер → клиент)
- `heartbeat` — обновление lastSeenAt (клиент → сервер, каждые 30 сек)

**События звонков:**
- `call:start` — инициировать звонок
- `call:accept` — принять звонок
- `call:reject` — отклонить звонок
- `call:end` — завершить звонок
- `call:signal` — WebRTC сигнал (offer/answer/ICE candidate)
- `call:missed` — пропущенный звонок
- `call:incoming` — входящий звонок (сервер → клиент)
- `call:accepted` — звонок принят (сервер → клиент)

**События уведомлений:**
- `notification:new` — новое уведомление (сервер → клиент)
- `notification:unread_count` — количество непрочитанных (сервер → клиент)

---

## 📱 Frontend Screens

| Экран | Файл | Описание |
|-------|------|----------|
| **LoginScreen** | [`frontend/lib/screens/login_screen.dart`](frontend/lib/screens/login_screen.dart) | Вход по логину/паролю |
| **AdminScreen** | [`frontend/lib/screens/admin_screen.dart`](frontend/lib/screens/admin_screen.dart) | Панель администратора: список пользователей, поиск, сортировка, фильтрация |
| **UserScreen** | [`frontend/lib/screens/user_screen.dart`](frontend/lib/screens/user_screen.dart) | Чат пользователя с администратором |
| **ChatScreen** | [`frontend/lib/screens/chat_screen.dart`](frontend/lib/screens/chat_screen.dart) | Полноценный чат: текст, фото, видео, голосовые, документы |
| **ArchiveScreen** | [`frontend/lib/screens/archive_screen.dart`](frontend/lib/screens/archive_screen.dart) | Архивные пользователи (admin) |
| **CreateUserScreen** | [`frontend/lib/screens/create_user_screen.dart`](frontend/lib/screens/create_user_screen.dart) | Создание нового пользователя (admin) |
| **EditUserScreen** | [`frontend/lib/screens/edit_user_screen.dart`](frontend/lib/screens/edit_user_screen.dart) | Редактирование пользователя (admin) |
| **UserCardScreen** | [`frontend/lib/screens/user_card_screen.dart`](frontend/lib/screens/user_card_screen.dart) | Карточка пользователя с полной информацией |
| **CallScreen** | [`frontend/lib/screens/call_screen.dart`](frontend/lib/screens/call_screen.dart) | WebRTC видеозвонки |
| **NotificationsScreen** | [`frontend/lib/screens/notifications_screen.dart`](frontend/lib/screens/notifications_screen.dart) | Уведомления |

---

## 🔧 Сборка и деплой

### Backend (Debian сервер)

- **Сервер:** `your-user@YOUR_SERVER_IP`, порт 3000
- **Пароль сервера:** `YOUR_SERVER_PASSWORD`
- **PM2 процесс:** `n-app-backend`
- **Путь:** `your-project-path`
- **Деплой:** `git pull` → `npm run build` → `pm2 restart n-app-backend`
- **Скрипты:**
  - [`deploy/deploy-backend.sh`](deploy/deploy-backend.sh) — деплой без Git
  - [`deploy/deploy-debian.sh`](deploy/deploy-debian.sh) — деплой через Git (сохраняет .env)
  - [`deploy/setup-vps.sh`](deploy/setup-vps.sh) — настройка сервера с нуля

**PM2 конфигурация** ([`ecosystem.config.js`](ecosystem.config.js)):
```js
module.exports = {
  apps: [{
    name: 'n-app-backend',
    script: 'dist/main.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: { NODE_ENV: 'production' },
  }],
};
```

### Frontend (Windows 11)

- **Flutter SDK:** 3.44.1
- **Android SDK:** build-tools 34.0.0, platform-tools
- **Gradle:** 8.14 (Tencent mirror: `https://mirrors.cloud.tencent.com/gradle/gradle-8.14-all.zip`)
- **AGP:** 8.9.1, **Kotlin:** 2.0.0
- **Java:** Android Studio JBR
- **Keystore:** [`frontend/android/upload-keystore.jks`](frontend/android/upload-keystore.jks) (PKCS12, пароль: `napp123`, alias: `upload`)
- **Установка:** ADB (USB) через platform-tools
- **Команда сборки:** `flutter build apk --release`
- **Подпись:** [`deploy/sign-apk.bat`](deploy/sign-apk.bat) (apksigner.jar из build-tools 34.0.0)
- **Скрипт сборки:** [`deploy/build-apk.sh`](deploy/build-apk.sh)

**API Config** ([`frontend/lib/config/api_config.dart`](frontend/lib/config/api_config.dart)):
```dart
static const String prodBaseUrl = 'http://YOUR_SERVER_IP:3000';
static const String prodWsUrl = 'ws://YOUR_SERVER_IP:3000';
static const bool isProduction = true; // Переключатель dev/prod
```

---

## 🔐 Безопасность

- **JWT_SECRET:** `YOUR_JWT_SECRET` (в .env на сервере)
- **Срок действия JWT:** 7 дней
- **Все эндпоинты защищены** `JwtAuthGuard` (кроме `/auth/login`)
- **Ролевая защита:** `RolesGuard` + декоратор `@Roles('ADMIN')`
- **Валидация:** глобальный `ValidationPipe` с `whitelist: true`, `forbidNonWhitelisted: true`
- **Пароли:** bcrypt с солью 10 раундов, `passwordHash` никогда не возвращается в API
- **Файлы:** может загружать любой авторизованный пользователь (через MinIO/S3)
- **CORS:** `origin: '*'` (в production рекомендуется ограничить)
- **WebSocket CORS:** `origin: process.env.CORS_ORIGIN ?? 'http://localhost:3000'`

### Переменные окружения (.env)
```
DATABASE_URL=postgresql://...
JWT_SECRET=YOUR_JWT_SECRET
PORT=3000
MINIO_ENDPOINT=http://localhost
MINIO_PORT=9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_BUCKET=n-app-files
CORS_ORIGIN=http://localhost:3000
```

### Seed данные
- **Администратор:** логин `admin`, пароль `admin123`
- Seed файл: [`prisma/seed.ts`](prisma/seed.ts)

---

## 🐛 Известные проблемы и решения

### Исправленные баги

| # | Проблема | Файл(ы) | Решение |
|---|----------|---------|---------|
| 1 | **JWT_SECRET fallback в коде** — был указан `'super-secret-key-change-in-production'` | [`src/config/constants.ts`](src/config/constants.ts:2) | Убран fallback, теперь выбрасывается ошибка, если JWT_SECRET не задан в .env |
| 2 | **Несоответствие полей Message** — frontend использовал `content` вместо `text`, `isRead` (bool) вместо `status` (enum) | [`frontend/lib/models/message.dart`](frontend/lib/models/message.dart:33-34) | Добавлена поддержка обоих полей через fallback в `fromJson`, статус теперь enum |
| 3 | **Event names Socket.IO** — frontend эмитил `sendMessage`, а gateway слушал `message:send` | [`frontend/lib/services/socket_service.dart`](frontend/lib/services/socket_service.dart:85) | Исправлены все event names на соответствующие backend |
| 4 | **Отправка сообщений от пользователя** — receiverId был ID текущего пользователя вместо ID админа | [`frontend/lib/providers/chat_provider.dart`](frontend/lib/providers/chat_provider.dart:233-253) | Backend сам находит администратора, если receiverId не указан |
| 5 | **Нет try/catch в ChatGateway** — ошибки падали в сокет | [`src/chat/chat.gateway.ts`](src/chat/chat.gateway.ts:28-83) | Добавлены try/catch во все обработчики |
| 6 | **CORS origin: '*'** — небезопасная конфигурация | [`src/main.ts`](src/main.ts:10-15) | Оставлено для разработки, в production через CORS_ORIGIN |
| 7 | **Пустой ConfigModule** — не использовался | [`src/config/config.module.ts`](src/config/config.module.ts) | Оставлен как заглушка |
| 8 | **Отсутствие валидации DTO в gateway** | [`src/chat/chat.gateway.ts`](src/chat/chat.gateway.ts) | Валидация пока только в HTTP контроллере |
| 9 | **Нет rate limiting на WebSocket** | — | Рекомендуется добавить throttle |
| 10 | **Нет Repository слоя** — сервисы напрямую зависят от PrismaService | Все сервисы | Рекомендуется внедрить абстракции UserRepository, MessageRepository |
| 11 | **MessageResponseDto не включает updatedAt** | [`src/chat/dto/message-response.dto.ts`](src/chat/dto/message-response.dto.ts) | Синхронизировать DTO с select |
| 12 | **AdminScreen использует ApiService напрямую** | [`frontend/lib/screens/admin_screen.dart`](frontend/lib/screens/admin_screen.dart) | Вынести логику в UserProvider |
| 13 | **Нет валидации полей при создании пользователя на клиенте** | [`frontend/lib/screens/create_user_screen.dart`](frontend/lib/screens/create_user_screen.dart) | Добавить валидацию перед отправкой |

---

## 📁 Структура проекта (полное дерево)

```
n-app/
├── deploy/                          # Скрипты деплоя
│   ├── setup-vps.sh                 # Настройка сервера (PostgreSQL, MinIO, Node.js, PM2)
│   ├── deploy-backend.sh            # Деплой бэкенда (npm install → build → prisma → pm2)
│   ├── deploy-debian.sh             # Деплой на Debian через Git (с сохранением .env)
│   ├── build-apk.sh                 # Сборка APK (flutter clean → pub get → build)
│   ├── sign-apk.bat                 # Подпись APK через apksigner (Windows)
│   └── setup-android-sdk.sh         # Установка Android SDK на Debian
├── docs/
│   ├── architecture.md              # Детальные архитектурные диаграммы (Mermaid)
│   └── CONTEXT.md                   # Полный контекст проекта (этот файл)
├── frontend/                        # Flutter приложение
│   ├── pubspec.yaml                 # Зависимости Flutter
│   ├── lib/
│   │   ├── main.dart                # Точка входа
│   │   ├── app/
│   │   │   └── app.dart             # MaterialApp + MultiProvider + AuthGate + мониторинг сети
│   │   ├── config/
│   │   │   ├── api_config.dart      # URL сервера, таймауты, endpoints
│   │   │   └── theme.dart           # Material 3 тема (primary: #1976D2)
│   │   ├── models/
│   │   │   ├── user.dart            # User модель (fullName, role, status, isOnline)
│   │   │   ├── message.dart         # Message + Attachment модели
│   │   │   ├── notification.dart    # AppNotification модель
│   │   │   └── call.dart            # Call модель
│   │   ├── services/
│   │   │   ├── api_service.dart     # Dio singleton + JWT interceptor + все HTTP методы
│   │   │   ├── auth_service.dart    # Login/logout/token management (SecureStorage)
│   │   │   ├── socket_service.dart  # Socket.IO singleton + heartbeat + все события
│   │   │   └── call_service.dart    # WebRTC + CallState management
│   │   ├── providers/
│   │   │   ├── auth_provider.dart   # AuthProvider (ChangeNotifier) — вход/выход/проверка
│   │   │   ├── chat_provider.dart   # ChatProvider — сообщения, пользователи, файлы
│   │   │   ├── user_provider.dart   # UserProvider — список пользователей, поиск, сортировка
│   │   │   └── notification_provider.dart  # NotificationProvider — уведомления
│   │   ├── screens/
│   │   │   ├── login_screen.dart    # Экран входа
│   │   │   ├── admin_screen.dart    # Панель администратора
│   │   │   ├── user_screen.dart     # Чат пользователя
│   │   │   ├── chat_screen.dart     # Полноценный чат
│   │   │   ├── archive_screen.dart  # Архивные пользователи
│   │   │   ├── create_user_screen.dart  # Создание пользователя
│   │   │   ├── edit_user_screen.dart    # Редактирование пользователя
│   │   │   ├── user_card_screen.dart    # Карточка пользователя
│   │   │   ├── call_screen.dart     # WebRTC видеозвонки
│   │   │   └── notifications_screen.dart # Уведомления
│   │   └── widgets/
│   │       ├── attachment_viewer.dart   # Просмотр вложений
│   │       ├── message_bubble.dart      # Пузырёк сообщения
│   │       └── notification_badge.dart  # Бейдж уведомлений
│   ├── android/
│   │   ├── build.gradle             # Корневой Gradle (AGP 8.9.1, Kotlin 2.0.0)
│   │   ├── settings.gradle          # Настройки Gradle
│   │   ├── gradle.properties        # minSdk=21, targetSdk=34, compileSdk=34
│   │   ├── key.properties           # storePassword=napp123, keyAlias=upload
│   │   ├── upload-keystore.jks      # Keystore для подписи APK
│   │   ├── gradle/wrapper/
│   │   │   └── gradle-wrapper.properties  # Gradle 8.14 (Tencent mirror)
│   │   └── app/
│   │       └── build.gradle         # Модуль app: applicationId=com.napp.app
│   └── assets/
│       └── icon.png                 # Иконка приложения
├── prisma/
│   ├── schema.prisma                # Prisma схема (6 моделей, 5 enum)
│   └── seed.ts                      # Seed: создаёт admin/admin123
├── src/                             # NestJS backend
│   ├── main.ts                      # Точка входа: CORS, ValidationPipe, Swagger, порт 3000
│   ├── app.module.ts                # Корневой модуль (7 модулей)
│   ├── auth/                        # Модуль аутентификации
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts       # POST /auth/login
│   │   ├── auth.service.ts          # Логика login + validateUser
│   │   ├── jwt.strategy.ts          # Passport JWT Strategy
│   │   ├── dto/auth.dto.ts          # LoginDto, AuthResponseDto
│   │   └── guards/
│   │       ├── jwt-auth.guard.ts    # JwtAuthGuard
│   │       └── roles.guard.ts       # RolesGuard
│   ├── users/                       # Модуль управления пользователями
│   │   ├── users.module.ts
│   │   ├── users.controller.ts      # CRUD + block/unblock/archive/restore/credentials
│   │   ├── users.service.ts         # Бизнес-логика (bcrypt, поиск, сортировка)
│   │   └── dto/
│   │       ├── create-user.dto.ts
│   │       ├── update-user.dto.ts
│   │       ├── update-credentials.dto.ts
│   │       └── query-users.dto.ts
│   ├── chat/                        # Модуль чата
│   │   ├── chat.module.ts
│   │   ├── chat.controller.ts       # HTTP endpoints (send, list, delete)
│   │   ├── chat.service.ts          # Бизнес-логика (create, resolveReceiver, status)
│   │   ├── chat.gateway.ts          # Socket.IO gateway (connection, online status)
│   │   └── dto/
│   │       ├── create-message.dto.ts
│   │       ├── message-response.dto.ts
│   │       └── chat-history-query.dto.ts
│   ├── files/                       # Модуль файлов (MinIO/S3)
│   │   ├── files.module.ts
│   │   ├── files.controller.ts      # POST upload, GET :key, DELETE :key
│   │   └── files.service.ts         # S3Client (Put/Get/DeleteObjectCommand)
│   ├── call/                        # Модуль звонков (WebRTC)
│   │   ├── call.module.ts
│   │   ├── call.controller.ts       # GET my, GET history/:userId
│   │   ├── call.gateway.ts          # Socket.IO: call:start/accept/reject/end/signal
│   │   └── call.service.ts          # CRUD звонков
│   ├── notifications/               # Модуль уведомлений
│   │   ├── notifications.module.ts
│   │   ├── notifications.controller.ts  # GET my, PATCH read/read-all, GET unread-count
│   │   ├── notifications.gateway.ts     # Socket.IO: notification:new, unread_count
│   │   └── notifications.service.ts     # CRUD уведомлений
│   ├── common/decorators/
│   │   ├── current-user.decorator.ts # @CurrentUser()
│   │   └── roles.decorator.ts        # @Roles()
│   ├── config/
│   │   ├── config.module.ts         # Пустой модуль (заглушка)
│   │   └── constants.ts             # JWT secret + expiresIn (7d)
│   └── prisma/
│       ├── prisma.module.ts         # Global модуль
│       └── prisma.service.ts        # PrismaClient lifecycle
├── .env.production                  # Production переменные окружения
├── ecosystem.config.js              # PM2 конфигурация
├── package.json                     # NestJS зависимости и скрипты
├── tsconfig.json                    # TypeScript конфигурация
├── nest-cli.json                    # NestJS CLI конфигурация
├── eslint.config.mjs                # ESLint конфигурация
├── .prettierrc                      # Prettier конфигурация
├── README.md                        # Основной README
├── ARCHITECTURE.md                  # Архитектурная документация
└── DEPLOY.md                        # Инструкция по развёртыванию
```

---

## 🚀 Быстрый старт

### Backend (локальная разработка)
```bash
# Установка зависимостей
npm install

# Сборка
npm run build

# Prisma
npx prisma generate
npx prisma migrate dev --name init
npx prisma db seed

# Запуск в режиме разработки
npm run start:dev
```

### Frontend (локальная сборка)
```bash
cd frontend

# Установка зависимостей
flutter pub get

# Сборка APK
flutter build apk --release

# Установка на устройство через ADB
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Деплой на сервер
```bash
# SSH на сервер
ssh your-user@YOUR_SERVER_IP

# Быстрый деплой
cd /opt/n-app && git pull && npm install && npm run build && npx prisma generate && npx prisma migrate deploy && pm2 restart n-app-backend

# Или через скрипт
./deploy/deploy-debian.sh
```

### Учётные данные по умолчанию
- **Администратор:** логин `admin`, пароль `admin123`

---

## 📚 Полезные ссылки

- **Swagger документация API:** `http://YOUR_SERVER_IP:3000/api`
- **MinIO Console:** `http://YOUR_SERVER_IP:9001` (логин: `minioadmin`, пароль: `minioadmin`)
- **PM2 статус:** `pm2 status` (на сервере)
- **PM2 логи:** `pm2 logs n-app-backend` (на сервере)
- **GitHub репозиторий:** `github.com/den063rus-design/n-app`