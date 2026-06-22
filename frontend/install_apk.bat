@echo off
chcp 65001 >nul
set ADB=C:\Users\user\AppData\Local\Android\sdk\platform-tools\adb.exe
set APK=build\app\outputs\flutter-apk\app-release.apk
set PACKAGE=com.napp.app

echo ============================================
echo  Установка N App на оба телефона
echo ============================================
echo.

if not exist "%APK%" (
    echo [ОШИБКА] APK не найден: %APK%
    echo Сначала собери: flutter build apk --release
    pause
    exit /b 1
)

echo [1/2] Устройство: 115662544C001051
echo.
echo Удаление старой версии...
"%ADB%" -s 115662544C001051 uninstall %PACKAGE% 2>nul
echo Установка новой версии...
"%ADB%" -s 115662544C001051 install "%APK%"
if %errorlevel% equ 0 (
    echo [OK] Установлено успешно
) else (
    echo [ОШИБКА] Установка не удалась
)
echo.

echo [2/2] Устройство: BGHBB20414201551
echo.
echo Удаление старой версии...
"%ADB%" -s BGHBB20414201551 uninstall %PACKAGE% 2>nul
echo Установка новой версии...
"%ADB%" -s BGHBB20414201551 install "%APK%"
if %errorlevel% equ 0 (
    echo [OK] Установлено успешно
) else (
    echo [ОШИБКА] Установка не удалась
)
echo.
echo ============================================
echo  Готово!
echo ============================================
pause