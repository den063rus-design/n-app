#!/bin/bash
# Скрипт настройки VPS сервера для N App
# Использование: chmod +x setup-vps.sh && sudo ./setup-vps.sh

set -e

echo "========================================"
echo "  Настройка VPS сервера для N App"
echo "========================================"

# 1. Установка PostgreSQL
echo "[1/6] Установка PostgreSQL..."
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Создание БД и пользователя
echo "[2/6] Создание базы данных..."
sudo -u postgres psql -c "CREATE DATABASE n_app;" 2>/dev/null || echo "  База данных n_app уже существует"
echo "  Задайте пароль пользователя postgres вручную через psql"

# 3. Установка MinIO
echo "[3/6] Установка MinIO..."
if ! command -v minio &> /dev/null; then
    wget -q https://dl.min.io/server/minio/release/linux-amd64/minio -O /tmp/minio
    chmod +x /tmp/minio
    sudo mv /tmp/minio /usr/local/bin/
    sudo mkdir -p /data/minio
    echo "  MinIO установлен"
else
    echo "  MinIO уже установлен"
fi

# Запуск MinIO (в фоне)
echo "  Запуск MinIO..."
export MINIO_ROOT_USER="${MINIO_ROOT_USER:-CHANGE_ME_MINIO_USER}"
export MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-CHANGE_ME_MINIO_PASSWORD}"
nohup minio server /data/minio --console-address ":9001" > /var/log/minio.log 2>&1 &
echo "  MinIO запущен на порту 9000 (консоль: 9001)"

# 4. Установка Node.js 20.x
echo "[4/6] Установка Node.js..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "  Node.js уже установлен: $(node --version)"
fi

# 5. Установка PM2
echo "[5/6] Установка PM2..."
if ! command -v pm2 &> /dev/null; then
    sudo npm install -g pm2
else
    echo "  PM2 уже установлен: $(pm2 --version)"
fi

# 6. Настройка firewall
echo "[6/6] Настройка firewall..."
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 3000/tcp  # Backend API
sudo ufw allow 9000/tcp  # MinIO API
sudo ufw allow 9001/tcp  # MinIO Console
sudo ufw --force enable

echo ""
echo "========================================"
echo "  Настройка VPS завершена!"
echo "========================================"
echo ""
echo "Далее:"
echo "  1. Скопируйте проект на сервер:"
echo "     scp -r . user@server:/opt/n-app"
echo "  2. Запустите деплой бэкенда:"
echo "     cd /opt/n-app && ./deploy/deploy-backend.sh"
echo ""
