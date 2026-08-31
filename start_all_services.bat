@echo off
chcp 65001 >nul
setlocal EnableExtensions

echo =======================================================
echo Starting PaperAgent local services
echo =======================================================

set "EDGE_DIR=%~dp0EDGE"
if "%EDGE_DIR:~-1%"=="\" set "EDGE_DIR=%EDGE_DIR:~0,-1%"
for %%I in ("%EDGE_DIR%\..") do set "ROOT_DIR=%%~fI"
set "FRONTEND_DIR=%EDGE_DIR%\aithesis"
set "CLOUD_DIR=%ROOT_DIR%\CLOUD\src"
set "NGINX_DIR=%ROOT_DIR%\nginx_install\nginx-1.30.1"
set "LOG_DIR=%ROOT_DIR%\logs"
set "PYTHON_ENV=%ROOT_DIR%\.venv\Scripts\pythonw.exe"
set "CONFIG_SCRIPT=%ROOT_DIR%\scripts\configure_project.ps1"
set "OPEA_GATEWAY_URL=http://127.0.0.1:7008"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not exist "%PYTHON_ENV%" (
  echo [ERROR] Python environment is missing: %PYTHON_ENV%
  echo Run deploy.bat first.
  pause
  exit /b 1
)

if not exist "%FRONTEND_DIR%\node_modules" (
  echo [ERROR] Frontend dependencies are missing.
  echo Run deploy.bat first.
  pause
  exit /b 1
)

if not exist "%NGINX_DIR%\nginx.exe" (
  echo [ERROR] Nginx is missing: %NGINX_DIR%\nginx.exe
  pause
  exit /b 1
)

echo [Config] Updating project paths...
powershell -NoProfile -ExecutionPolicy Bypass -File "%CONFIG_SCRIPT%"
if errorlevel 1 (
  echo [ERROR] Project path configuration failed.
  pause
  exit /b 1
)

echo [0/5] Stopping previous local project services...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $ports=@(5000,5001,5173,7007); $portPids=@(); foreach($port in $ports){$portPids += Get-NetTCPConnection -LocalPort $port -State Listen | Select-Object -ExpandProperty OwningProcess}; $root='%ROOT_DIR%'.ToLower(); $patterns=@('main_npu.py','CLOUD\\src\\app.py','aithesis','npm run dev:ip','nginx'); $currentPid=$PID; $procs=Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $currentPid } | Where-Object { $cmd=($_.CommandLine+'').ToLower(); ($portPids -contains $_.ProcessId) -or (($cmd -like ('*'+$root+'*')) -and ($patterns | Where-Object { $cmd -like ('*'+$_.ToLower()+'*') })) }; $ids=$procs | Select-Object -ExpandProperty ProcessId -Unique; foreach($id in $ids){Write-Host ('  stopping PID tree ' + $id); & taskkill.exe /T /F /PID $id | Out-Null}; Start-Sleep -Seconds 2; foreach($port in $ports){$left=Get-NetTCPConnection -LocalPort $port -State Listen; if($left){Write-Host ('  warning: port ' + $port + ' is still in use by PID ' + (($left | Select-Object -ExpandProperty OwningProcess -Unique) -join ','))}}"

echo [1/5] Creating hidden launcher...
(
  echo Dim WShell
  echo Set WShell = CreateObject("WScript.Shell"^)
  echo WShell.Run WScript.Arguments(0^), 0, False
) > "%EDGE_DIR%\run_silent.vbs"

echo [2/5] Starting EDGE backend on port 5001...
cd /d "%EDGE_DIR%"
wscript //nologo "%EDGE_DIR%\run_silent.vbs" "cmd /d /c ""%PYTHON_ENV%"" -u main_npu.py > %LOG_DIR%\edge_backend.log 2>&1"

echo [3/5] Starting EDGE frontend on port 5173...
cd /d "%FRONTEND_DIR%"
set NO_COLOR=1
wscript //nologo "%EDGE_DIR%\run_silent.vbs" "cmd /d /c npm run dev:ip > %LOG_DIR%\edge_frontend.log 2> %LOG_DIR%\edge_frontend_error.log"

echo [4/5] Starting cloud UI on port 7007...
cd /d "%CLOUD_DIR%"
wscript //nologo "%EDGE_DIR%\run_silent.vbs" "cmd /d /c set OPEA_GATEWAY_URL=%OPEA_GATEWAY_URL%&& set GRADIO_ROOT_PATH=/cloud&& ""%PYTHON_ENV%"" -u app.py --server-name 0.0.0.0 --server-port 7007 > %LOG_DIR%\cloud_backend.log 2>&1"

echo [5/5] Starting nginx on port 5000...
cd /d "%NGINX_DIR%"
start "" "%NGINX_DIR%\nginx.exe"

echo.
echo =======================================================
echo Local services started. All logs in: %LOG_DIR%\
echo   EDGE backend:         edge_backend.log
echo   EDGE frontend:        edge_frontend.log
echo   EDGE frontend error:  edge_frontend_error.log
echo   Cloud UI:             cloud_backend.log
echo   Nginx:                %NGINX_DIR%\logs\
echo.
echo OPEA gateway target: %OPEA_GATEWAY_URL%
echo If OPEA is unavailable, the cloud UI falls back to the compatibility path.
echo Access URL: http://localhost:5000/
echo =======================================================

endlocal
