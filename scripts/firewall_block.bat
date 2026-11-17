@echo off
:: Run as Administrator before installing Punto Switcher
echo Blocking Punto Switcher network access...

netsh advfirewall firewall add rule name="Punto - Setup block" dir=out action=block program="%USERPROFILE%\Downloads\PuntoSwitcherSetup.exe" enable=yes
netsh advfirewall firewall add rule name="Punto - punto.exe block" dir=out action=block program="%LOCALAPPDATA%\PuntoSwitcher\punto.exe" enable=yes

echo Done! You can now run the installer.
pause
