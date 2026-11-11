@echo off
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if not %errorlevel%==0 (
  echo Administrator privileges required.
  echo Right-click restart_service.bat and choose "Run as administrator".
  pause
  exit /b 1
)

echo ========================================================
echo   Restarting OrderX TallySync Service...
echo ========================================================
echo.

"%~dp0myserviceinstaller.exe" stop
timeout /t 2 /nobreak >nul
"%~dp0myserviceinstaller.exe" start

if %errorlevel%==0 (
  echo.
  echo [SUCCESS] OrderX TallySync service restarted successfully!
) else (
  echo.
  echo [ERROR] Failed to restart service. Check myserviceinstaller.wrapper.log.
)

echo.
pause
