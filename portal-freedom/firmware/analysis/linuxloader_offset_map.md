# LinuxLoader-terry.efi Offset Map for Portal Exploit Adaptation

**Binary:** LinuxLoader-terry.efi (PE32+ AArch64, 741KB)
**Source:** Marcel @MarcelD505 via gofile.io
**Target:** Portal Go (terry), but built from aloha/Cipher codebase
**Date:** 2026-02-26
**Analysis:** Python prologue scan + Ghidra 12.0.3 headless decompilation

---

## PE Structure

| Section | VA | VSize | Raw Size | Purpose |
|---------|-----|-------|----------|---------|
| .text | 0x001000 | 0x094000 | 0x094000 | Code (608KB) |
| .data | 0x095000 | 0x01d000 | 0x01d000 | Data (116KB) |
| .reloc | 0x0b2000 | 0x003000 | 0x003000 | Relocations (12KB) |

**Code boundary:** 0x095000
**Entry point:** 0x001000
**Image size:** 0x0B5000 (741KB)
**Functions identified:** 1,042 (Ghidra auto-analysis) / ~69 (prologue scan)
**Total relocations:** 4,123
**Build path:** `/disk/jenkins/workspace/aloha/Cipher-non-hlos-10/src/bootable/bootloader/edk2/...`

---

## Key Functions (Terry Offsets) — Ghidra Confirmed

### Core Fastboot Infrastructure

| Function | Address | Size | Ghidra Name | Evidence |
|----------|---------|------|-------------|----------|
| **FastbootFail** | **0x00F004** | 72 | FUN_0000f004 | Thin wrapper: calls FUN_0000f04c (FastbootResponse) |
| **FastbootResponse** | **0x00F04C** | ~340 | FUN_0000f04c | Common response sender for both FAIL and OKAY |
| **FastbootOkay** | **0x00F1A0** | 72 | FUN_0000f1a0 | Thin wrapper: calls FUN_0000f04c (FastbootResponse) |
| **AsciiStrLen** | **0x03BFF4** | 224 | FUN_0003bff4 | EDK2 `AsciiStrLen()` — returns string length |
| **AsciiStrnCmp** | **0x03C294** | 300 | FUN_0003c294 | EDK2 `AsciiStrnCmp()` — compare N chars, return diff |
| **FastbootPublishVar** | **0x014F24** | 188 | FUN_00014f24 | Linked list insert: `*puVar3 = DAT_000a0f70; DAT_000a0f70 = puVar3` |
| **DebugPrint** | **0x039C50** | ~200 | FUN_00039c50 | Serial/debug log output (called ~100+ times) |
| **DebugAssertCheck** | **0x03A16C** | ~68 | FUN_0003a16c | Returns nonzero if debug assertions enabled |
| **DebugLevelCheck** | **0x03A1B0** | ~100 | FUN_0003a1b0 | Checks if debug level mask matches |
| **AssertFailed** | **0x03A040** | ~300 | FUN_0003a040 | Assertion failure handler (file, line, expression) |

### Command Dispatch Pattern (Ghidra Corrected)

**Previous assumption was wrong.** The two BL calls per command are NOT "register name" + "set handler". They are:
1. `BL 0x03BFF4` — `AsciiStrLen(cmd_name)` — get command string length
2. `BL 0x03C294` — `AsciiStrnCmp(input, cmd_name, len)` — compare input against command

The command dispatcher (`FUN_00010078`, 1580 bytes) at 0x010078 sequentially compares the received command string against known commands: "download", "flash", "erase", etc. Each comparison uses strlen+strncmp. On match, the corresponding handler code executes inline or via event callback.

| Command | String RVA | Comparison Site | Handler Area |
|---------|-----------|-----------------|--------------|
| `download` | 0x073797 | 0x0100F4 | Event → CmdDownload (~0x014D00) |
| `flash` | 0x072571 | 0x010230, 0x010274 | FUN_00012010 @ 0x012010 |
| `erase` | 0x0720D7 | 0x0102B8 | ~0x014100 area |
| `getvar:partition-type` | 0x0720F0 | 0x01050C | inline |
| `boot-recovery` | 0x0723FF | 0x0148D0, 0x02665C | ~0x026600 |
| `boot-fastboot` | 0x07240F | 0x014980, 0x0266B4 | ~0x026600 |
| `reboot` | 0x0735C5 | 0x025EAC | ~0x014870 |
| `set_active:` | ? | ? | ~0x00FA00 |
| `unlock_bootloader` | (wide) | 0x012058 (flash handler) | FUN_00015a60 @ 0x015A60 |
| `UFS` / `EMMC` / `NAND` | various | 0x012494+ | Storage type dispatch |

### Critical Exploit-Relevant Functions (Ghidra Decompiled)

| Function | Terry Address | Size | Ghidra Name | Role |
|----------|-------------|------|-------------|------|
| **FastbootFail** | 0x00F004 | 72 | FUN_0000f004 | Sends FAIL response |
| **FastbootOkay** | 0x00F1A0 | 72 | FUN_0000f1a0 | Sends OKAY response |
| **DataReadyHandler** | 0x00FE30 | 584 | FUN_0000fe30 | Download data reception + "Download Finished" |
| **BootPartitionCheck** | 0x00F6B8 | 424 | FUN_0000f6b8 | Scans for "boot" partition updates |
| **CommandDispatcher** | 0x010078 | 1580 | FUN_00010078 | Main fastboot command router |
| **FastbootInit** | 0x0107D8 | 3972 | FUN_000107d8 | Buffer alloc + variable publish + init |
| **FlashHandler** | 0x012010 | 8232 | FUN_00012010 | Flash + partition table + unlock dispatch |
| **FastbootPublishVar** | 0x014F24 | 188 | FUN_00014f24 | Register getvar variables |
| **UnlockVerify** | 0x015A60 | 708 | FUN_00015a60 | Verify OEM unlock request signature |
| **SetLockUnlockState** | 0x016654 | 328 | FUN_00016654 | Lock/unlock/critical state setter |
| **ResetDownloadState** | 0x011C68 | ~100 | FUN_00011c68 | Reset download progress counters |
| **AllocatePool** | 0x00D814 | ~200 | FUN_0000d814 | UEFI memory allocator |
| **FreePool** | 0x00D8E0 | ~100 | FUN_0000d8e0 | UEFI memory free |
| **StackCanaryFail** | 0x017538 | ~50 | FUN_00017538 | Stack cookie mismatch handler (noreturn) |
| **RebootDevice** | 0x017728 | ~100 | FUN_00017728 | Reboot device (param '\x01') |
| **SetWatchdogState** | 0x02BD34 | ~200 | FUN_0002bd34 | Enable/disable watchdog timer |
| **GetBlockAlignment** | 0x0181E8 | ~100 | FUN_000181e8 | Get storage block alignment |
| **GetDeviceSerial** | 0x0365D4 | ~100 | FUN_000365d4 | Returns device serial string |
| **AsciiSPrint** | 0x049354 | ~200 | FUN_00049354 | Formatted string print (like snprintf) |

### Lock State Functions (Ghidra Decompiled)

| Function | Address | Size | Ghidra Name | Role |
|----------|---------|------|-------------|------|
| **IsDeviceLocked** | 0x032530 | ~68 | FUN_00032530 | Returns nonzero if device locked |
| **IsDeviceCriticalLocked** | 0x032574 | ~196 | FUN_00032574 | Returns nonzero if critical partitions locked |
| **IsDeviceUnsealed** | 0x032638 | ~700 | FUN_00032638 | Returns nonzero if device NOT unsealed |
| **SetDeviceState** | 0x032914 | ~800 | FUN_00032914 | Write lock/unlock state to storage |
| **SetUnlockState** | 0x033038 | ~540 | FUN_00033038 | Set unlock state (param: 0=lock, 1=unlock) |
| **GetUnlockState** | 0x033254 | ~220 | FUN_00033254 | Read stored unlock state |
| **GetStoredNonce** | 0x0332EC | ~68 | FUN_000332ec | Retrieve stored unlock nonce |
| **SetLockState** | 0x033330 | ~900 | FUN_00033330 | Write lock state to persistent storage |
| **VerifyUnlockRequest** | 0x01731C | ~176 | FUN_0001731c | Verify OEM unlock signature (method 1) |
| **VerifyUnlockRequestAlt** | 0x0173CC | ~200 | FUN_000173cc | Verify OEM unlock signature (method 2) |

**Lock check flow in FlashHandler (0x012010):**
```
FUN_00032530() → IsDeviceLocked?
  └─ if locked AND FUN_00032574() → IsCriticalLocked?
       └─ if critical AND FUN_00015d24(partition) → IsCriticalPartition?
            └─ if critical AND FUN_00032638() → IsUnsealed?
                 └─ if NOT unsealed AND FUN_00015db8(partition) → IsProtectedPartition?
                      └─ if all checks fail → "Flashing is not allowed"
```

---

## Data Section Variables (Ghidra Decompiled) — EXPLOIT CRITICAL

### Fastboot Buffer State (0x0A0F00 region)

These are the critical data addresses controlling the download buffer, directly relevant to CVE-2021-1931:

| Address | Size | Name | Purpose | p114 Equiv |
|---------|------|------|---------|------------|
| **0x0A0F28** | 8 | `download_size` | Expected download size (bytes to receive) | part of state struct |
| **0x0A0F30** | 8 | `bytes_received` | Running counter of bytes downloaded | part of state struct |
| **0x0A0F40** | 8 | `buffer_base` | Original allocated buffer base address | part of state struct |
| **0x0A0F48** | 8 | **`active_buf_ptr`** | **Active download buffer write pointer** | **0xFB658** |
| **0x0A0F50** | 8 | `swap_buf_ptr` | Alternate/swap buffer pointer | part of state struct |
| **0x0A0F58** | 8 | `alloc_buf_size` | Total allocated buffer size (from free mem) | part of state struct |
| **0x0A0F88** | 8 | `saved_dl_size` | Saved download size (copied for flash ops) | part of state struct |

**Buffer initialization (in FastbootInit @ 0x0107D8):**
```c
// After allocating memory (local_138 = AllocatePages result):
DAT_000a0f40 = local_138;   // buffer_base = allocated memory
DAT_000a0f48 = local_138;   // active_buf_ptr = same (start of buffer)
DAT_000a0f28 = uVar22;      // download_size = allocated size
DAT_000a0f88 = uVar22;      // saved_dl_size = same
DAT_000a0f50 = local_138;   // swap_buf_ptr = same initially
```

**Buffer double-swap (in FlashHandler @ 0x012010):**
```c
piVar6 = DAT_000a0f48;       // Save current active pointer
DAT_000a0f48 = DAT_000a0f50; // Active ← swap (other buffer half)
DAT_000a0f50 = piVar6;       // Swap ← old active
DAT_000a0f88 = DAT_000a0f28; // Save download size for flash use
```

**Download completion check (in DataReadyHandler @ 0x00FE30):**
```c
DAT_000a0f30 = uVar4 + DAT_000a0f30;  // Accumulate bytes received
if (DAT_000a0f30 == DAT_000a0f28) {    // All bytes received?
    // "Download Finished\n" → proceed to command processing
}
```

### Fastboot State Flags

| Address | Size | Name | Purpose |
|---------|------|------|---------|
| 0x0A0F11 | 1 | `flash_status` | Flash operation status (cleared at flash start) |
| 0x0A0F12 | 1 | `download_state` | Download active flag (0x01 = download in progress) |
| 0x0A0F13 | 1 | `post_dl_flag` | Post-download processing state |
| 0x0A0F18 | 8 | `unlock_perm` | Unlock operation permission flag |
| 0x0A0F70 | 8 | `pubvar_list` | Published variables linked list head |
| 0x0A0F78 | 8 | `flash_active` | Flash-in-progress flag (checked in dispatcher) |
| 0x0A0FBA | ? | `unlock_nonce` | Stored unlock nonce data |

### UEFI Runtime Pointers

| Address | Size | Name | Purpose |
|---------|------|------|---------|
| **0x099E30** | 8 | `boot_services` | UEFI Boot Services Table pointer |
| 0x099EE8 | 8 | `dl_in_progress` | Download-in-progress bit flag (bit 0) |
| 0x095418 | 8 | `stack_canary` | Stack cookie / security canary value |
| 0x095150 | 4 | `lun_index` | Storage LUN index (-1 = eMMC, 0+ = UFS LUN) |
| 0x0A0F80 | 8 | `charger_proto` | FbChargerProtocol handle |
| 0x0A6590 | ? | `partition_table` | Partition record array (per-LUN) |
| 0x0A5990 | ? | `partition_handles` | Partition handle array (per-LUN) |

**Boot Services call patterns (offset from DAT_00099e30):**
| Offset | UEFI Boot Service | Usage in code |
|--------|------------------|---------------|
| +0x38 | GetMemoryMap | Buffer size calculation in FastbootInit |
| +0x50 | CreateEvent | Event creation for download/flash callbacks |
| +0x58 | SetTimer | Set timer for event signaling |
| +0x68 | SignalEvent | Signal completion events |
| +0x70 | CloseEvent | Close event handles |
| +0x98 | HandleProtocol | Access partition protocols |
| +0x100 | SetWatchdogTimer | Disable watchdog in FastbootInit |
| +0x140 | LocateProtocol | Find FbChargerProtocol etc. |
| +0x168 | SetMem | Memory clear (buffer zeroing) |
| +0x170 | InstallProtocolInterface | Register protocols |

### Buffer Size Constraints

```c
// In FastbootInit, buffer sizing logic:
DAT_000a0f58 = (free_memory * 3 / 4 + 0xFFF) & ~0xFFF;  // 75% of free mem, page-aligned
if (DAT_000a0f58 > 0x60000000) {
    DAT_000a0f58 = 0x60000000;  // Cap at 1.5GB
}
// Then halved for dual-slot devices:
if (FUN_00017e94() != 2) {  // If not dual-LUN
    uVar22 = DAT_000a0f58 >> 1;  // Halve for single buffer
}
```

Max download: 512MB (`getvar max-download-size` = 0x20000000 = 536870912)

---

## Lock State & Security

| Feature | Address | String |
|---------|---------|--------|
| Lock state check (flash) | 0x012238 | "Flashing is not allowed in Lock State" |
| Lock state check (erase) | 0x014148 | "Erase is not allowed in Lock State" |
| Critical partition check | 0x01229C | "Flashing is not allowed for Critical Partitions" |
| Persist partition check | 0x0122B8 | "Flashing is not allowed for persist partition" |
| Slot change lock check | 0x00FA1C | "Slot Change is not allowed in Lock State" |
| Boot partition locked | 0x016B74 | "Boot partition is locked." |
| Sealed state set | 0x016B90 | "Failed to set sealed state" |
| ADB lock | 0x016BFC | "Adb is now locked" |
| Unlock ability check | 0x01170C | "IsAllowUnlock is %d" |
| Get unlock ability var | 0x0142F8 | "get_unlock_ability: %d" |
| Unlock FAIL | 0x0166F8 | "Flashing Unlock is not allowed" → BL 0x033330 |
| Unlock OK nonce gen | 0x01442C | "Error locating PRNG protocol" |
| Unlock request FAIL | 0x0144E8 | "OEM Unlock Request Failed" |
| Unlock allowed | 0x015C9C | "Fastboot unlock is now allowed." → BL FastbootOkay |
| Unlock request reuse | 0x015B84 | "Unlock-allow request cannot be reused." |
| Device info strings | 0x073510 | "Device unlocked: %a" |
| Device critical unlock | 0x073524 | "Device critical unlocked: %a" |
| Device unsealed | 0x073559 | "Device unsealed: %a" |
| Locked string | 0x02CE10 | "locked" (loaded into x3) |

### Unlock Verification Flow (Ghidra Decompiled)

From `FUN_00015a60` (UnlockVerify, 708 bytes):

```
1. Validate params: param_1 != NULL && param_2 >= 0x59 (89 bytes min)
2. Get device serial via FUN_000365d4()
3. Try VerifyUnlockRequest (FUN_0001731c) with serial + nonce
4. If fail → Try VerifyUnlockRequestAlt (FUN_000173cc)
5. Verify stored nonce matches (FUN_000332ec → GetStoredNonce)
6. Check byte at (unlock_data + 0x50):
   - Bit 0: unlock state already set?
   - Bit 2: critical unlock allowed?
7. If bit 2 set:
   FUN_00033038(1)  → SetUnlockState(unlocked)
   FUN_0000f1a0()   → FastbootOkay
   FUN_00017728(1)  → RebootDevice
8. Else:
   FUN_00033330(1)  → SetLockState(unlocked)
   FUN_0000f1a0()   → FastbootOkay
```

---

## Download Buffer (CVE-2021-1931 Target)

The download command handler is around 0x014D00. Key references:
- 0x014DE0: Size check — "Requested download size is more than max allowed" → FAIL
- 0x014E0C: Parse error — "Failed to get the number of bytes to download"
- 0x014EE4: Success log — "CmdDownload: Send 12 %a"
- 0x00FED8: Completion — "Download Finished\n"

Buffer allocation is in FastbootInit (FUN_000107d8 @ 0x0107D8, 3972 bytes):
- 0x010B34: "ERROR: Allocation fail for minimum buffer for fastboot"
- 0x010B60: "Failed to get free memory for fastboot buffer"
- 0x010B98: "Not enough memory to Allocate Fastboot Buffer"
- 0x010BE4: "Fastboot Buffer Size allocated: %ld"

### Exploit-Critical Data Flow

```
┌─ FastbootInit (0x0107D8) ─────────────────────────────────┐
│  Query free memory → Allocate 75% (capped 1.5GB)          │
│  Set: buffer_base, active_buf_ptr, swap_buf_ptr            │
│  All three point to same allocation initially              │
└────────────────────────────────────────────────────────────┘
        │
        ▼
┌─ CmdDownload (~0x014D00) ─────────────────────────────────┐
│  Parse size from "download:XXXXXXXX"                       │
│  Validate: size <= alloc_buf_size (DAT_000a0f58)           │
│  Set: download_size = parsed size                          │
│  Set: bytes_received = 0                                   │
│  Set: dl_in_progress flag (DAT_00099ee8 |= 1)             │
│  Send "DATA" + hex_size response                           │
│  ⚠️ NO VALIDATION that size fits actual buffer! ⚠️         │
└────────────────────────────────────────────────────────────┘
        │
        ▼
┌─ DataReadyHandler (0x00FE30) ─────────────────────────────┐
│  If dl_in_progress:                                        │
│    Copy received data to active_buf_ptr + bytes_received   │
│    bytes_received += chunk_size                             │
│    If bytes_received == download_size:                      │
│      "Download Finished" → next command                    │
│      ⚠️ OVERFLOW: writes past buffer into ABL code pages!  │
│  Else:                                                     │
│    Pass to CommandDispatcher (FUN_00010078)                 │
└────────────────────────────────────────────────────────────┘
```

---

## String Map (Key Strings)

| String | RVA | Usage |
|--------|-----|-------|
| "download" | 0x073797 | Command registration |
| "flash:" | 0x072571 | Command registration |
| "flash" | 0x072571 | Also used standalone |
| "erase:" | 0x0720D7 | Command registration |
| "erase" | 0x0720D7 | Also used standalone |
| "boot" | 0x06C9F6 | Partition name (Ghidra: 20+ xrefs) |
| "continue" | 0x0723BD | Command string |
| "reboot" | 0x0735C5 | Command string |
| "reboot-bootloader" | ? | Not ADRP-found |
| "getvar:" | 0x07242F | Command string |
| "set_active:" | ? | Not ADRP-found |
| "fastboot" | 0x072414 | Boot mode string |
| "max-download-size" | 0x072473 | Getvar variable |
| "version-bootloader" | 0x072509 | Getvar variable |
| "logical-block-size" | 0x0724E5 | Getvar variable |
| "erase-block-size" | 0x0724F8 | Getvar variable |
| "unknown command" | 0x07211B | Error response |
| "Download Finished\n" | 0x071EF3 | Status log |
| "Fastboot: Processing commands\n" | 0x071633 | Status log |
| "Fastboot: Initializing...\n" | ~0x071600 | Init log |
| "Flashing is not allowed in Lock State" | 0x0725A1 | Lock check error |
| "Flashing Unlock is not allowed\n" | 0x0733FB | Unlock denied |
| "No such partition" | ~0x072000 | Flash error |
| "androidboot.hardware=cipher" | 0x0779CA | Boot cmdline |
| "Portal is starting up in developer mode" | 0x096C76 | Dev mode message |
| "Please Reboot..." | 0x0964CC | Fastboot screen |
| "Unlocked" | 0x06CDBF | Boot state string |
| "Locked" | 0x06CDC8 | Boot state string |
| "DataReady %d\n" | ~0x071E00 | Download data arrival |
| "AcceptData: Send %d\n" | ~0x071E40 | Data acceptance log |
| "Handling Cmd: %a\n" | ~0x071700 | Command dispatch log |
| "unlock_bootloader" | (wide string) | Flash handler special case |
| "avb_custom_key" | (wide string) | Custom key partition check |
| "Boot Partition is updated\n" | ~0x06C780 | Partition table update |

---

## Comparison: Sony p114 vs Portal terry (Ghidra Updated)

| Concept | Sony p114 | Portal terry | Status |
|---------|-----------|-------------|--------|
| Code boundary | 0x0E7000 | 0x095000 | Terry is 0.64x size |
| FastbootFail | 0x28E64 | 0x00F004 | **CONFIRMED** (Ghidra) |
| FastbootOkay | 0x28DBC | 0x00F1A0 | **CONFIRMED** (Ghidra) |
| FastbootResponse | 0x28EA8 | 0x00F04C | **CONFIRMED** (common sender) |
| **Download buffer ptr** | **0xFB658** | **0x0A0F48** | **FOUND** (Ghidra: DAT_000a0f48) |
| Download size | part of struct | 0x0A0F28 | **FOUND** (DAT_000a0f28) |
| Bytes received | part of struct | 0x0A0F30 | **FOUND** (DAT_000a0f30) |
| Buffer base | part of struct | 0x0A0F40 | **FOUND** (DAT_000a0f40) |
| Swap buffer ptr | part of struct | 0x0A0F50 | **FOUND** (DAT_000a0f50) |
| Alloc buffer size | part of struct | 0x0A0F58 | **FOUND** (DAT_000a0f58) |
| Boot Services Table | in UEFI system | 0x099E30 | **FOUND** (DAT_00099e30) |
| BL state struct | 0xF3B78 | 0x032530-0x033330 area | **FOUND** (functions, not single struct) |
| exploit_continue | 0x28DC8 | ~0x00FE30 (DataReadyHandler) | **FOUND** (FUN_0000fe30) |
| flash handler | 0x264A4 | 0x012010 | **CONFIRMED** (8232 bytes) |
| erase handler area | 0x28298 | 0x014100 area | Confirmed via strings |
| oem unlock handler | 0x4D9E4 | 0x015A60 | **CONFIRMED** (708 bytes) |
| lock/unlock setter | part of struct | 0x016654 | **CONFIRMED** (328 bytes) |
| command dispatcher | part of handler | 0x010078 | **CONFIRMED** (1580 bytes) |
| fastboot init | N/A | 0x0107D8 | **CONFIRMED** (3972 bytes) |
| boot cmd handler | 0x286DC | 0x016B74 area | Confirmed via strings |
| "flash:fb" trigger | 0x26560 | Same pattern expected | "No such partition" |
| IsDeviceLocked | part of struct | 0x032530 | **FOUND** (separate function) |
| IsCriticalLocked | part of struct | 0x032574 | **FOUND** |
| IsDeviceUnsealed | part of struct | 0x032638 | **FOUND** |
| StackCanary | N/A | 0x095418 | **FOUND** (DAT_00095418) |

---

## BL Opcode Patterns for Blind Exploit

The test2/test3 shellcode searches backward from overflow position for BL instructions
targeting FastbootFail. These are candidate patterns derived from terry:

### From "unknown command" handler (0x0105C0 → 0x00F004)
```
Distance: 0x0105C0 - 0x00F004 = 0x015BC = 5564 instructions back
BL encoding: 0x97FFFA91  (bytes: 91 FA FF 97)
```

### From flash lock check (0x012238 → 0x00F004)
```
Distance: 0x012238 - 0x00F004 = 0x0321C = 12828 instructions back (wrong, let me recalc)
Actually: (0x012238 - 0x00F004) / 4 = 0xC8D instructions
BL encoding: 0x97FFF373  (bytes: 73 F3 FF 97)
```

### BL encoding formula
```
BL offset = (target - current) / 4   (signed 26-bit)
BL opcode = 0x94000000 | (offset & 0x03FFFFFF)
For backward: offset is negative, so upper bits are 1s → 0x97FFxxxx pattern
```

**For blind probing, the shellcode loads the target BL pattern into a register and scans backward through memory. Any 0x97FFxxxx opcode is a backward BL and might target FastbootFail.**

---

## Exploit Adaptation Notes (Updated with Ghidra Findings)

### What We Now Know from Terry + Ghidra

1. **Download buffer pointer is at 0x0A0F48** — This is the terry equivalent of p114's 0xFB658. The exploit shellcode reads/writes this pointer to redirect download data into ABL code pages.

2. **Buffer management is NOT a simple struct** — Unlike p114 where all buffer state is in a single struct, terry stores each variable at individual fixed .data addresses (0x0A0F28, 0x0A0F30, 0x0A0F40, 0x0A0F48, 0x0A0F50, 0x0A0F58, 0x0A0F88). This simplifies exploitation: each address is independently accessible.

3. **Lock state is checked via function calls, not struct fields** — Three separate functions: IsDeviceLocked (0x032530), IsDeviceCriticalLocked (0x032574), IsDeviceUnsealed (0x032638). Patching any of these to return 0 bypasses the corresponding check.

4. **The "unknown command" path** — `FUN_00010078` calls `FUN_0000f004` (FastbootFail) directly at 0x0105C8 when no command matches. This is the most reliable BL pattern to search for in blind exploitation.

5. **Unlock flow requires nonce + signature** — `FUN_00015a60` calls `VerifyUnlockRequest` (0x01731C) which validates a cryptographic signature over the device serial + nonce. Direct patching of lock state functions is needed to bypass this.

6. **UEFI Boot Services table at 0x099E30** — Many operations go through this table. The exploit shellcode can use this to call UEFI services directly if needed.

### What Still Requires Aloha-Specific Analysis

1. **Actual aloha data addresses** — The 0x0A0Fxx offsets are for terry. Aloha's ABL will have different .data layout. The blind memory dump will reveal these.
2. **Stack canary value** — terry uses DAT_00095418. Aloha will have a different address.
3. **USB DMA buffer physical address** — Depends on runtime memory allocation.
4. **Cache line behavior** — ARM cache coherency for code modification.

### Blind Exploit Strategy (Refined with Ghidra Data)

1. **test0 (crash)**: Infinite-loop `B #0x00` — confirms code execution via DMA overflow
2. **test2 (distance probe)**: PIC shellcode searches for 0x97FFxxxx BL pattern targeting FastbootFail, reports distance via FAIL response. Use PORTAL_BL_PATTERN = 0x97FFFA91 (from terry "unknown cmd" callsite)
3. **test3 (NOP sled)**: NOP sled variant with distance reporting via x2 register
4. **Memory dump**: Read decrypted ABL from RAM, return 28-byte chunks via FAIL response string. With DataReadyHandler at 0x00FE30, we know the callback structure.
5. **Full exploit**: With dumped ABL, locate aloha's 0x0A0F48 equivalent, patch lock state functions, write modified code pages
6. **Permanent unlock**: Patch IsDeviceLocked (aloha equiv of 0x032530) to return 0, patch SetDeviceState (aloha equiv of 0x032914) to write unlocked state to storage
