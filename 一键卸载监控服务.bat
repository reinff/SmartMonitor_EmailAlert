@echo off
:: Admin Check
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    goto UACPrompt
) else ( goto gotAdmin )
:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin_un.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin_un.vbs"
    "%temp%\getadmin_un.vbs"
    exit /B
:gotAdmin
    if exist "%temp%\getadmin_un.vbs" ( del "%temp%\getadmin_un.vbs" )
    pushd "%~dp0"

echo ======================================================
echo    SmartMonitor - Service Uninstallation
echo ======================================================
echo.
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-MonitorService.ps1"
echo.
echo ======================================================
echo Done. Press any key to exit...
pause >nul