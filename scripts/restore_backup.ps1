#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Restores the original punto.exe from punto.exe.backup (created by patch_analytics.ps1).
#>
[CmdletBinding()]
param(
    [string]$PuntoPath = (Join-Path $env:LOCALAPPDATA 'PuntoSwitcher')
)

$ErrorActionPreference = 'Stop'
$exe    = Join-Path $PuntoPath 'punto.exe'
$backup = "$exe.backup"

if (-not (Test-Path $backup)) { throw "No backup found at $backup" }

Get-Process -Name punto, ps64ldr -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Set-ItemProperty $exe -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
Copy-Item $backup $exe -Force
Remove-MpPreference -ExclusionProcess 'punto.exe' -ErrorAction SilentlyContinue

Write-Host "Restored: $exe"
Write-Host 'yupdate.exe / yupdate.dll are NOT restored - reinstall Punto Switcher to get them back.'
Write-Host 'To drop the firewall rules: scripts\firewall_block.bat remove'
