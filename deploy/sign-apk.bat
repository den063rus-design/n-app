@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM ============================================
REM Sign APK with local keystore from key.properties
REM Usage: sign-apk.bat [apk-file]
REM If no file specified, signs all release APKs in build output
REM ============================================

set KEY_PROPS=%~dp0..\frontend\android\key.properties
set APKSIGNER=%USERPROFILE%\AppData\Local\Android\Sdk\build-tools\34.0.0\apksigner.bat
set APK_DIR=%~dp0..\frontend\build\app\outputs\flutter-apk

if not exist "%KEY_PROPS%" (
    echo [ERROR] key.properties not found: %KEY_PROPS%
    echo Create it from frontend\android\key.properties.example
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in ("%KEY_PROPS%") do (
    set "%%A=%%B"
)

if "%storeFile%"=="" (
    echo [ERROR] storeFile is missing in key.properties
    exit /b 1
)

set KEYSTORE=%~dp0..\frontend\android\%storeFile%

if not exist "%APKSIGNER%" (
    echo [ERROR] apksigner not found at: %APKSIGNER%
    echo Please install Android SDK build-tools 34.0.0
    exit /b 1
)

if not exist "%KEYSTORE%" (
    echo [ERROR] Keystore not found at: %KEYSTORE%
    echo Generate a local keystore and update key.properties
    exit /b 1
)

if not "%1"=="" (
    set APK_FILE=%1
    if not exist "%APK_FILE%" (
        echo [ERROR] APK file not found: %APK_FILE%
        exit /b 1
    )
    echo [SIGNING] %APK_FILE%
    "%APKSIGNER%" sign --ks "%KEYSTORE%" --ks-key-alias "%keyAlias%" --ks-pass pass:%storePassword% --key-pass pass:%keyPassword% --out "%APK_FILE%" "%APK_FILE%"
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
    "%APKSIGNER%" sign --ks "%KEYSTORE%" --ks-key-alias "%keyAlias%" --ks-pass pass:%storePassword% --key-pass pass:%keyPassword% --out "%%f" "%%f"
    if !ERRORLEVEL! equ 0 (
        echo [OK] %%~nxf signed
    ) else (
        echo [FAILED] %%~nxf
    )
)

echo [DONE] All APKs signed
endlocal
