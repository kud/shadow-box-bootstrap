@echo off
rem Entry point: `shadow install`, `shadow update`, `shadow status`.
rem Prefers PowerShell 7 and falls back to Windows PowerShell.
where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\shadow.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\shadow.ps1" %*
)
exit /b %errorlevel%
