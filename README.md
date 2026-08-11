# N App

Закрытая система общения преподавателя английского языка с учениками в формате `1 на 1`.

Проект состоит из backend на NestJS и мобильного frontend на Flutter. Backend отвечает за пользователей, авторизацию, чат, файлы, уведомления и signaling для звонков. Flutter-приложение дает преподавателю и ученикам интерфейс для входа, чата, карточек пользователей, архива, уведомлений и видеозвонков.

## Возможности

- вход по логину и паролю без самостоятельной регистрации;
- создание учеников и доступов преподавателем;
- чат между преподавателем и учеником;
- текстовые сообщения, фото, видео, голосовые и документы;
- поиск по сообщениям и вложениям;
- статусы сообщений `SENT`, `DELIVERED`, `READ`;
- блокировка, разблокировка, архивирование и восстановление учеников;
- in-app уведомления через Socket.IO;
- WebRTC-звонки;
- локальное хранение файлов в `uploads/` с возможностью позже подключить MinIO.

> В коде роль преподавателя может называться `ADMIN`. Это внутреннее техническое имя роли, по бизнес-смыслу это преподаватель.

## Стек

### Backend

- NestJS
- Prisma
- PostgreSQL
- Socket.IO
- JWT / Passport
- bcrypt
- Swagger
- PM2 для запуска на сервере

### Frontend

- Flutter
- Provider
- Dio / HTTP
- socket_io_client
- flutter_webrtc
- Firebase Messaging
- flutter_local_notifications

## Структура проекта

```text
.
├── src/                  # NestJS backend
│   ├── auth/             # авторизация и JWT
│   ├── call/             # WebRTC signaling и звонки
│   ├── chat/             # сообщения и статусы
│   ├── files/            # upload/download/delete файлов
│   ├── notifications/    # in-app уведомления
│   ├── prisma/           # PrismaService
│   └── users/            # пользователи, роли, архив
├── prisma/               # schema, migrations, seed
├── frontend/             # Flutter-приложение
├── deploy/               # скрипты деплоя и сборки
├── docs/                 # дополнительная документация
├── plans/                # планы развития
├── ARCHITECTURE.md
├── DEPLOY.md
└── README.md
```

## Backend: локальный запуск

### 1. Установить зависимости

```bash
npm install
```

### 2. Создать `.env`

Создайте файл `.env` в корне проекта:

```env
PORT=3000
DATABASE_URL="postgresql://napp_user:CHANGE_ME_STRONG_PASSWORD@localhost:5432/n_app?schema=public"
JWT_SECRET="CHANGE_ME_SUPER_SECRET"
CORS_ORIGIN="http://localhost:3000"
FILE_STORAGE_DRIVER=local
```

Для MinIO позже можно добавить:

```env
MINIO_ENDPOINT=http://YOUR_MINIO_HOST
MINIO_PORT=9000
MINIO_BUCKET=n-app-files
MINIO_ACCESS_KEY=CHANGE_ME
MINIO_SECRET_KEY=CHANGE_ME
```

### 3. Подготовить Prisma

```bash
npx prisma generate
npx prisma migrate deploy
npx prisma db seed
```

Seed создает преподавателя по умолчанию:

```text
login: admin
password: admin123
```

После первого входа пароль лучше поменять.

### 4. Запустить backend

```bash
npm run start:dev
```

Swagger доступен по адресу:

```text
http://localhost:3000/api
```

## Backend: production на Debian

Краткий вариант:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates gnupg build-essential unzip postgresql postgresql-contrib

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2

cd /opt
sudo git clone https://github.com/den063rus-design/n-app.git n-app
sudo chown -R $USER:$USER /opt/n-app
cd /opt/n-app

npm install
npx prisma generate
npx prisma migrate deploy
npx prisma db seed
npm run build
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

Подробная инструкция лежит в `DEPLOY.md`.

## Frontend: сборка APK

Перейдите в папку frontend:

```bash
cd frontend
flutter pub get
flutter doctor
flutter build apk --release
```

Готовый APK:

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```

Установка через ADB:

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Настройка API для frontend

Основной файл:

```text
frontend/lib/config/api_config.dart
```

Перед production-сборкой проверьте:

- `prodBaseUrl`;
- `prodWsUrl`;
- флаг `isProduction`.

## Файлы и загрузки

По умолчанию файлы хранятся локально:

```text
uploads/{userId}_{slug}/uuid.ext
```

Старые плоские ключи вида `uuid.jpg` остаются совместимыми. Папка `uploads/` не хранится в git.

## Секреты

Не коммитьте реальные секреты:

- `.env`;
- `frontend/android/key.properties`;
- `frontend/android/*.jks`;
- `frontend/android/app/google-services.json`;
- `firebase-service-account.json`;
- любые `*-firebase-adminsdk-*.json`.

В репозитории оставлены только примеры, например `firebase-service-account.example.json` и `frontend/android/key.properties.example`.

## Полезные команды

```bash
# Backend
npm run build
npm run start:dev
npm run start:prod
npm run test

# Prisma
npx prisma generate
npx prisma migrate deploy
npx prisma studio

# PM2
pm2 status
pm2 logs n-app-backend
pm2 restart n-app-backend
```

## Ограничения

- Docker, Docker Compose, Nginx и SSL сейчас не входят в проект.
- Для WebRTC настроен STUN. Без TURN звонки могут быть нестабильны в некоторых сетях.
- Push-уведомления FCM находятся в процессе подготовки: зависимости и часть сервисов уже есть, финальную production-настройку нужно проверять отдельно.

## Документация

- `ARCHITECTURE.md` - архитектура и ограничения;
- `DEPLOY.md` - деплой backend;
- `docs/` - дополнительный контекст;
- `plans/push-notifications.md` - план по push-уведомлениям;
- `plans/turn-server.md` - план по TURN-серверу.
