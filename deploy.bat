@echo off
chcp 65001 >nul
setlocal

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

echo =======================================================
echo PaperAgent Competition Edition - One Click Deployment
echo =======================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\deploy.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Deployment failed. Review the message above.
  pause
  exit /b %EXIT_CODE%
)

echo.
echo Deployment completed successfully.
pause
endlocal
