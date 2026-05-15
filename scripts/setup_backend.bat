@echo off
setlocal EnableExtensions
title IDX Stock ML - Setup Backend

set "ROOT=%~dp0.."
set "BACKEND=%ROOT%\backend"
cd /d "%BACKEND%"

echo === Setup backend (sekali saja) ===
echo Folder: %BACKEND%
echo.

where py >nul 2>&1
if errorlevel 1 (
    echo [ERROR] py launcher tidak ditemukan. Instal Python 3.12 dari python.org
    pause
    exit /b 1
)

py -3.12 -m venv .venv 2>nul
if not exist ".venv\Scripts\python.exe" (
    echo Mencoba python default ...
    python -m venv .venv
)

if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] Gagal membuat .venv
    pause
    exit /b 1
)

echo Menginstall dependency (bisa beberapa menit) ...
".venv\Scripts\python.exe" -m pip install --upgrade pip
".venv\Scripts\python.exe" -m pip install -r requirements.txt

if errorlevel 1 (
    echo [ERROR] pip install gagal. Lihat pesan di atas.
    pause
    exit /b 1
)

echo.
echo [OK] Backend siap. Jalankan start_app.bat atau shortcut desktop.
pause
exit /b 0
