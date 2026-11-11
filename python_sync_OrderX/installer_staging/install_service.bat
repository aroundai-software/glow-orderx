@echo off
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if not %errorlevel%==0 (
  echo Right-click install_service.bat and choose "Run as administrator".
  pause
  exit /b 1
)

if not exist "%~dp0TallySync.exe" (
  echo TallySync.exe is missing from this folder.
  pause
  exit /b 1
)

if not exist "%~dp0.env" (
  echo .env is missing from this folder. The service reads settings from that file.
  pause
  exit /b 1
)

echo Installing TallySync service...
"%~dp0myserviceinstaller.exe" install
if not %errorlevel%==0 (
  echo Install failed. If it is already installed, run uninstall_service.bat first.
  pause
  exit /b 1
)

echo Starting TallySync service...
"%~dp0myserviceinstaller.exe" start
if not %errorlevel%==0 (
  echo Service installed, but start failed. Check myserviceinstaller.wrapper.log in this folder.
  pause
  exit /b 1
)

echo.
echo Done. TallySync is running in the background and will start with Windows.
echo Edit SYNC_INTERVAL_SECONDS in .env and save. The running service picks it up.
echo Do not move this folder after installing.
pause
