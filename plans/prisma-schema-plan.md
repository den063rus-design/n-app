# План расширения схемы Prisma — Этап 1

## Результаты анализа текущей схемы

В ходе анализа текущей схемы (`prisma/schema.prisma`) выявлено, что некоторые элементы из ТЗ **уже реализованы**:

| Элемент | Статус |
|---------|--------|
| Поле `age` в модели `User` | ✅ **Уже есть** (строка 30) |
| Значение `ARCHIVED` в `UserStatus` | ✅ **Уже есть** (строка 18) |

## 1. Изменения в модели `User`

### Добавляемые поля

| Поле | Тип | Атрибуты | Назначение |
|------|-----|----------|------------|
| `notes` | `String?` | — | Заметки администратора о пользователе |
| `isOnline` | `Boolean` | `@default(false)` | Флаг онлайн-статуса |
| `lastSeenAt` | `DateTime?` | — | Временная метка последней активности |

### Добавляемые связи (отношения)

```prisma
callerCalls      Call[]        @relation("CallerCalls")
calleeCalls      Call[]        @relation("CalleeCalls")
notifications    Notification[]
sessions         UserSession[]
```

### Итоговый вид модели `User`

```prisma
model User {
  id             Int           @id @default(autoincrement())
  fio            String
  age            Int
  login          String        @unique
  passwordHash   String
  role           Role          @default(USER)
  status         UserStatus    @default(ACTIVE)
  notes          String?                              // заметки администратора
  isOnline       Boolean       @default(false)         // онлайн-статус
  lastSeenAt     DateTime?                             // время последней активности
  createdAt      DateTime      @default(now())
  updatedAt      DateTime      @updatedAt

  sentMessages       Message[]     @relation("SentMessages")
  receivedMessages   Message[]     @relation("ReceivedMessages")
  callerCalls        Call[]        @relation("CallerCalls")
  calleeCalls        Call[]        @relation("CalleeCalls")
  notifications      Notification[]
  sessions           UserSession[]

  @@index([role])
  @@index([status])
  @@index([createdAt])
}
```

## 2. Новые enum'ы

### CallStatus

```prisma
enum CallStatus {
  PENDING
  ACCEPTED
  REJECTED
  ENDED
  MISSED
}
```

### NotificationType

```prisma
enum NotificationType {
  MESSAGE
  CALL
}
```

## 3. Новая модель `Call`

Хранит историю звонков между пользователями.

```prisma
model Call {
  id        Int        @id @default(autoincrement())
  callerId  Int
  calleeId  Int
  status    CallStatus @default(PENDING)
  startedAt DateTime?
  endedAt   DateTime?
  createdAt DateTime   @default(now())

  caller  User  @relation("CallerCalls", fields: [callerId], references: [id], onDelete: Cascade, onUpdate: Cascade)
  callee  User  @relation("CalleeCalls", fields: [calleeId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([callerId])
  @@index([calleeId])
  @@index([callerId, calleeId])
  @@index([status])
  @@index([createdAt])
}
```

**Индексы:**
- `callerId` — быстрый поиск исходящих звонков
- `calleeId` — быстрый поиск входящих звонков
- `callerId, calleeId` — композитный поиск диалогов
- `status` — фильтрация по статусу
- `createdAt` — сортировка по дате

## 4. Новая модель `Notification`

Уведомления для пользователей.

```prisma
model Notification {
  id        Int              @id @default(autoincrement())
  userId    Int
  type      NotificationType
  title     String
  body      String?
  data      Json?
  isRead    Boolean          @default(false)
  createdAt DateTime         @default(now())

  user      User             @relation(fields: [userId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([userId, isRead])
  @@index([userId, createdAt])
}
```

**Особенности:**
- `data` типа `Json?` — для хранения произвольных метаданных (ID сообщения, ID звонка и т.д.)
- Индекс `[userId, isRead]` — быстрая выборка непрочитанных уведомлений
- Индекс `[userId, createdAt]` — сортировка по дате для конкретного пользователя

## 5. Новая модель `UserSession`

Сессии для отслеживания онлайн-статуса через WebSocket.

```prisma
model UserSession {
  id        String   @id @default(cuid())
  userId    Int
  socketId  String?
  isActive  Boolean  @default(true)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([userId, isActive])
  @@index([socketId])
}
```

**Особенности:**
- `id` — `cuid()` для распределённой генерации без автоинкремента
- `socketId` — идентификатор WebSocket-соединения (nullable)
- Индекс `[socketId]` — быстрый поиск при дисконнекте

## 6. Полный обновлённый файл `prisma/schema.prisma`

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

// ========== ENUMS ==========

enum Role {
  ADMIN
  USER
}

enum UserStatus {
  ACTIVE
  BLOCKED
  ARCHIVED
}

enum MessageStatus {
  SENT
  DELIVERED
  READ
}

enum CallStatus {
  PENDING
  ACCEPTED
  REJECTED
  ENDED
  MISSED
}

enum NotificationType {
  MESSAGE
  CALL
}

// ========== MODELS ==========

model User {
  id             Int           @id @default(autoincrement())
  fio            String
  age            Int
  login          String        @unique
  passwordHash   String
  role           Role          @default(USER)
  status         UserStatus    @default(ACTIVE)
  notes          String?
  isOnline       Boolean       @default(false)
  lastSeenAt     DateTime?
  createdAt      DateTime      @default(now())
  updatedAt      DateTime      @updatedAt

  sentMessages       Message[]     @relation("SentMessages")
  receivedMessages   Message[]     @relation("ReceivedMessages")
  callerCalls        Call[]        @relation("CallerCalls")
  calleeCalls        Call[]        @relation("CalleeCalls")
  notifications      Notification[]
  sessions           UserSession[]

  @@index([role])
  @@index([status])
  @@index([createdAt])
}

model Message {
  id         Int           @id @default(autoincrement())
  senderId   Int
  receiverId Int
  text       String
  status     MessageStatus @default(SENT)
  createdAt  DateTime      @default(now())
  updatedAt  DateTime      @updatedAt

  sender      User          @relation("SentMessages", fields: [senderId], references: [id], onDelete: Cascade, onUpdate: Cascade)
  receiver    User          @relation("ReceivedMessages", fields: [receiverId], references: [id], onDelete: Cascade, onUpdate: Cascade)
  attachments Attachment[]

  @@index([senderId, createdAt])
  @@index([receiverId, createdAt])
  @@index([status])
}

model Attachment {
  id        Int      @id @default(autoincrement())
  messageId Int
  message   Message  @relation(fields: [messageId], references: [id], onDelete: Cascade)
  fileName  String
  fileType  String
  fileSize  Int
  createdAt DateTime @default(now())

  @@index([messageId])
}

// ========== NEW MODELS ==========

model Call {
  id        Int        @id @default(autoincrement())
  callerId  Int
  calleeId  Int
  status    CallStatus @default(PENDING)
  startedAt DateTime?
  endedAt   DateTime?
  createdAt DateTime   @default(now())

  caller  User  @relation("CallerCalls", fields: [callerId], references: [id], onDelete: Cascade, onUpdate: Cascade)
  callee  User  @relation("CalleeCalls", fields: [calleeId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([callerId])
  @@index([calleeId])
  @@index([callerId, calleeId])
  @@index([status])
  @@index([createdAt])
}

model Notification {
  id        Int              @id @default(autoincrement())
  userId    Int
  type      NotificationType
  title     String
  body      String?
  data      Json?
  isRead    Boolean          @default(false)
  createdAt DateTime         @default(now())

  user      User             @relation(fields: [userId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([userId, isRead])
  @@index([userId, createdAt])
}

model UserSession {
  id        String   @id @default(cuid())
  userId    Int
  socketId  String?
  isActive  Boolean  @default(true)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([userId, isActive])
  @@index([socketId])
}
```

## 7. План дальнейших действий (Этапы 2+)

После применения схемы Prisma потребуются изменения в коде:

| Файл | Изменения |
|------|-----------|
| `src/users/dto/user-response.dto.ts` | Добавить поля `notes`, `isOnline`, `lastSeenAt` |
| `src/users/dto/update-user.dto.ts` | Добавить опциональное поле `notes` |
| `src/users/users.service.ts` | Добавить `notes`, `isOnline`, `lastSeenAt` в `userSelect` |
| Создать `src/call/` | Модуль для работы со звонками (CRUD, WebSocket) |
| Создать `src/notifications/` | Модуль для работы с уведомлениями |
| Создать `src/sessions/` | Модуль для управления сессиями |
| `src/chat/chat.gateway.ts` | Интеграция с `UserSession` для онлайн-статуса |