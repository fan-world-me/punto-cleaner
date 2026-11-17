#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Disables Punto Switcher analytics: patches punto.exe and removes the Yandex updater.

.DESCRIPTION
  Target: Punto Switcher 4.5.0.583 (x86). Safe by design:
    - original bytes are verified at every offset, nothing is written on mismatch
    - VA -> file offset is computed from the PE section table, not hardcoded
    - the calling convention is not assumed: the script finds the function's own
      ret / ret N and builds the stub to match (xor eax,eax + ret [N])
    - all patches are validated first, the file is written only if every one passes
    - a .backup of the original is kept (see restore_backup.ps1)

.PARAMETER DryRun
  Show what would be patched/removed, change nothing.

.PARAMETER AddDefenderExclusion
  Add a Defender exclusion for the punto.exe process. Use only if Defender removes
  the patched file (the Yandex signature is broken by patching).
#>
[CmdletBinding()]
param(
    [string]$PuntoPath = (Join-Path $env:LOCALAPPDATA 'PuntoSwitcher'),
    [switch]$DryRun,
    [switch]$AddDefenderExclusion
)

$ErrorActionPreference = 'Stop'
$puntoExe = Join-Path $PuntoPath 'punto.exe'
$backup   = "$puntoExe.backup"

# Functions to neutralise (virtual addresses, Punto Switcher 4.5.0.583)
$targets = @(
    @{ Name = 'Update check';     VA = 0x00445FB0 },
    @{ Name = 'Stat ping thread'; VA = 0x004464C0 },
    @{ Name = 'Click tracking';   VA = 0x00446D70 }
)

function Get-PeInfo([byte[]]$b) {
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ([BitConverter]::ToUInt32($b, $pe) -ne 0x00004550) { throw 'Not a PE file.' }
    $nSec    = [BitConverter]::ToUInt16($b, $pe + 6)
    $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
    $opt     = $pe + 24
    if ([BitConverter]::ToUInt16($b, $opt) -ne 0x10B) { throw 'Not a 32-bit (PE32) executable.' }
    $info = @{ ImageBase = [int64][BitConverter]::ToUInt32($b, $opt + 28); Sections = @() }
    $sec = $opt + $optSize
    for ($i = 0; $i -lt $nSec; $i++) {
        $o = $sec + 40 * $i
        $info.Sections += @{
            VSize   = [int64][BitConverter]::ToUInt32($b, $o + 8)
            VA      = [int64][BitConverter]::ToUInt32($b, $o + 12)
            RawSize = [int64][BitConverter]::ToUInt32($b, $o + 16)
            RawPtr  = [int64][BitConverter]::ToUInt32($b, $o + 20)
        }
    }
    return $info
}

function ConvertTo-FileOffset($pe, [int64]$va) {
    $rva = $va - $pe.ImageBase
    foreach ($s in $pe.Sections) {
        $size = [Math]::Max($s.VSize, $s.RawSize)
        if ($rva -ge $s.VA -and $rva -lt ($s.VA + $size)) {
            return [int]($rva - $s.VA + $s.RawPtr)
        }
    }
    throw ('VA 0x{0:X} is not inside any section.' -f $va)
}

# Scan forward from the function entry for the first epilogue: (pop ebp | leave) + (ret | ret N).
# All return paths of one function share the same N. Returns N, or $null if not found.
function Find-FunctionReturn([byte[]]$b, [int]$start, [int]$maxScan = 0x4000) {
    $end = [Math]::Min($b.Length - 4, $start + $maxScan)
    for ($i = $start + 3; $i -lt $end; $i++) {
        if ($b[$i] -eq 0x5D -or $b[$i] -eq 0xC9) {
            if ($b[$i + 1] -eq 0xC3) { return 0 }
            if ($b[$i + 1] -eq 0xC2) { return [int][BitConverter]::ToUInt16($b, $i + 2) }
        }
    }
    return $null
}

if (-not (Test-Path $puntoExe)) { throw "punto.exe not found at $puntoExe" }

$ver = (Get-Item $puntoExe).VersionInfo.FileVersion
Write-Host "punto.exe version: $ver"
if ($ver -notlike '4.5.0.583*') {
    Write-Warning 'Expected 4.5.0.583. Offsets may not match; the byte check below decides whether it is safe.'
}

$bytes = [IO.File]::ReadAllBytes($puntoExe)
$pe    = Get-PeInfo $bytes

# ---- Plan (validate everything before touching the file) ----
$plan = @()
foreach ($t in $targets) {
    $off = ConvertTo-FileOffset $pe $t.VA
    $cur = $bytes[$off..($off + 2)]

    if ($cur[0] -eq 0x31 -and $cur[1] -eq 0xC0) {
        $plan += [pscustomobject]@{ Name = $t.Name; VA = $t.VA; Offset = $off; N = $null; Patch = $null; State = 'already patched' }
        continue
    }
    if (-not ($cur[0] -eq 0x55 -and $cur[1] -eq 0x8B -and $cur[2] -eq 0xEC)) {
        throw ('{0}: expected 55 8B EC at file offset 0x{1:X}, found {2}. Wrong version? Nothing was changed.' -f `
            $t.Name, $off, (($cur | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    }
    $n = Find-FunctionReturn $bytes $off
    if ($null -eq $n) { throw "$($t.Name): could not locate the function's ret. Nothing was changed." }
    if (($n % 4) -ne 0 -or $n -gt 64) { throw "$($t.Name): suspicious ret $n. Nothing was changed." }

    if ($n -eq 0) {
        $patch = [byte[]](0x31, 0xC0, 0xC3)
    } else {
        $patch = [byte[]](0x31, 0xC0, 0xC2, ($n -band 0xFF), (($n -shr 8) -band 0xFF))
    }
    $plan += [pscustomobject]@{ Name = $t.Name; VA = $t.VA; Offset = $off; N = $n; Patch = $patch; State = 'pending' }
}

Write-Host ''
foreach ($p in $plan) {
    if ($p.State -eq 'pending') {
        $stub = ($p.Patch | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Host ('{0,-17} VA 0x{1:X8}  offset 0x{2:X}  ret {3,-2} ->  {4}' -f $p.Name, $p.VA, $p.Offset, $p.N, $stub)
    } else {
        Write-Host ('{0,-17} VA 0x{1:X8}  already patched' -f $p.Name, $p.VA)
    }
}

$toRemove = @('yupdate.exe', 'yupdate.dll', 'Updater') | ForEach-Object { Join-Path $PuntoPath $_ }

if ($DryRun) {
    Write-Host ''
    Write-Host 'DryRun: nothing was changed. Would remove (if present):'
    $toRemove | ForEach-Object { Write-Host "  $_" }
    return
}

# ---- Apply ----
Get-Process -Name punto, ps64ldr -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$pending = @($plan | Where-Object { $_.State -eq 'pending' })
if ($pending.Count -gt 0) {
    Set-ItemProperty $puntoExe -Name IsReadOnly -Value $false
    if (-not (Test-Path $backup)) {
        Copy-Item $puntoExe $backup
        Write-Host "Backup created: $backup"
    }
    foreach ($p in $pending) {
        for ($k = 0; $k -lt $p.Patch.Length; $k++) { $bytes[$p.Offset + $k] = $p.Patch[$k] }
    }
    [IO.File]::WriteAllBytes($puntoExe, $bytes)

    # verify what actually landed on disk
    $check = [IO.File]::ReadAllBytes($puntoExe)
    foreach ($p in $pending) {
        for ($k = 0; $k -lt $p.Patch.Length; $k++) {
            if ($check[$p.Offset + $k] -ne $p.Patch[$k]) { throw "Verification failed for $($p.Name). Run restore_backup.ps1." }
        }
    }
    Write-Host 'Patches written and verified.'
} else {
    Write-Host 'punto.exe is already patched.'
}

foreach ($item in $toRemove) {
    if (Test-Path $item) {
        Remove-Item $item -Recurse -Force
        Write-Host "Removed: $item"
    }
}

if ($AddDefenderExclusion) {
    Add-MpPreference -ExclusionProcess 'punto.exe'
    Write-Warning 'Defender will not scan the punto.exe process. Remove with: Remove-MpPreference -ExclusionProcess punto.exe'
}

Write-Host ''
Write-Host 'Done. Static patch only - verify with Procmon/Wireshark that no Yandex traffic remains.'
