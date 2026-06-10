#!/bin/bash
# Скрипт сборки APK для N App
# Использование: chmod +x build-apk.sh && ./build-apk.sh

set -e

echo "========================================"
echo "  Сборка APK N App"
echo "========================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_DIR/frontend"

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "Ошибка: Директория frontend не найдена в $PROJECT_DIR"
    exit 1
fi

cd "$FRONTEND_DIR"

# 1. Очистка
echo "[1/4] Очистка проекта..."
flutter clean

# 2. Установка зависимостей
echo "[2/4] Установка зависимостей..."
flutter pub get

# 3. Сборка APK
echo "[3/4] Сборка APK (release)..."
flutter build apk --release

echo ""
echo "========================================"
echo "  Сборка APK завершена!"
echo "========================================"
echo ""
echo "APK файл: $FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "Для установки на устройство:"
echo "  adb install $FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo ""