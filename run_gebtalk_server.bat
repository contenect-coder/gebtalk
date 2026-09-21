@echo off
REM ===================================================
REM GEBTALK Complete Permanent Server Runner
REM ===================================================

REM 1. Update DuckDNS Domain IP automatically
curl.exe -s "https://www.duckdns.org/update?domains=gebtalk-app&token=e4667104-4414-4dac-8f15-0b77f2811f9f&ip=" >nul 2>&1

REM 2. Start Python API Backend on port 5000 (if not running)
cd /d "D:\EB GLOBAL APP\gebtalk_backend"
tasklist /FI "IMAGENAME eq python.exe" 2>NUL | find /I /N "python.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" app.py
)

timeout /t 2 /nobreak >nul

REM 3. Start GEBTALK Web App Server on port 8080 (if not running)
cd /d "D:\EB GLOBAL APP"
start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" web_server.py

timeout /t 2 /nobreak >nul

REM 4. Start Cloudflare Tunnel for Mobile App connectivity (if not running)
tasklist /FI "IMAGENAME eq cloudflared.exe" 2>NUL | find /I /N "cloudflared.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B cloudflared tunnel --url http://127.0.0.1:5000 --logfile "D:\EB GLOBAL APP\tunnel.log"
)
