@echo off
:: Punto Switcher - block outbound network access via Windows Firewall.
::
:: Usage (run as Administrator):
::   firewall_block.bat [path\to\PuntoSwitcherSetup.exe]   add rules (run BEFORE installing)
::   firewall_block.bat remove                             delete all rules added by this script

net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: run this script as Administrator.
    pause
    exit /b 1
)

if /i "%~1"=="remove" (
    echo Removing Punto Switcher firewall rules...
    netsh advfirewall firewall delete rule name="Punto - Setup block" >nul 2>&1
    netsh advfirewall firewall delete rule name="Punto - punto.exe block" >nul 2>&1
    netsh advfirewall firewall delete rule name="Punto - ps64ldr block" >nul 2>&1
    echo Done.
    pause
    exit /b 0
)

set "SETUP=%~1"
if "%SETUP%"=="" set "SETUP=%USERPROFILE%\Downloads\PuntoSwitcherSetup.exe"
set "PUNTO_DIR=%LOCALAPPDATA%\PuntoSwitcher"

echo Blocking Punto Switcher network access...

:: delete old rules first so re-running does not create duplicates
netsh advfirewall firewall delete rule name="Punto - Setup block" >nul 2>&1
netsh advfirewall firewall delete rule name="Punto - punto.exe block" >nul 2>&1
netsh advfirewall firewall delete rule name="Punto - ps64ldr block" >nul 2>&1

netsh advfirewall firewall add rule name="Punto - Setup block" dir=out action=block program="%SETUP%" enable=yes
netsh advfirewall firewall add rule name="Punto - punto.exe block" dir=out action=block program="%PUNTO_DIR%\punto.exe" enable=yes
netsh advfirewall firewall add rule name="Punto - ps64ldr block" dir=out action=block program="%PUNTO_DIR%\ps64ldr.exe" enable=yes

echo.
echo Installer path : %SETUP%
echo Punto directory: %PUNTO_DIR%
echo Done! You can now run the installer.
pause
