# N App

Закрытая система общения администратора с пользователями.

- Backend: `NestJS`, `Prisma`, `PostgreSQL`, `Socket.IO`, `JWT`, `bcrypt`
- Frontend: `Flutter`
- Файлы: локальное хранилище `uploads/` сейчас, `MinIO` можно подключить позже
- Архитектура: `Controller -> Service -> PrismaService`

## Что умеет проект

- вход по логину и паролю без самостоятельной регистрации
- создание пользователей только администратором
- чат `user <-> admin`
- текст, фото, видео, голосовые и документы
- статусы сообщений `SENT / DELIVERED / READ`
- блокировка, разблокировка, архивирование, восстановление пользователей
- in-app уведомления через `Socket.IO`
- WebRTC-звонки

## Важные ограничения

- в проекте нет `Docker`, `Docker Compose`, `Kubernetes`, `Nginx`, `SSL`
- push-уведомления `FCM` пока не реализованы
- для WebRTC сейчас настроен только `STUN`, без `TURN`, поэтому в некоторых сетях звонки могут работать нестабильно

## Структура

```text
prisma/
src/
  auth/
  chat/
  common/
  config/
  files/
  notifications/
  prisma/
  users/
frontend/
deploy/
plans/
README.md
ARCHITECTURE.md
DEPLOY.md
ecosystem.config.js
```

## Backend: установка на чистый Debian

Ниже инструкция для чистого сервера Debian 12.

### 1. Обновить систему

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates gnupg build-essential unzip
```

### 2. Установить Node.js 20

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v
npm -v
```

### 3. Установить PM2

```bash
sudo npm install -g pm2
pm2 -v
```

### 4. Установить PostgreSQL

```bash
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

### 5. Создать базу и пользователя PostgreSQL

Пример:

```bash
sudo -u postgres psql
```

Внутри `psql`:

```sql
CREATE USER napp_user WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE n_app OWNER napp_user;
GRANT ALL PRIVILEGES ON DATABASE n_app TO napp_user;
\q
```

### 6. Клонировать проект

```bash
cd /opt
sudo git clone https://github.com/den063rus-design/n-app.git n-app
sudo chown -R $USER:$USER /opt/n-app
cd /opt/n-app
```

### 7. Установить зависимости backend

```bash
npm install
```

### 8. Создать `.env`

Создай файл `C:\Users\user\Desktop\N APP\.env` локально по аналогии, а на сервере файл должен лежать в `/opt/n-app/.env`.

Пример содержимого для Debian:

```env
PORT=3000
DATABASE_URL="postgresql://napp_user:CHANGE_ME_STRONG_PASSWORD@localhost:5432/n_app?schema=public"
JWT_SECRET="CHANGE_ME_SUPER_SECRET"
CORS_ORIGIN="http://YOUR_SERVER_IP:3000"
FILE_STORAGE_DRIVER=local
```

Если позже будет использоваться `MinIO`, тогда дополнительно понадобятся:

```env
MINIO_ENDPOINT=http://YOUR_MINIO_HOST
MINIO_PORT=9000
MINIO_BUCKET=n-app-files
MINIO_ACCESS_KEY=CHANGE_ME
MINIO_SECRET_KEY=CHANGE_ME
```

### 9. Применить Prisma и создать администратора

```bash
npx prisma generate
npx prisma migrate deploy
npx prisma db seed
```

После `seed` по умолчанию создаётся администратор:

- логин: `admin`
- пароль: `admin123`

### 10. Собрать backend

```bash
npm run build
```

### 11. Запустить backend через PM2

```bash
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

Если `pm2 startup` выведет отдельную команду, выполни её один раз под `sudo`.

### 12. Проверка

```bash
pm2 status
curl http://localhost:3000
```

Swagger после запуска будет доступен по адресу:

```text
http://YOUR_SERVER_IP:3000/api
```

## Обновление backend через Git

Базовая команда обновления, которую ты используешь:

```bash
cd /opt/n-app
git pull
npm run build
pm2 restart n-app-backend
```

Если в коммите менялась Prisma schema или миграции, после `git pull` дополнительно выполни:

```bash
npx prisma migrate deploy
```

## Если потерян логин или пароль администратора

### Вариант 1. Сбросить пароль существующему админу

Перейди в проект:

```bash
cd /opt/n-app
```

Сгенерируй новый bcrypt hash:

```bash
node -e "const bcrypt=require('bcrypt'); bcrypt.hash('NEW_ADMIN_PASSWORD',10).then(h=>console.log(h))"
```

Скопируй полученный hash.

Посмотри пользователей:

```bash
psql "$DATABASE_URL" -c "SELECT id, login, role, status FROM \"User\" ORDER BY id;"
```

Обнови нужного администратора по `id`:

```bash
psql "$DATABASE_URL" -c "UPDATE \"User\" SET login='admin', \"passwordHash\"='PASTE_BCRYPT_HASH_HERE', role='ADMIN', status='ACTIVE' WHERE id=ADMIN_ID;"
```

### Вариант 2. Создать нового администратора вручную

Сначала получи hash так же, как в примере выше.

Потом создай запись:

```bash
psql "$DATABASE_URL" -c "INSERT INTO \"User\" (fio, age, login, \"passwordHash\", role, status, \"createdAt\", \"updatedAt\") VALUES ('Главный администратор', 30, 'admin', 'PASTE_BCRYPT_HASH_HERE', 'ADMIN', 'ACTIVE', NOW(), NOW());"
```

## Frontend: что нужно для сборки APK

### Программы и инструменты

Для сборки Android APK на Windows используются:

- `Flutter SDK`
- `Dart SDK` (идёт вместе с Flutter)
- `Android Studio`
- `Android SDK Platform-Tools`
- `Android SDK Build-Tools`
- `Java` / `JBR` из Android Studio
- `adb`
- `apksigner`
- `Git`
- `PowerShell` или `cmd`

### Версии из проекта

Смотри конфиги:

- `C:\Users\user\Desktop\N APP\frontend\pubspec.yaml`
- `C:\Users\user\Desktop\N APP\frontend\android\settings.gradle`
- `C:\Users\user\Desktop\N APP\frontend\android\app\build.gradle`

Текущие важные значения:

- `AGP`: `8.9.1`
- `Kotlin`: `2.0.0`
- `minSdk`: из Flutter-конфига проекта
- `compileSdk` / `targetSdk`: из Flutter/Android-конфига проекта

### Сборка APK

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

### Установка APK через ADB

```bash
adb devices
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### Полезные скрипты в репозитории

- `C:\Users\user\Desktop\N APP\deploy\build-apk.sh`
- `C:\Users\user\Desktop\N APP\deploy\sign-apk.bat`
- `C:\Users\user\Desktop\N APP\deploy\setup-android-sdk.sh`
- `C:\Users\user\Desktop\N APP\deploy\setup-vps.sh`
- `C:\Users\user\Desktop\N APP\deploy\deploy-debian.sh`
- `C:\Users\user\Desktop\N APP\deploy\deploy-backend.sh`

## Настройка frontend API

Файл:

- `C:\Users\user\Desktop\N APP\frontend\lib\config\api_config.dart`

Если приложение собирается под реальный сервер, проверь:

- `prodBaseUrl`
- `prodWsUrl`
- флаг `isProduction`

## Файлы и загрузки

Сейчас локальное файловое хранилище работает через папку:

```text
/opt/n-app/uploads
```

Git её не отслеживает.

## Полезные команды

### Prisma

```bash
npx prisma generate
npx prisma migrate deploy
npx prisma studio
```

### PM2

```bash
pm2 status
pm2 logs n-app-backend
pm2 restart n-app-backend
pm2 stop n-app-backend
```

### Git

```bash
git status
git pull
git log --oneline -n 10
```

## Что ещё важно

- `README.md` — быстрая инструкция
- `ARCHITECTURE.md` — архитектура и ограничения
- `DEPLOY.md` — дополнительная инструкция по развёртыванию
- `plans/push-notifications.md` — план по FCM
- `plans/turn-server.md` — план по TURN
