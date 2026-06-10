# Инструкция по развёртыванию N App

## Требования

- **Сервер:** Linux VPS (Ubuntu 20.04+)
- **База данных:** PostgreSQL 14+
- **Файловое хранилище:** MinIO (S3-совместимое)
- **Среда выполнения:** Node.js 20+
- **Сборка APK:** Flutter SDK (на машине разработчика)

---

## 1. Настройка сервера

Скопируйте скрипт на сервер и выполните:

```bash
chmod +x deploy/setup-vps.sh
sudo ./deploy/setup-vps.sh
```

Скрипт автоматически:
- Установит PostgreSQL и создаст базу данных `n_app`
- Установит MinIO (S3-хранилище для файлов)
- Установит Node.js 20.x
- Установит PM2 для управления процессами
- Настроит firewall (SSH, порты 3000, 9000, 9001)

---

## 2. Связь GitHub с Debian сервером

Этот раздел описывает, как связать GitHub-репозиторий с вашим Debian-сервером для автоматического деплоя через `git pull`.

### 2.1. Установка Git на Debian

```bash
sudo apt update
sudo apt install git -y
git --version
```

### 2.2. Клонирование репозитория на сервер

**Важно:** Директория `/opt/n-app` не должна существовать или должна быть пуста, иначе `git clone` не сработает.

```bash
# Удалить старую директорию, если она есть (но не содержит нужных данных!)
sudo rm -rf /opt/n-app

# Клонировать репозиторий
sudo git clone https://github.com/den063rus-design/n-app.git /opt/n-app
sudo chown -R $USER:$USER /opt/n-app
cd /opt/n-app
```

### 2.3. Настройка SSH deploy key (рекомендуется)

SSH-ключ позволяет пулить без ввода пароля.

**На сервере Debian** сгенерируйте ключ:

```bash
ssh-keygen -t ed25519 -C "deploy-key" -f ~/.ssh/deploy_key
cat ~/.ssh/deploy_key.pub
```

**В GitHub:**
1. Перейдите: `Settings → SSH and GPG keys → New SSH key`
2. Title: `N App Debian Server`
3. Key: вставьте содержимое `~/.ssh/deploy_key.pub`
4. Нажмите **Add SSH key**

**На сервере** смените remote на SSH (выполнять ТОЛЬКО после `git clone`):

```bash
cd /opt/n-app
git remote set-url origin git@github.com:den063rus-design/n-app.git
```

Проверьте подключение:

```bash
ssh -T git@github.com
# Ожидаемый ответ: Hi den063rus-design/n-app! You've successfully authenticated...
```

### 2.4. Быстрый деплой одной командой

После настройки SSH ключа деплой делается одной командой:

```bash
cd /opt/n-app && git pull && npm install && npm run build && npx prisma generate && npx prisma migrate deploy && pm2 restart n-app-backend
```

Или через готовый скрипт:

```bash
chmod +x deploy/deploy-debian.sh
./deploy/deploy-debian.sh
```

### 2.5. Что делает скрипт deploy-debian.sh

Скрипт [`deploy/deploy-debian.sh`](deploy/deploy-debian.sh) автоматически:

1. Переходит в `/opt/n-app`
2. Сохраняет текущий `.env` (чтобы не потерять настройки)
3. Выполняет `git fetch origin && git reset --hard origin/main` — стягивает последнюю версию
4. Восстанавливает `.env` из бэкапа (или создаёт из `.env.production`)
5. Устанавливает npm-зависимости (`npm install --production`)
6. Собирает проект (`npm run build`)
7. Генерирует Prisma Client (`npx prisma generate`)
8. Применяет миграции БД (`npx prisma migrate deploy`)
9. Запускает seed (если нужно)
10. Перезапускает PM2 процесс
11. Проверяет, что сервер запустился

### 2.6. Рабочий процесс

```
[Локальный ПК]           [GitHub]              [Debian Server]
     │                      │                       │
     ├── git add . ────────►│                       │
     ├── git commit ───────►│                       │
     ├── git push ─────────►│                       │
     │                      │                       │
     │                      │                       │◄── ssh
     │                      ├── git pull ───────────┤
     │                      │                       ├── npm install
     │                      │                       ├── npm run build
     │                      │                       ├── prisma migrate
     │                      │                       └── pm2 restart
```

**Процесс обновления:**
1. Вносите изменения локально
2. Коммитите и пушите в GitHub
3. Заходите на сервер по SSH
4. Запускаете `./deploy/deploy-debian.sh`
5. Готово! 🚀

---

## 3. Деплой бэкенда

### 3.1. Копирование файлов на сервер (без Git)

Если вы не используете Git-связку, можно скопировать файлы вручную:

```bash
# Замените user и server на ваши данные
scp -r . user@your-server:/opt/n-app
```

### 3.2. Настройка окружения

```bash
ssh user@your-server
cd /opt/n-app
cp .env.production .env
```

**Важно:** Отредактируйте `.env`:
- Замените `JWT_SECRET` на сгенерированную случайную строку (можно использовать `openssl rand -hex 32`)
- Укажите реальный `MINIO_ENDPOINT`, если MinIO на другом сервере

### 3.3. Запуск деплоя

```bash
chmod +x deploy/deploy-backend.sh
./deploy/deploy-backend.sh
```

Скрипт выполнит:
1. Установку npm-зависимостей
2. Сборку NestJS (`npm run build`)
3. Генерацию Prisma Client и миграции БД
4. Заполнение БД начальными данными (seed)
5. Запуск через PM2 с авторестартом

### 3.4. Управление бэкендом

```bash
# Статус
pm2 status

# Логи
pm2 logs n-app-backend

# Перезапуск
pm2 restart n-app-backend

# Остановка
pm2 stop n-app-backend
```

---

## 4. Сборка APK

Сборка может выполняться как на локальной машине, так и на сервере Debian с установленным Flutter SDK.

### 4.1. Настройка production-конфигурации

Перед сборкой отредактируйте [`frontend/lib/config/api_config.dart`](frontend/lib/config/api_config.dart):

```dart
static const bool isProduction = true; // Меняем на true
```

И укажите URL вашего сервера:

```dart
static const String prodBaseUrl = 'http://95.170.111.146:3000';
static const String prodWsUrl = 'ws://95.170.111.146:3000';
```

> **Важно:** Если приложение и сервер на одной машине (тестирование), можно использовать `localhost:3000`. Для продакшена — укажите реальный IP или домен сервера.

### 4.2. Установка Flutter SDK на Debian сервер

Если вы собираете APK прямо на сервере, установите Flutter SDK:

```bash
# 1. Перейдите в /opt
cd /opt

# 2. Скачайте стабильную версию Flutter
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.1-stable.tar.xz

# 3. Распакуйте
tar -xf flutter_linux_3.27.1-stable.tar.xz

# 4. Добавьте Flutter в PATH (временно)
export PATH="/opt/flutter/bin:$PATH"

# 5. Добавьте в ~/.bashrc (постоянно)
echo 'export PATH="/opt/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 6. Проверьте версию
flutter --version
# Ожидаемый вывод: Flutter 3.27.1 • channel stable • ...
```

#### Решение проблем с Flutter на Debian

**Проблема: `fatal: detected dubious ownership in repository at '/opt/flutter'`**

```bash
git config --global --add safe.directory /opt/flutter
```

**Проблема: `The current Flutter SDK version is 0.0.0-unknown`**

Это означает, что Flutter SDK повреждён или установлен некорректно. Решение — переустановить:

```bash
cd /opt
rm -rf flutter
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.1-stable.tar.xz
tar -xf flutter_linux_3.27.1-stable.tar.xz
export PATH="/opt/flutter/bin:$PATH"
flutter --version
```

**Проблема: `Flutter requires Android SDK`**

Установите Android SDK Command Line Tools:

```bash
# 1. Установите Java (требуется для Android SDK)
sudo apt install openjdk-17-jdk -y

# 2. Скачайте Android SDK command line tools
cd /opt
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-11076708_latest.zip -d android-sdk
rm commandlinetools-linux-11076708_latest.zip

# 3. Настройте переменные
export ANDROID_HOME="/opt/android-sdk"
export PATH="$ANDROID_HOME/cmdline-tools/bin:$PATH"
echo 'export ANDROID_HOME="/opt/android-sdk"' >> ~/.bashrc
echo 'export PATH="$ANDROID_HOME/cmdline-tools/bin:$PATH"' >> ~/.bashrc

# 4. Примите лицензии
yes | sdkmanager --sdk_root=$ANDROID_HOME --licenses

# 5. Установите необходимые компоненты
sdkmanager --sdk_root=$ANDROID_HOME "platforms;android-34" "build-tools;34.0.0"
```

### 4.3. Запуск сборки

Используйте готовый скрипт:

```bash
chmod +x deploy/build-apk.sh
./deploy/build-apk.sh
```

Скрипт автоматически проверит наличие Flutter SDK и его версию.

APK будет создан по пути:
```
frontend/build/app/outputs/flutter-apk/app-release.apk
```

### 4.4. Установка на устройство

**Через ADB (подключённое устройство):**
```bash
adb install frontend/build/app/outputs/flutter-apk/app-release.apk
```

**Вручную:**
1. Скопируйте `app-release.apk` на Android-устройство
2. Откройте файл через файловый менеджер
3. Разрешите установку из неизвестных источников
4. Установите

**С сервера на локальный ПК (через SCP):**
```bash
# На локальном ПК выполните:
scp root@koha-server:/opt/n-app/frontend/build/app/outputs/flutter-apk/app-release.apk ./
```

**Через Telegram:** можно отправить APK самому себе в Telegram (работает как файл).

**Через облако:** загрузите на Dropbox, Google Drive или Яндекс.Диск и скачайте на телефон.

---

## 5. Проверка работоспособности

После деплоя проверьте:

### 5.1. API сервер

```bash
curl http://localhost:3000/api/health
# Ожидаемый ответ: { "status": "ok" }
```

### 5.2. База данных

```bash
sudo -u postgres psql -c "\l" | grep n_app
# Должна быть база n_app
```

### 5.3. MinIO

Откройте в браузере: `http://your-server:9001`
- Логин: `minioadmin`
- Пароль: `minioadmin`

### 5.4. Приложение

1. Откройте приложение на устройстве
2. Войдите как администратор: `admin` / `admin123`
3. Создайте тестового пользователя
4. Проверьте отправку сообщений в чате
5. Проверьте видеозвонки

---

## 6. Дополнительная информация

### 6.1. Обновление бэкенда

```bash
cd /opt/n-app
git pull
npm install
npm run build
npx prisma generate
npx prisma migrate deploy
pm2 restart n-app-backend
```

### 6.2. Бэкап базы данных

```bash
pg_dump -U postgres n_app > backup_$(date +%Y%m%d).sql
```

### 6.3. Восстановление базы данных

```bash
psql -U postgres n_app < backup.sql
```

### 6.4. Структура проекта

```
n-app/
├── deploy/                  # Скрипты деплоя
│   ├── setup-vps.sh        # Настройка сервера
│   ├── deploy-backend.sh   # Деплой бэкенда
│   ├── deploy-debian.sh    # Деплой на Debian через Git
│   └── build-apk.sh        # Сборка APK
├── frontend/               # Flutter приложение
├── prisma/                 # Prisma схема и миграции
├── src/                    # NestJS бэкенд
├── .env.production         # Production переменные
├── ecosystem.config.js     # PM2 конфигурация
└── DEPLOY.md               # Эта инструкция