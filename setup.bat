@echo off
rem Windows: double-click to open the agent-token-lab setup menu.
rem It runs setup.ps1 with ExecutionPolicy Bypass for this process only.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
