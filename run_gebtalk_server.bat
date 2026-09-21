@echo off
REM ===================================================
REM GEBTALK Permanent Server Runner (ngrok static domain)
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

REM 3. Start GEBTALK Web App Server on port 8080
cd /d "D:\EB GLOBAL APP"
start "" /B "D:\EB GLOBAL APP\gebtalk_backend\.venv\Scripts\python.exe" web_server.py

timeout /t 2 /nobreak >nul

REM 4. Start ngrok with PERMANENT static domain (never changes!)
tasklist /FI "IMAGENAME eq ngrok.exe" 2>NUL | find /I /N "ngrok.exe">NUL
if "%ERRORLEVEL%"=="1" (
    start "" /B "C:\Users\pravi\AppData\AndroidCLI\ngrok.exe" http --url=sharper-prevent-psychic.ngrok-free.dev 5000
)
