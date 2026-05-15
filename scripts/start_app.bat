@echo off
setlocal EnableExtensions
title IDX Stock ML Launcher

REM Folder scripts\ -> project root stock_predictor\
set "ROOT=%~dp0.."
set "BACKEND=%ROOT%\backend"
set "FLUTTER=%ROOT%\flutter_app"
set "PYTHON=%BACKEND%\.venv\Scripts\python.exe"

if not exist "%PYTHON%" (
    echo [ERROR] Virtual environment tidak ditemukan.
    echo Jalankan dulu: scripts\setup_backend.bat
    echo.
    pause
    exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter tidak ada di PATH. Pasang Flutter SDK lalu buka terminal baru.
    pause
    exit /b 1
)

echo Memulai backend API di port 8000 ...
start "IDX Stock - Backend API" cmd /k "cd /d "%BACKEND%" && "%PYTHON%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000"

echo Menunggu backend siap (8 detik) ...
timeout /t 8 /nobreak >nul

echo Memulai Flutter Web (Chrome) ...
start "IDX Stock - Flutter Chrome" cmd /k "cd /d "%FLUTTER%" && flutter run -d chrome"

echo.
echo Selesai. Dua jendela CMD terbuka:
echo   1. Backend API  - http://127.0.0.1:8000/docs
echo   2. Flutter      - Chrome akan terbuka otomatis
echo.
echo Tutup jendela CMD untuk menghentikan proses.
timeout /t 5 >nul
exit /b 0
