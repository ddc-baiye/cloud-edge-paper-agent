@echo off
chcp 65001 >nul
setlocal

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

echo =======================================================
echo Paperagent new-computer setup
echo =======================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\setup_environment.ps1" -ProjectRoot "%ROOT_DIR%"
if errorlevel 1 (
  echo.
  echo Setup failed. Review the error message above.
  pause
  exit /b 1
)

echo.
echo Setup completed successfully.
pause
endlocal
