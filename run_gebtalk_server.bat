@echo off
REM ===================================================
REM GEBTALK Backend, Web App & Tunnel Background Runner
REM ===================================================
cd /d "D:\EB GLOBAL APP\gebtalk_backend"

REM 1. Start Python API Backend on port 5000
tasklist /FI "IMAGENAME eq python.exe" 2>NUL | find /I /N "python.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" app.py
)

timeout /t 2 /nobreak >nul

REM 2. Start GEBTALK Web App Server on port 8080
cd /d "D:\EB GLOBAL APP"
start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" web_server.py

timeout /t 2 /nobreak >nul

REM 3. Start Cloudflare Tunnel for Mobile App connectivity
tasklist /FI "IMAGENAME eq cloudflared.exe" 2>NUL | find /I /N "cloudflared.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B cloudflared tunnel --url http://127.0.0.1:5000 --logfile "D:\EB GLOBAL APP\tunnel.log"
)
