@echo off
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if not %errorlevel%==0 (
  echo Right-click uninstall_service.bat and choose "Run as administrator".
  pause
  exit /b 1
)

echo Stopping TallySync service...
"%~dp0myserviceinstaller.exe" stop
echo Uninstalling TallySync service...
"%~dp0myserviceinstaller.exe" uninstall
if not %errorlevel%==0 (
  echo Uninstall failed. See myserviceinstaller.wrapper.log in this folder.
  pause
  exit /b 1
)

echo Done. Service removed.
pause
