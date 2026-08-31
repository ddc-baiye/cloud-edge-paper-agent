@echo off
chcp 65001 >nul
setlocal

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

echo ========================================
echo  PaperAgent Deployment Verification
echo ========================================

echo.
echo [Edge] Configuring project paths...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\configure_project.ps1" -ProjectRoot "%ROOT_DIR%"
if errorlevel 1 goto :failed

echo.
echo [Edge] Verifying local runtime...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\verify_environment.ps1" -ProjectRoot "%ROOT_DIR%"
if errorlevel 1 goto :failed

if exist "%ROOT_DIR%\CLOUD\opea\.env" (
  echo.
  echo [OPEA Cloud] Verifying Docker services and topology...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\verify_opea.ps1" -ProjectRoot "%ROOT_DIR%"
  if errorlevel 1 goto :failed
) else (
  echo.
  echo [OPEA Cloud] Not configured. Skipping OPEA verification.
  echo              Run deploy.bat -OPEAOnly after Docker and LLM settings are ready.
)

echo.
echo ========================================
echo Verification passed.
echo ========================================
pause
exit /b 0

:failed
echo.
echo Verification failed.
pause
exit /b 1
