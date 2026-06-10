#!/bin/bash

# ============================================
# N App - Deploy Script for Debian
# Использование: bash deploy/deploy-debian.sh
# ============================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  N App - Деплой на Debian${NC}"
echo -e "${GREEN}============================================${NC}"

# Конфигурация
PROJECT_DIR="/opt/n-app"
BRANCH="main"

# 1. Перейти в директорию проекта
echo -e "\n${YELLOW}📁 Перехожу в директорию проекта...${NC}"
cd "$PROJECT_DIR" || {
    echo -e "${RED}❌ Директория $PROJECT_DIR не найдена!${NC}"
    echo -e "${YELLOW}Сначала клонируй репозиторий:${NC}"
    echo "   git clone https://github.com/den063rus-design/n-app.git $PROJECT_DIR"
    exit 1
}

# 2. Сохранить текущий .env если есть
if [ -f .env ]; then
    echo -e "${YELLOW}💾 Сохраняю текущий .env...${NC}"
    cp .env /tmp/n-app-env-backup
fi

# 3. Стянуть последние изменения с GitHub
echo -e "\n${YELLOW}📥 Стягиваю последние изменения с GitHub...${NC}"
git fetch origin
git reset --hard "origin/$BRANCH"
git clean -fd

echo -e "${GREEN}✅ Последний коммит:${NC}"
git log --oneline -1

# 4. Восстановить .env
if [ -f /tmp/n-app-env-backup ]; then
    echo -e "${YELLOW}♻️ Восстанавливаю .env...${NC}"
    cp /tmp/n-app-env-backup .env
    rm /tmp/n-app-env-backup
elif [ ! -f .env ]; then
    echo -e "${YELLOW}⚠️ .env не найден. Создаю из .env.production...${NC}"
    if [ -f .env.production ]; then
        cp .env.production .env
        echo -e "${RED}⚠️ ВАЖНО: Отредактируй .env и укажи правильные данные!${NC}"
        echo "   nano .env"
    fi
fi

# 5. Установить зависимости
echo -e "\n${YELLOW}📦 Устанавливаю npm зависимости...${NC}"
npm install --production

# 6. Собрать проект
echo -e "\n${YELLOW}🔨 Собираю проект...${NC}"
npm run build

# 7. Сгенерировать Prisma клиент
echo -e "\n${YELLOW}🗄️  Генерирую Prisma клиент...${NC}"
npx prisma generate

# 8. Применить миграции
echo -e "\n${YELLOW}🗄️  Применяю миграции БД...${NC}"
npx prisma migrate deploy

# 9. Запустить seed
echo -e "\n${YELLOW}🌱 Запускаю seed...${NC}"
npx prisma db seed || echo -e "${YELLOW}⚠️ Seed пропущен (возможно уже есть данные)${NC}"

# 10. Перезапустить PM2
echo -e "\n${YELLOW}🔄 Перезапускаю PM2...${NC}"
pm2 delete n-app-backend 2>/dev/null || true
pm2 start dist/main.js --name n-app-backend
pm2 save

# 11. Проверить статус
sleep 2
if pm2 show n-app-backend | grep -q "online"; then
    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  ✅ Деплой завершён успешно!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "📌 Сервер запущен на порту: ${YELLOW}3000${NC}"
    echo -e "📌 Логи: ${YELLOW}pm2 logs n-app-backend${NC}"
    echo -e "📌 Статус: ${YELLOW}pm2 status${NC}"
else
    echo -e "\n${RED}❌ Ошибка: сервер не запустился!${NC}"
    echo -e "📌 Проверь логи: ${YELLOW}pm2 logs n-app-backend${NC}"
fi