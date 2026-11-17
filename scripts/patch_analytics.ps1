# Punto Switcher Analytics Patcher
# Run as Administrator after installation
# Tested on Punto Switcher 4.5.0.583

$puntoPath = "$env:LOCALAPPDATA\PuntoSwitcher"
$puntoExe = "$puntoPath\punto.exe"

# Check file exists
if (-not (Test-Path $puntoExe)) {
    Write-Error "punto.exe not found at $puntoExe"
    exit 1
}

# Stop Punto if running
Get-Process | Where-Object { $_.Name -like "*punto*" -or $_.Name -like "*ps64*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Remove read-only
Set-ItemProperty $puntoExe -Name IsReadOnly -Value $false

# Backup
$backup = "$puntoExe.backup"
if (-not (Test-Path $backup)) {
    Copy-Item $puntoExe $backup
    Write-Host "Backup created: $backup"
}

# Read binary
$bytes = [System.IO.File]::ReadAllBytes($puntoExe)

# VA to file offset
# ImageBase = 0x400000, .text: VA=0x1000, FileOffset=0x400
function VA-ToOffset($va) { return $va - 0x400000 - 0x1000 + 0x400 }

# Patch analytics functions
# XOR EAX, EAX (31 C0) + RET (C3) = return 0 immediately
$patches = @{
    "PingStatThread (0x4464C0)"     = 0x004464C0
    "Update check (0x445FB0)"       = 0x00445FB0
    "Click tracking (0x446D70)"     = 0x00446D70
}

foreach ($name in $patches.Keys) {
    $offset = VA-ToOffset $patches[$name]
    $original = $bytes[$offset..($offset+2)] | ForEach-Object { '{0:X2}' -f $_ }
    $bytes[$offset]   = 0x31  # XOR EAX, EAX
    $bytes[$offset+1] = 0xC0
    $bytes[$offset+2] = 0xC3  # RET
    Write-Host "Patched: $name | was: $($original -join ' ') -> 31 C0 C3"
}

# Write patched binary
[System.IO.File]::WriteAllBytes($puntoExe, $bytes)
Write-Host ""
Write-Host "Done! Analytics functions patched."
Write-Host ""

# Remove updater components
$toRemove = @("$puntoPath\yupdate.exe", "$puntoPath\yupdate.dll", "$puntoPath\Updater")
foreach ($item in $toRemove) {
    if (Test-Path $item) {
        Remove-Item $item -Recurse -Force
        Write-Host "Removed: $item"
    }
}

# Add Windows Defender exclusions
Add-MpPreference -ExclusionPath $puntoPath -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess "punto.exe" -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess "ps64ldr.exe" -ErrorAction SilentlyContinue
Write-Host "Defender exclusions added."

Write-Host ""
Write-Host "All done! Punto Switcher analytics removed."
