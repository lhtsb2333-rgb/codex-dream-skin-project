@echo off
rem Content notice: this launcher is AI-generated/AI-edited technical text,
rem not a personal opinion or political/social statement.
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%windows\CodexSkinManagerPortable.ps1" %*
if errorlevel 1 (
  echo.
  echo Codex Dream Skin could not start. Review the message above.
  pause
)
