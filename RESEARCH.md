# Research Notes — Punto Switcher 4.5.0.583

## Tools used

- [Ghidra 12.0.4](https://ghidra-sre.org/) — reverse engineering
- [GhidraMCP](https://github.com/13bm/GhidraMCP) — MCP server for AI-assisted analysis
- PowerShell — binary patching and static analysis

## File analysis

### punto.exe (4,022,080 bytes)

**Digital signature:** Valid, signed by YANDEX LLC via GlobalSign EV Code Signing CA  
**Compiler:** Visual Studio (MSVC)  
**Architecture:** x86 32-bit  
**Functions:** 19,301

#### Decompiled analytics code

**PingStatThread** (`0x004464C0`):
```c
void FUN_004464c0(void) {
    // Logs: "[%lx] %s(%d) +++ Sending statistics using YaUpdater"
    CoInitialize(NULL);
    FUN_004463c0();               // prepares stat data
    (*DAT_00733f78)("punto", ...); // calls DLLUsageReport via yupdate.dll
    CoUninitialize();
}
```

**RegApplicationAndCheckUpdate** (`0x00445FB0`):
```c
// Calls yupdate COM object with:
(*DAT_00733f7c)(
    "punto",                                      // app name
    "winnt",                                      // platform
    "http://download.yandex.ru/punto/version.rss",// update URL
    "http://soft.export.yandex.ru/status.xml",    // stats URL
    0x15180,                                      // timeout
    0, version_major, version_minor, version_patch,
    flags
);
```

**Click tracking** (`0x00446D70`):
```c
// Builds URL: https://yandex.ru/clck/click/dtype=stred/pid=156/cid=73020/path=...
// Opens connection via InternetOpenW / InternetOpenUrlW
// Reads Yandex Browser cookies: yandexuid
// Path: %APPDATA%\Yandex\YandexBrowser\User Data\Local State
```

#### yupdate.dll exports (removed)

| Export | Purpose |
|---|---|
| `DLLOnApplicationStartup` | Called on app start, registers with Yandex |
| `DLLOnApplicationUninstall` | Called on uninstall |
| `DLLUsageReport` | Sends usage statistics |
| `DLLSetApplicationState` | Sets app state on Yandex servers |
| `DLLSetExecutorPath` | Sets path to yupdate.exe |
| `DLLSetUniqueParam` | Sets unique user identifier |

## Network addresses

All found via Ghidra string search in `punto.exe`:

```
http://soft.export.yandex.ru/status.xml        ← usage stats
http://download.yandex.ru/punto/version.rss     ← update check
https://download.yandex.ru/punto/config/        ← config download
https://yandex.ru/clck/click/...                ← click tracking
https://share.yandex.net/go.xml                 ← sharing
http://maps.yandex.ru                           ← Yandex Maps integration
http://translate.yandex.ru                      ← Yandex Translate
http://market.yandex.ru                         ← Yandex Market
yandexuid                                       ← user tracking cookie
```

## Patch verification

After patching, confirmed via PowerShell byte check:

```powershell
function VA-ToOffset($va) { return $va - 0x400000 - 0x1000 + 0x400 }

$bytes = [System.IO.File]::ReadAllBytes("punto.exe")
$offset = VA-ToOffset 0x004464C0
$bytes[$offset..($offset+2)]  # Should be: 0x31 0xC0 0xC3
```
