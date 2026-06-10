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

# Проверка Flutter SDK
if ! command -v flutter &> /dev/null; then
    echo "Ошибка: Flutter SDK не найден!"
    echo ""
    echo "Установите Flutter SDK:"
    echo "  cd /opt"
    echo "  wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.1-stable.tar.xz"
    echo "  tar -xf flutter_linux_3.27.1-stable.tar.xz"
    echo "  export PATH=\"/opt/flutter/bin:\$PATH\""
    echo ""
    echo "Или добавьте в ~/.bashrc:"
    echo "  echo 'export PATH=\"/opt/flutter/bin:\$PATH\"' >> ~/.bashrc"
    echo "  source ~/.bashrc"
    exit 1
fi

# Проверка версии Flutter
FLUTTER_VERSION=$(flutter --version 2>&1 | head -1)
echo "Flutter: $FLUTTER_VERSION"

if echo "$FLUTTER_VERSION" | grep -q "unknown"; then
    echo ""
    echo "Ошибка: Flutter SDK повреждён или установлен некорректно (версия 0.0.0-unknown)."
    echo ""
    echo "Решение:"
    echo "  1. Добавьте Flutter в safe.directory:"
    echo "     git config --global --add safe.directory /opt/flutter"
    echo ""
    echo "  2. Если не помогло — переустановите Flutter:"
    echo "     cd /opt"
    echo "     rm -rf flutter"
    echo "     wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.1-stable.tar.xz"
    echo "     tar -xf flutter_linux_3.27.1-stable.tar.xz"
    echo "     export PATH=\"/opt/flutter/bin:\$PATH\""
    echo "     flutter --version"
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
APK_PATH="$FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo "APK файл: $APK_PATH"
echo ""
echo "Размер: $(ls -lh "$APK_PATH" 2>/dev/null | awk '{print $5}')"
echo ""
echo "Для установки на устройство:"
echo "  adb install $APK_PATH"
echo ""
echo "Для копирования на сервер (если собираете локально):"
echo "  scp user@your-server:$APK_PATH ./"
echo ""