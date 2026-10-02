@echo off
rem Builds Mudhkir and installs it on the Android phone connected by USB.
rem Double-click this file. The first build takes 5-10 minutes.

cd /d "%~dp0\..\.."

where flutter >nul 2>nul
if errorlevel 1 (
  if exist "C:\src\flutter\bin\flutter.bat" (
    set "PATH=C:\src\flutter\bin;%PATH%"
  ) else (
    echo Flutter was not found. Run tools\windows\setup.ps1 first.
    pause
    exit /b 1
  )
)

if not exist env.json (
  echo {}> env.json
  echo env.json was missing: running offline only. See docs\WINDOWS_SETUP.md to add the Supabase key.
)

echo.
echo Connected devices:
call flutter devices
echo.
echo Building and installing... keep the phone unlocked and tap "Allow" if it asks.
call flutter run --dart-define-from-file=env.json
pause
