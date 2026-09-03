@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "ARGS=%*"
set "SKIP_MODELS=0"
set "NON_INTERACTIVE=0"

echo =======================================================
echo PaperAgent Competition Edition - One Click Deployment
echo =======================================================

echo(%ARGS% | findstr /I /C:"-OPEAOnly" >nul && set "SKIP_MODELS=1"
echo(%ARGS% | findstr /I /C:"-SkipModelDownload" >nul && set "SKIP_MODELS=1"
echo(%ARGS% | findstr /I /C:"-NonInteractive" >nul && set "NON_INTERACTIVE=1"

if "%SKIP_MODELS%"=="0" (
  echo.
  echo [Model preparation] ModelScope is the default model source.
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\download_models.ps1" -ProjectRoot "%ROOT_DIR%"
  if errorlevel 1 (
    echo.
    echo [ERROR] Model preparation failed.
    if "%NON_INTERACTIVE%"=="0" pause
    exit /b 1
  )
) else (
  echo.
  echo [Model preparation] Skipped by deployment mode/argument.
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\deploy.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Deployment failed. Review the message above.
  if "%NON_INTERACTIVE%"=="0" pause
  exit /b %EXIT_CODE%
)

echo.
echo Deployment completed successfully.
if "%NON_INTERACTIVE%"=="0" pause
endlocal
