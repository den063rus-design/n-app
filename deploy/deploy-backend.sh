#!/bin/bash
# Скрипт деплоя бэкенда N App
# Использование: chmod +x deploy-backend.sh && ./deploy-backend.sh

set -e

echo "========================================"
echo "  Деплой бэкенда N App"
echo "========================================"

PROJECT_DIR="/opt/n-app"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Ошибка: Директория $PROJECT_DIR не найдена"
    echo "Сначала скопируйте проект: scp -r . user@server:$PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# 1. Установка зависимостей
echo "[1/5] Установка npm зависимостей..."
npm install

# 2. Сборка NestJS
echo "[2/5] Сборка NestJS..."
npm run build

# 3. Prisma миграции
echo "[3/5] Prisma миграции..."
npx prisma generate
npx prisma migrate deploy

# 4. Seed базы данных
echo "[4/5] Seed базы данных..."
npx prisma db seed

# 5. Запуск через PM2
echo "[5/5] Запуск через PM2..."
pm2 delete n-app-backend 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save

echo ""
echo "========================================"
echo "  Деплой бэкенда завершён!"
echo "========================================"
echo ""
echo "Проверка статуса: pm2 status"
echo "Просмотр логов: pm2 logs n-app-backend"
echo ""