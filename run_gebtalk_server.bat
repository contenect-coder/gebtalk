@echo off
REM ===================================================
REM GEBTALK Server & Tunnel Background Runner
REM ===================================================
cd /d "D:\EB GLOBAL APP\gebtalk_backend"

REM Check if python backend is already running
tasklist /FI "IMAGENAME eq python.exe" 2>NUL | find /I /N "python.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" app.py
)

timeout /t 3 /nobreak >nul

REM Check if cloudflared is already running
tasklist /FI "IMAGENAME eq cloudflared.exe" 2>NUL | find /I /N "cloudflared.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B cloudflared tunnel --url http://127.0.0.1:5000 --logfile "D:\EB GLOBAL APP\tunnel.log"
)
