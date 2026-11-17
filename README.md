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

Run `scripts/firewall_block.bat` as Administrator **before** running the installer. If the installer is not in `Downloads`, pass its path:

```bat
firewall_block.bat C:\path\to\PuntoSwitcherSetup.exe
```

### Step 2 — Install Punto Switcher

Run the official installer normally.

### Step 3 — Patch analytics

Run as Administrator. First a dry run (changes nothing, shows exactly what will be patched):

```powershell
.\scripts\patch_analytics.ps1 -DryRun
.\scripts\patch_analytics.ps1
```

The script refuses to write anything if the original bytes at any offset do not match (e.g. a different Punto version).

### Step 4 — Defender exclusion (only if needed)

After patching, Windows Defender may flag `punto.exe` due to the broken digital signature. If that happens:

```powershell
.\scripts\patch_analytics.ps1 -AddDefenderExclusion
```

> **Warning:** This disables Defender scanning for the `punto.exe` process. Only do this if Defender removes the patched file.

### Undo

```powershell
.\scripts\restore_backup.ps1      # restores the original punto.exe from punto.exe.backup
.\scripts\firewall_block.bat remove   # removes the firewall rules
```

`yupdate.exe` / `yupdate.dll` are not restored — reinstall Punto Switcher for that.

---

## Technical details

### Binary patches applied to punto.exe

Each function entry is overwritten with `xor eax, eax` + `ret`. On 32-bit MSVC, `__thiscall` methods and `__stdcall` thread procedures end with `ret N` (the callee pops its arguments), so a plain `ret` would unbalance the stack. The patcher does not assume the calling convention: for each target it scans forward from the entry for the function's own epilogue (`pop ebp`/`leave` followed by `ret` or `ret N`) and builds the stub accordingly:

- no arguments: `31 C0 C3`
- `N` bytes of arguments: `31 C0 C2 NN 00` (5 bytes)

The detected value for each function is printed by `-DryRun`.

| Virtual Address | File Offset | Original bytes | Patched bytes | Function |
|---|---|---|---|---|
| `0x00445FB0` | `0x453B0` | `55 8B EC` | `31 C0 C3` or `31 C0 C2 NN 00` | Update check |
| `0x004464C0` | `0x458C0` | `55 8B EC` | `31 C0 C3` or `31 C0 C2 NN 00` | Stat ping thread |
| `0x00446D70` | `0x46170` | `55 8B EC` | `31 C0 C3` or `31 C0 C2 NN 00` | Click tracking |

VA → file offset is computed from the PE section table (`.text`: VA `0x1000`, raw `0x400`).

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
