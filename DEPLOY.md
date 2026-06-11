# Деплой N App

Актуальная краткая инструкция по запуску backend и сборке frontend.

## Что используется сейчас

- Backend: `NestJS` + `Prisma` + `PostgreSQL`
- Frontend: `Flutter`
- Хранение файлов по умолчанию: локальная папка `uploads/`
- `MinIO` поддерживается как опциональный режим, но не требуется для базового запуска

## Backend на Debian

### Требования

- Debian 12
- Node.js 20+
- PostgreSQL 14+
- PM2

### Базовый запуск

```bash
cd /opt
git clone https://github.com/den063rus-design/n-app.git n-app
cd /opt/n-app
npm install
npx prisma generate
npx prisma migrate deploy
npx prisma db seed
npm run build
pm2 start ecosystem.config.js
```

### `.env`

Пример минимальной конфигурации:

```env
PORT=3000
DATABASE_URL="postgresql://napp_user:CHANGE_ME@localhost:5432/n_app?schema=public"
JWT_SECRET="CHANGE_ME_SUPER_SECRET"
CORS_ORIGIN="http://YOUR_SERVER_IP:3000"
FILE_STORAGE_DRIVER=local
```

### Проверка backend

```bash
pm2 status
curl http://localhost:3000
```

Swagger:

```text
http://YOUR_SERVER_IP:3000/api
```

## Хранение файлов

### Текущий режим

По умолчанию проект хранит файлы локально:

```text
/opt/n-app/uploads
```

Новые файлы раскладываются по папкам пользователей:

```text
uploads/{userId}_{slug}/uuid.ext
```

Пример:

```text
uploads/12_ivanov_ivan_ivanovich/3f2c8d9a.jpg
```

### Удаление файлов

Если администратор удаляет сообщение, backend удаляет и связанные физические файлы.

### MinIO

`MinIO` не обязателен. Он включается только если явно задано:

```env
FILE_STORAGE_DRIVER=minio
```

Тогда дополнительно нужны:

```env
MINIO_ENDPOINT=http://YOUR_MINIO_HOST
MINIO_PORT=9000
MINIO_BUCKET=n-app-files
MINIO_ACCESS_KEY=CHANGE_ME
MINIO_SECRET_KEY=CHANGE_ME
```

## Обновление проекта на сервере

Используй только эту команду:

```bash
cd /opt/n-app
git pull
npm run build
pm2 restart n-app-backend
```

Если были изменения Prisma schema или новые миграции, дополнительно выполни:

```bash
npx prisma migrate deploy
```

## Сборка APK

Сборка выполняется на машине разработчика:

```bash
cd frontend
flutter pub get
flutter build apk --release
```

APK:

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```

Установка через `adb`:

```bash
adb install -r frontend/build/app/outputs/flutter-apk/app-release.apk
```
