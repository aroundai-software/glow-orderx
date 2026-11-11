@echo off
cd /d "%~dp0"

echo ========================================================
echo   OrderX TallySync - Manual Sync Test Console
echo ========================================================
echo.
echo Running one-time sync cycle to test connection and log output...
echo Press Ctrl+C at any time to cancel.
echo.

"%~dp0TallySync.exe" --once

echo.
echo ========================================================
echo Sync process finished.
echo ========================================================
pause
