@echo off
setlocal EnableExtensions
title Publish IDX Stock ML ke GitHub

REM scripts\ -> stock_predictor\
set "ROOT=%~dp0.."
cd /d "%ROOT%"

where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git tidak ada di PATH.
    echo Instal: https://git-scm.com/download/win
    pause
    exit /b 1
)

where gh >nul 2>&1
if errorlevel 1 (
    echo [ERROR] GitHub CLI ^(gh^) tidak ada di PATH.
    echo Instal: https://cli.github.com/
    echo Lalu login: gh auth login
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Publish ke GitHub - Memedsugianto
echo ============================================
echo  Folder: %CD%
echo.
echo  Sebelum lanjut, pastikan sudah:
echo    gh auth login
echo.
echo  Edit nama repo di: scripts\github.config.ps1
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_to_github.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
if not "%EC%"=="0" (
    echo [GAGAL] Exit code %EC%
) else (
    echo [OK] Selesai.
)
pause
exit /b %EC%
