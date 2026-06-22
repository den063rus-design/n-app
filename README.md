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
- поиск по чату
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
  call/
  chat/
  common/
  config/
  files/
  notifications/
  prisma/
  users/
frontend/
  lib/
    screens/
      admin_screen.dart
      archive_screen.dart
      call_screen.dart
      chat_screen.dart
      chat_search_delegate.dart
      create_user_screen.dart
      edit_user_screen.dart
      login_screen.dart
      notifications_screen.dart
      user_card_screen.dart
      user_screen.dart
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

Создай локальный файл `.env` по аналогии, а на сервере файл должен лежать в `/opt/n-app/.env`.

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

___________________________________________________________________

## Как заливать на сервер только backend

Если тебе нужен сервер, где крутится только backend, тут есть 2 рабочих варианта.

### Лучший и самый простой вариант

Просто клонируешь весь репозиторий на сервер и запускаешь только backend.

Что будет:

- `frontend/`, `plans/`, `docs/` просто лежат как файлы
- они никак не крутятся и не мешают backend
- на сервере реально работает только `pm2 -> dist/main.js`

Если тебе важно именно чтобы на сервере работал только backend — ничего удалять не обязательно.

### Если хочешь оставить только нужные backend-файлы

Тогда лучше использовать `sparse checkout`.
Это режим Git, когда на сервер сразу подтягиваются только нужные файлы и папки.

#### Что нужно для backend

- `src/`
- `prisma/`
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `tsconfig.build.json`
- `nest-cli.json`
- `ecosystem.config.js`
- `.env` — создаётся на сервере вручную
- `uploads/` — создастся и будет использоваться backend

#### Что не нужно для backend-only сервера

- `frontend/`
- `plans/`
- `docs/`
- `README.md`
- `ARCHITECTURE.md`
- `DEPLOY.md`
- Android / Flutter файлы целиком

### Как сразу забрать только backend

```bash
mkdir -p /opt/n-app
cd /opt/n-app
git init
git remote add origin https://github.com/den063rus-design/n-app.git
git config core.sparseCheckout true
printf "src/\nprisma/\npackage.json\npackage-lock.json\ntsconfig.json\ntsconfig.build.json\nnest-cli.json\necosystem.config.js\n" > .git/info/sparse-checkout
git pull origin main
```

Потом:

```bash
npm install
npx prisma generate
npx prisma migrate deploy
npm run build
pm2 start ecosystem.config.js
```

### Если уже склонировал весь проект

Лишнее можно удалить вручную:

```bash
rm -rf frontend docs plans
rm -f README.md ARCHITECTURE.md DEPLOY.md
```

Но такой вариант не рекомендуется, потому что:

- потом могут быть неудобства при `git pull`
- можно случайно удалить полезные файлы
- обычно проще хранить полный репозиторий и просто запускать только backend

### Моя рекомендация

- если хочешь без лишнего геморроя — клонируй весь репозиторий
- если хочешь максимально чистый backend-only сервер — делай `sparse checkout`

### Итог

Самый практичный путь:

- либо не удалять ничего после `git clone`
- либо сразу использовать `sparse checkout`

Сам backend от наличия `frontend/` на сервере не страдает.

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
- `Gradle`
- `Java` / `JBR` из Android Studio
- `adb`
- `apksigner`
- `Git`
- `PowerShell` или `cmd`

### Версии из проекта

Смотри конфиги:

- `frontend/pubspec.yaml`
- `frontend/android/settings.gradle`
- `frontend/android/app/build.gradle`

Текущие важные значения:

- `AGP`: `8.9.1`
- `Kotlin`: `2.0.0`
- `applicationId`: `com.napp.app`
- `minSdk`: берётся из Flutter Android-конфига
- `compileSdk`: берётся из Flutter Android-конфига
- `targetSdk`: берётся из Flutter Android-конфига

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

### Секреты для Android-подписи и Firebase

Не храните в git реальные секреты:

- `frontend/android/key.properties`
- `frontend/android/*.jks`
- Firebase service account JSON

Используйте только локальные ignored-файлы:

- `frontend/android/key.properties` — создаётся из `frontend/android/key.properties.example`
- `firebase-service-account.json` — создаётся локально из `firebase-service-account.example.json`

### Полезные скрипты в репозитории

- `deploy/build-apk.sh`
- `deploy/sign-apk.bat`
- `deploy/setup-android-sdk.sh`
- `deploy/setup-vps.sh`
- `deploy/deploy-debian.sh`
- `deploy/deploy-backend.sh`

## Настройка frontend API

Файл:

- `frontend/lib/config/api_config.dart`

Если приложение собирается под реальный сервер, проверь:

- `prodBaseUrl`
- `prodWsUrl`
- флаг `isProduction`

## Основные backend-модули

- `auth` — вход и JWT
- `users` — создание, изменение, блокировка, архив
- `chat` — сообщения, история, статусы
- `files` — upload / download / delete файлов
- `call` — signaling и логика звонков
- `notifications` — in-app уведомления

## Основные экраны frontend

- `login_screen.dart` — вход
- `admin_screen.dart` — список пользователей
- `chat_screen.dart` — чат администратора с пользователем
- `user_screen.dart` — чат пользователя
- `call_screen.dart` — видеозвонок
- `notifications_screen.dart` — уведомления
- `archive_screen.dart` — архив пользователей
- `chat_search_delegate.dart` — поиск по сообщениям и вложениям

## Файлы и загрузки

### Схема хранения

Файлы хранятся в папках пользователей по схеме:

```text
uploads/{userId}_{slug}/uuid.ext
```

Пример:

```text
uploads/12_ivanov_ivan_ivanovich/3f2c8d9a.jpg
```

- `userId` — уникальный ID пользователя (гарантирует уникальность)
- `slug` — транслитерированное ФИО в латинице (lowercase, пробелы заменены на `_`)
- Длина slug ограничена 50 символами

### Обратная совместимость

Старые файлы с плоским ключом (`uuid.jpg`) продолжают работать.
Новые файлы получают ключ с подпапкой (`12_ivanov_ivan_ivanovich/uuid.jpg`).

### GET /files/:key

Маршрут использует wildcard-параметр `:key(*)`, что позволяет читать файлы
как со старыми плоскими ключами, так и с новыми вложенными путями.

### Удаление файлов

При удалении сообщения администратором backend автоматически удаляет
связанные физические файлы из папки `uploads/`. Если файл уже отсутствует
на диске — запрос не ломается, ошибка логируется.

### Локальное хранилище

```text
/opt/n-app/uploads
```

Git папку не отслеживает. Для продакшена можно подключить MinIO
(переменная `FILE_STORAGE_DRIVER=minio`).

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
