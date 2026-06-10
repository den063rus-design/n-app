@echo off
REM ============================================
REM Sign APK with production keystore
REM Usage: sign-apk.bat [apk-file]
REM If no file specified, signs all APKs in build output
REM ============================================

set KEYSTORE=%~dp0..\frontend\android\upload-keystore.jks
set APKSIGNER=%USERPROFILE%\AppData\Local\Android\Sdk\build-tools\34.0.0\apksigner.bat
set APK_DIR=%~dp0..\frontend\build\app\outputs\flutter-apk

if not exist "%APKSIGNER%" (
    echo [ERROR] apksigner not found at: %APKSIGNER%
    echo Please install Android SDK build-tools 34.0.0
    exit /b 1
)

if not exist "%KEYSTORE%" (
    echo [ERROR] Keystore not found at: %KEYSTORE%
    echo Please run: keytool -genkey -v -keystore "%KEYSTORE%" -alias upload -keyalg RSA -keysize 2048 -validity 10000
    exit /b 1
)

if not "%1"=="" (
    set APK_FILE=%1
    if not exist "%APK_FILE%" (
        echo [ERROR] APK file not found: %APK_FILE%
        exit /b 1
    )
    echo [SIGNING] %APK_FILE%
    "%APKSIGNER%" sign --ks "%KEYSTORE%" --ks-key-alias upload --ks-pass pass:napp123 --key-pass pass:napp123 --out "%APK_FILE%" "%APK_FILE%"
    if %ERRORLEVEL% equ 0 (
        echo [OK] Signed successfully
    ) else (
        echo [FAILED] Signing failed
    )
    exit /b %ERRORLEVEL%
)

echo [SIGNING] All APKs in %APK_DIR%
for %%f in ("%APK_DIR%\*-release.apk") do (
    echo [SIGNING] %%~nxf
    "%APKSIGNER%" sign --ks "%KEYSTORE%" --ks-key-alias upload --ks-pass pass:napp123 --key-pass pass:napp123 --out "%%f" "%%f"
    if !ERRORLEVEL! equ 0 (
        echo [OK] %%~nxf signed
    ) else (
        echo [FAILED] %%~nxf
    )
)

echo [DONE] All APKs signed