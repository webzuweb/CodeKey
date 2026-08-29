@echo off
setlocal
cd /d "%~dp0\.."
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter SDK is not available in PATH.
  exit /b 2
)
if not exist "android\app\src\main\AndroidManifest.xml" (
  python tool\bootstrap_platforms.py
  if errorlevel 1 exit /b %errorlevel%
)
flutter pub get
if errorlevel 1 exit /b %errorlevel%
flutter analyze
if errorlevel 1 exit /b %errorlevel%
flutter test
if errorlevel 1 exit /b %errorlevel%
flutter build apk --release %*
if errorlevel 1 exit /b %errorlevel%
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
endlocal
