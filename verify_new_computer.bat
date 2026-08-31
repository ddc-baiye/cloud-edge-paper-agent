@echo off
chcp 65001 >nul
setlocal

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\configure_project.ps1" -ProjectRoot "%ROOT_DIR%"
if errorlevel 1 goto :failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\verify_environment.ps1" -ProjectRoot "%ROOT_DIR%"
if errorlevel 1 goto :failed

pause
exit /b 0

:failed
echo.
echo Verification failed.
pause
exit /b 1
