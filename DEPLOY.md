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

## 2. Деплой бэкенда

### 2.1. Копирование файлов на сервер

```bash
# Замените user и server на ваши данные
scp -r . user@your-server:/opt/n-app
```

### 2.2. Настройка окружения

```bash
ssh user@your-server
cd /opt/n-app
cp .env.production .env
```

**Важно:** Отредактируйте `.env`:
- Замените `JWT_SECRET` на сгенерированную случайную строку (можно использовать `openssl rand -hex 32`)
- Укажите реальный `MINIO_ENDPOINT`, если MinIO на другом сервере

### 2.3. Запуск деплоя

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

### 2.4. Управление бэкендом

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

## 3. Сборка APK

Сборка выполняется на машине с установленным Flutter SDK.

### 3.1. Настройка production-конфигурации

Перед сборкой отредактируйте [`frontend/lib/config/api_config.dart`](frontend/lib/config/api_config.dart):

```dart
static const bool isProduction = true; // Меняем на true
```

И укажите URL вашего сервера:

```dart
static const String prodBaseUrl = 'https://ваш-сервер.ru';
static const String prodWsUrl = 'wss://ваш-сервер.ru';
```

### 3.2. Запуск сборки

```bash
chmod +x deploy/build-apk.sh
./deploy/build-apk.sh
```

APK будет создан по пути:
```
frontend/build/app/outputs/flutter-apk/app-release.apk
```

### 3.3. Установка на устройство

**Через ADB (подключённое устройство):**
```bash
adb install frontend/build/app/outputs/flutter-apk/app-release.apk
```

**Вручную:**
1. Скопируйте `app-release.apk` на Android-устройство
2. Откройте файл через файловый менеджер
3. Разрешите установку из неизвестных источников
4. Установите

---

## 4. Проверка работоспособности

После деплоя проверьте:

### 4.1. API сервер

```bash
curl http://localhost:3000/api/health
# Ожидаемый ответ: { "status": "ok" }
```

### 4.2. База данных

```bash
sudo -u postgres psql -c "\l" | grep n_app
# Должна быть база n_app
```

### 4.3. MinIO

Откройте в браузере: `http://your-server:9001`
- Логин: `minioadmin`
- Пароль: `minioadmin`

### 4.4. Приложение

1. Откройте приложение на устройстве
2. Войдите как администратор: `admin` / `admin123`
3. Создайте тестового пользователя
4. Проверьте отправку сообщений в чате
5. Проверьте видеозвонки

---

## 5. Дополнительная информация

### 5.1. Обновление бэкенда

```bash
cd /opt/n-app
git pull
npm install
npm run build
npx prisma generate
npx prisma migrate deploy
pm2 restart n-app-backend
```

### 5.2. Бэкап базы данных

```bash
pg_dump -U postgres n_app > backup_$(date +%Y%m%d).sql
```

### 5.3. Восстановление базы данных

```bash
psql -U postgres n_app < backup.sql
```

### 5.4. Структура проекта

```
n-app/
├── deploy/                  # Скрипты деплоя
│   ├── setup-vps.sh        # Настройка сервера
│   ├── deploy-backend.sh   # Деплой бэкенда
│   └── build-apk.sh        # Сборка APK
├── frontend/               # Flutter приложение
├── prisma/                 # Prisma схема и миграции
├── src/                    # NestJS бэкенд
├── .env.production         # Production переменные
├── ecosystem.config.js     # PM2 конфигурация
└── DEPLOY.md               # Эта инструкция