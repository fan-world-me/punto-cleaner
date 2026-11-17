# Punto Switcher — Privacy Cleanup

A research project documenting what Punto Switcher 4.5.0.583 sends to Yandex servers, and tools to block or patch that behavior.

> Punto Switcher is developed by Yandex (Russia). The binary contains functions that send usage statistics, click tracking data, and a unique user identifier (`yandexuid`) to Yandex servers. This project documents those findings and provides tools to disable them.

---

## Most interesting finding — Yandex Browser cookie harvesting

`punto.exe` reads the `yandexuid` tracking cookie directly from Yandex Browser's profile:

```
%APPDATA%\Yandex\YandexBrowser\User Data\Local State
Yandex\clids-yabrowser.xml
```

This identifier is then included in click tracking requests to `yandex.ru/clck/click`. Punto Switcher links your keyboard layout switching activity to your Yandex Browser identity.

---

## What was found

Using [Ghidra](https://ghidra-sre.org/) with [GhidraMCP](https://github.com/13bm/GhidraMCP) (AI-assisted reverse engineering via MCP), the following was identified inside `punto.exe`:

### Analytics functions (decompiled)

| Function | Address | Description |
|---|---|---|
| `CYaUpdater::PingStatThread` | `0x004464C0` | Background thread that sends usage statistics to Yandex via `yupdate.dll` COM object |
| `CYaUpdater::RegApplicationAndCheckUpdate` | `0x00445FB0` | Registers app and checks for updates at `download.yandex.ru` |
| `FUN_00446D70` | `0x00446D70` | Builds and sends click tracking URL to `yandex.ru/clck/click`, reads `yandexuid` from Yandex Browser |

### Network addresses found in binary

Addresses below marked **[patched]** are disabled by binary patches. Addresses marked **[firewall]** are blocked only via Windows Firewall — not patched in the binary.

- `http://soft.export.yandex.ru/status.xml` — usage statistics **[patched]**
- `http://download.yandex.ru/punto/version.rss` — update checks **[patched]**
- `https://yandex.ru/clck/click/dtype=stred/pid=156/cid=73020/path=` — click tracking **[patched]**
- `https://download.yandex.ru/punto/config/` — config download **[firewall only]**
- `https://share.yandex.net/go.xml` — sharing **[firewall only]**
- `http://maps.yandex.ru`, `http://translate.yandex.ru`, `http://market.yandex.ru` — UI integrations **[firewall only]**

### Key strings found

```
"CYaUpdater::PingStatThread"
"[%lx] %s(%d) +++ Sending statistics using YaUpdater"
"Punto Switcher Stat"
"yandex.statistics.ui"
"yandexuid"
```

---

## What this project does

1. **Patches** three analytics functions in `punto.exe` to return immediately without executing
2. **Blocks** all outgoing connections from `punto.exe` and `ps64ldr.exe` via Windows Firewall
3. **Removes** `yupdate.exe` and `yupdate.dll` (the updater/stats components)

> **Note:** The patches are based on static analysis only. Dynamic verification (Procmon, Wireshark) was not performed. Firewall rules provide an additional layer regardless of patch effectiveness.

Punto Switcher continues to work normally as a keyboard layout switcher after these changes.

---

## Usage

### Step 1 — Block network access (before installation)

Run `scripts/firewall_block.bat` as Administrator **before** running the installer.

### Step 2 — Install Punto Switcher

Run the official installer normally.

### Step 3 — Patch analytics

Run `scripts/patch_analytics.ps1` as Administrator after installation.

### Step 4 — Add Windows Defender exclusion for punto.exe (if needed)

After patching, Windows Defender may flag `punto.exe` due to the broken digital signature. If that happens:

```powershell
# Run as Administrator
Add-MpPreference -ExclusionProcess "punto.exe"
```

> **Warning:** This disables Defender scanning for `punto.exe`. Only do this if Defender removes the patched file.

---

## Technical details

### Binary patches applied to punto.exe

Each function entry is overwritten. For 32-bit MSVC `__stdcall`/`__thiscall` functions, the correct patch must account for `ret N` (stack cleanup) vs plain `ret`. Each target function here uses `ret` with no arguments from the caller's perspective at the patch point, verified by checking the function signature in Ghidra (`void` return, no parameters visible at entry).

| Virtual Address | File Offset | Original bytes | Patched bytes | Function |
|---|---|---|---|---|
| `0x00445FB0` | `0x453B0` | `55 8B EC` | `31 C0 C3` | Update check |
| `0x004464C0` | `0x458C0` | `55 8B EC` | `31 C0 C3` | Stat ping thread |
| `0x00446D70` | `0x46170` | `55 8B EC` | `31 C0 C3` | Click tracking |

> `FUN_00445BA0` (yupdate.dll loader) is **not** patched — patching it causes a crash because callers check its return value during initialization. `yupdate.dll` and `yupdate.exe` are physically deleted instead, so the loader fails on its own when it tries to `LoadLibrary("yupdate.dll")`.

### Files removed

- `yupdate.exe` — Yandex updater executable
- `yupdate.dll` — exports `DLLUsageReport`, `DLLOnApplicationStartup`, `DLLSetApplicationState`

### Firewall rules added

```
Punto - Setup block      → outbound BLOCK → PuntoSwitcherSetup.exe
Punto - punto.exe block  → outbound BLOCK → punto.exe
Punto - ps64ldr block    → outbound BLOCK → ps64ldr.exe
```

---

## Disclaimer

This project is for **research and educational purposes** only.

- Punto Switcher is proprietary software owned by Yandex LLC.
- This repository contains **no binary files** from Punto Switcher.
- Patching a proprietary binary may violate the Punto Switcher EULA. Check the license agreement before applying patches.
- All patches are described as byte offsets for research documentation purposes.

---

## License

Scripts and documentation in this repository are released under [MIT License](LICENSE).  
Punto Switcher binaries remain property of Yandex LLC.
