#!/bin/bash
# Скрипт установки Android SDK для сборки Flutter APK на Debian
# Использование: chmod +x setup-android-sdk.sh && sudo ./setup-android-sdk.sh

set -e

echo "========================================"
echo "  Установка Android SDK для Flutter"
echo "========================================"

# 1. Установка Java 17
echo "[1/5] Установка Java 17..."
if ! command -v java &> /dev/null; then
    apt update
    apt install -y openjdk-17-jdk unzip wget
else
    echo "  Java уже установлена: $(java --version 2>&1 | head -1)"
fi

# 2. Установка Android SDK Command Line Tools
ANDROID_SDK_ROOT="/opt/android-sdk"
echo "[2/5] Установка Android SDK Command Line Tools в $ANDROID_SDK_ROOT..."

if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools" ]; then
    mkdir -p "$ANDROID_SDK_ROOT"
    cd /tmp
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
    unzip -q cmdline-tools.zip -d "$ANDROID_SDK_ROOT"
    rm cmdline-tools.zip
    
    # Структура: cmdline-tools/tools/bin/sdkmanager
    # Но Android SDK ожидает: cmdline-tools/latest/bin/sdkmanager
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mv "$ANDROID_SDK_ROOT/cmdline-tools/bin" "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
    mv "$ANDROID_SDK_ROOT/cmdline-tools/lib" "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
    mv "$ANDROID_SDK_ROOT/cmdline-tools/NOTICE.txt" "$ANDROID_SDK_ROOT/cmdline-tools/latest/" 2>/dev/null || true
    mv "$ANDROID_SDK_ROOT/cmdline-tools/source.properties" "$ANDROID_SDK_ROOT/cmdline-tools/latest/" 2>/dev/null || true
    
    echo "  Command Line Tools установлены"
else
    echo "  Command Line Tools уже установлены"
fi

# 3. Настройка переменных окружения
echo "[3/5] Настройка переменных окружения..."

# Удаляем старые записи, если есть
sed -i '/ANDROID_HOME/d' ~/.bashrc
sed -i '/ANDROID_SDK_ROOT/d' ~/.bashrc
sed -i '/cmdline-tools/d' ~/.bashrc
sed -i '/platform-tools/d' ~/.bashrc

cat >> ~/.bashrc << 'EOF'

# Android SDK
export ANDROID_HOME="/opt/android-sdk"
export ANDROID_SDK_ROOT="/opt/android-sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export PATH="$ANDROID_HOME/tools:$PATH"
EOF

# Применяем для текущей сессии
export ANDROID_HOME="/opt/android-sdk"
export ANDROID_SDK_ROOT="/opt/android-sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export PATH="$ANDROID_HOME/tools:$PATH"

echo "  Переменные окружения настроены"

# 4. Принятие лицензий и установка компонентов
echo "[4/5] Принятие лицензий Android SDK..."

yes | sdkmanager --sdk_root=$ANDROID_SDK_ROOT --licenses 2>/dev/null || true

echo "[5/5] Установка компонентов Android SDK..."

sdkmanager --sdk_root=$ANDROID_SDK_ROOT "platforms;android-34" "build-tools;34.0.0" "platform-tools" 2>/dev/null || true

echo ""
echo "========================================"
echo "  Установка Android SDK завершена!"
echo "========================================"
echo ""
echo "Проверка:"
echo "  echo \$ANDROID_HOME  -> $ANDROID_HOME"
echo ""
echo "Теперь можно собирать APK:"
echo "  cd /opt/n-app && ./deploy/build-apk.sh"
echo ""
echo "Или вручную:"
echo "  cd /opt/n-app/frontend && flutter build apk --release"
echo ""