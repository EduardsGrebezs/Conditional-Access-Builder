@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7 (pwsh.exe) was not found in PATH.
  echo Install PowerShell 7, then reopen the command prompt.
  pause
  exit /b 1
)

REM Public source build: honor the current Windows PowerShell execution policy.
REM Review the source and its origin before using Unblock-File on downloaded scripts.
pwsh.exe -NoProfile -STA -File "%~dp0Start-EntraCABuilder.ps1"
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo GUI process exited with code %EXITCODE%.
  echo Check the PowerShell error above and README.md for trusted-source setup.
  echo For policy restrictions run: pwsh.exe -NoProfile -Command "Get-ExecutionPolicy -List"
  echo Do not override execution policy enforced by your organization.
  pause
)
exit /b %EXITCODE%
