# Punto Switcher — Privacy Cleanup

A research project documenting how to remove analytics, telemetry, and Russian server connections from Punto Switcher 4.5.0.583.

> **Why?** Punto Switcher is developed by Yandex (Russia). For users in Ukraine and other countries, sending usage data to Russian servers is unacceptable. This project provides tools to block all outgoing connections and patch analytics functions directly in the binary.

---

## What was found

Using [Ghidra](https://ghidra-sre.org/) with [GhidraMCP](https://github.com/13bm/GhidraMCP), the following was identified inside `punto.exe`:

### Analytics functions (decompiled)

| Function | Address | Description |
|---|---|---|
| `CYaUpdater::PingStatThread` | `0x004464C0` | Background thread that sends usage statistics to Yandex |
| `CYaUpdater::RegApplicationAndCheckUpdate` | `0x00445FB0` | Registers app and checks for updates at `download.yandex.ru` |
| `FUN_00446D70` | `0x00446D70` | Click tracking via `yandex.ru/clck/click` |

### Network addresses found in binary

- `http://soft.export.yandex.ru/status.xml` — usage statistics
- `http://download.yandex.ru/punto/version.rss` — update checks  
- `https://yandex.ru/clck/click/dtype=stred/pid=156/cid=73020/path=` — click tracking
- `https://share.yandex.net/go.xml` — sharing
- `yandexuid` cookie tracking

### Key strings found

```
"CYaUpdater::PingStatThread"
"[%lx] %s(%d) +++ Sending statistics using YaUpdater"
"Punto Switcher Stat"
"yandex.statistics.ui"
```

---

## What this project does

1. **Patches** analytics functions in `punto.exe` to immediately return without executing
2. **Blocks** all outgoing connections via Windows Firewall
3. **Removes** `yupdate.exe` and `yupdate.dll` (the updater/stats components)

Punto Switcher continues to work normally as a keyboard layout switcher.

---

## Usage

### Step 1 — Block network access (before installation)

Run `scripts/firewall_block.bat` as Administrator **before** running the installer.

### Step 2 — Install Punto Switcher

Run the official installer normally.

### Step 3 — Patch analytics

Run `scripts/patch_analytics.ps1` as Administrator after installation.

### Step 4 — Add Windows Defender exclusions

```powershell
Add-MpPreference -ExclusionPath "C:\Users\$env:USERNAME\AppData\Local\PuntoSwitcher"
Add-MpPreference -ExclusionProcess "punto.exe"
Add-MpPreference -ExclusionProcess "ps64ldr.exe"
```

---

## Technical details

### Binary patches applied to punto.exe

Each function is patched to `XOR EAX, EAX` + `RET` (`31 C0 C3`), making it return 0 immediately.

| Virtual Address | File Offset | Original bytes | Patched bytes | Function |
|---|---|---|---|---|
| `0x00445FB0` | `0x453B0` | `55 8B EC` | `31 C0 C3` | Update check |
| `0x004464C0` | `0x458C0` | `55 8B EC` | `31 C0 C3` | Stat ping thread |
| `0x00446D70` | `0x46170` | `55 8B EC` | `31 C0 C3` | Click tracking |

> Note: `FUN_00445BA0` (yupdate.dll loader) is **not** patched — it is called during initialization and patching it causes a crash. Instead, `yupdate.dll` and `yupdate.exe` are physically deleted, so the loader fails gracefully on its own.

### Files removed

- `yupdate.exe` — Yandex updater executable
- `yupdate.dll` — Yandex updater library with `DLLUsageReport`, `DLLOnApplicationStartup` exports

### Firewall rules added

```
Punto - Setup block     → outbound BLOCK → PuntoSwitcherSetup.exe
Punto - punto.exe block → outbound BLOCK → punto.exe
```

---

## Disclaimer

This project is for **research and educational purposes** only.  
Punto Switcher is proprietary software owned by Yandex LLC.  
This repository contains **no binary files** from Punto Switcher.  
All patches are described as byte offsets for research documentation.

---

## License

Scripts and documentation in this repository are released under [MIT License](LICENSE).  
Punto Switcher binaries remain property of Yandex LLC.
