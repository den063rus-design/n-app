# Push-уведомления (FCM) — план реализации

## Статус
🟡 **Не начато.** В проекте есть только in-app realtime-уведомления через Socket.IO.
Полноценных push-уведомлений (FCM) нет ни на backend, ни на frontend.

## Текущая архитектура уведомлений
- **Backend:** [`NotificationsGateway`](src/notifications/notifications.gateway.ts) — Socket.IO, in-app только
- **Frontend:** [`SocketService`](frontend/lib/services/socket_service.dart) — подписка на сокет-события
- **Provider:** [`NotificationProvider`](frontend/lib/providers/notification_provider.dart) — управление состоянием

## Что отсутствует

### Backend
- `firebase-admin` — нет в зависимостях (`package.json`)
- FCM service — нет модуля отправки push
- Нет эндпоинта для сохранения FCM токенов устройств
- Нет модели/таблицы для хранения FCM токенов

### Frontend
- `firebase_messaging` — нет в зависимостях (`pubspec.yaml`)
- Нет инициализации Firebase
- Нет запроса разрешения на уведомления
- Нет получения/отправки FCM токена на backend
- Нет обработки фоновых уведомлений

## План реализации

### Этап 1: Backend — Firebase Admin SDK
1. Установить `firebase-admin` в `package.json`
2. Создать `FirebaseModule` и `FirebaseService`
3. Добавить конфигурацию через `.env` (путь к service account key)
4. Реализовать метод `sendPushNotification(userId, title, body, data)`

### Этап 2: Backend — FCM token management
1. Добавить модель `DeviceToken` в Prisma schema
2. Создать эндпоинт `POST /notifications/register-token` (сохранить FCM токен)
3. Создать эндпоинт `DELETE /notifications/unregister-token` (удалить токен)
4. Интегрировать отправку push в `NotificationsService` при новых сообщениях/звонках

### Этап 3: Frontend — Firebase Messaging SDK
1. Установить `firebase_core` и `firebase_messaging` в `pubspec.yaml`
2. Настроить Firebase проект (google-services.json)
3. Инициализировать Firebase в `main.dart`
4. Запросить разрешение на уведомления
5. Получить FCM токен и отправить на backend
6. Обработать входящие push (foreground + background + terminated)

### Этап 4: Интеграция
1. При отправке сообщения — отправлять push получателю
2. При звонке — отправлять push с данными для WebRTC
3. Тестирование на реальном устройстве

## Зависимости
- **Firebase проект** (нужен аккаунт Firebase)
- **google-services.json** (для Android)
- **Service account key** (для backend)