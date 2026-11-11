@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo   OrderX TallySync - One-Click Installer Builder
echo ========================================================
echo.

echo [1/3] Compiling Python code into executable with PyInstaller...
python -m PyInstaller TallySync.spec --noconfirm
if not %errorlevel%==0 (
  echo [ERROR] PyInstaller build failed.
  pause
  exit /b 1
)

echo.
echo [2/3] Updating installer staging directory...
if not exist "installer_staging" mkdir "installer_staging"
copy /y "dist\TallySync\TallySync.exe" "installer_staging\" >nul
xcopy /e /i /y "dist\TallySync\_internal" "installer_staging\_internal" >nul
if not exist "installer_staging\.env" copy /y ".env" "installer_staging\" >nul

echo.
echo [3/3] Compiling Inno Setup Windows Installer...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "OrderX_TallySync_Setup.iss"
if not %errorlevel%==0 (
  echo [ERROR] Inno Setup compilation failed.
  pause
  exit /b 1
)

echo.
echo ========================================================
echo [SUCCESS] Installer generated successfully!
echo Location: installer_output\OrderX_TallySync_Setup.exe
echo ========================================================
echo.
pause
