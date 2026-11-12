@echo off
setlocal
set "SCANNER=%~dp0BA2_Content_Scanner.ps1"
if not exist "%SCANNER%" (
    echo.
    echo ERROR: BA2_Content_Scanner.ps1 was not found.
    echo Keep BA2_Content_Scanner.bat and BA2_Content_Scanner.ps1
    echo in the SAME extracted folder.
    echo.
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCANNER%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo Scanner exited with code %RC%. Check the message above.
    pause
)
endlocal & exit /b %RC%
