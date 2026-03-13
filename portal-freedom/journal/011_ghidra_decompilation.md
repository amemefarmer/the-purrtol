# Experiment 011: Ghidra Headless Decompilation of LinuxLoader

**Date:** 2026-02-26
**Risk Level:** ZERO (host-side binary analysis only)
**Outcome:** SUCCESS — 1042 functions discovered, 12 key functions decompiled, all critical data addresses found

---

## Summary

Ran Ghidra 12.0.3 headless analysis on LinuxLoader-terry.efi using a custom Java GhidraScript (`GhidraExport.java`). This significantly advanced our understanding beyond the Python-based analysis in experiment 010, revealing the exact data layout of the fastboot download buffer system and confirming/correcting function identifications.

**Critical finding:** The download buffer pointer lives at `DAT_000a0f48` in terry — the equivalent of p114's `0xFB658`. This is THE key address for CVE-2021-1931 exploitation.

## Setup Challenges

### Challenge 1: Ghidra 12.0.3 Dropped Jython
The initial Python-based export script failed because Ghidra 12.0.3 requires PyGhidra for Python scripting (Jython was removed). Error: "Ghidra was not started with PyGhidra. Python is not available."

**Solution:** Rewrote the entire export script in Java as `GhidraExport.java`.

### Challenge 2: Script Path Registration
Ghidra couldn't find the script at `/tmp/GhidraExport.java` — scripts must be in a registered script directory.

**Solution:** Created `/tmp/ghidra_scripts/`, copied script there, used `-scriptPath /tmp/ghidra_scripts` flag.

### Challenge 3: ReferenceIterator API Change
`refMgr.getReferencesTo()` returns `ReferenceIterator` not `Reference[]` in Ghidra 12.x.

**Solution:** Changed to iterator-based collection with `ArrayList<Reference>`.

### Working Command
```bash
/opt/homebrew/Cellar/ghidra/12.0.3/libexec/support/analyzeHeadless \
  /tmp/ghidra_portal PortalAnalysis \
  -process LinuxLoader-terry.efi \
  -postScript GhidraExport.java \
  -scriptPath /tmp/ghidra_scripts \
  -noanalysis
```

Note: `-noanalysis` skips re-analysis since the project was already analyzed in a prior run.

## Results

### Export Statistics
| Output File | Content | Count |
|-------------|---------|-------|
| `functions.txt` | All functions with addresses, sizes, signatures | 1,042 functions |
| `string_xrefs.txt` | Cross-references for exploit-relevant strings | 605 xrefs |
| `data_pointers.txt` | Data section pointers into code section | 556 pointers |
| `decompiled.txt` | Decompiled C output for 16 key function addresses | 12 unique functions |

### Key Function Corrections

The Python analysis (experiment 010) misidentified two critical functions:

| Previous ID | Actual Function | Evidence |
|------------|-----------------|----------|
| "FastbootRegister (name)" @ 0x03BFF4 | **AsciiStrLen** | EDK2 string length function — iterates chars until null |
| "FastbootRegister (handler)" @ 0x03C294 | **AsciiStrnCmp** | EDK2 string compare — returns char difference |

The command dispatch pattern is actually `strlen(cmd) → strncmp(input, cmd, len)`, not a two-phase registration system. Commands are matched sequentially in `FUN_00010078` (CommandDispatcher).

### Critical Data Addresses Discovered

All fastboot buffer state variables live in the 0x0A0F00 region of .data:

| Terry Address | Name | Purpose | Exploit Relevance |
|--------------|------|---------|-------------------|
| **0x0A0F48** | active_buf_ptr | Current download write position | **PRIMARY exploit target** (equiv p114 0xFB658) |
| 0x0A0F50 | swap_buf_ptr | Alternate buffer for double-buffering | Used in flash handler swap |
| 0x0A0F40 | buffer_base | Original allocation base | Initial value of active_buf_ptr |
| 0x0A0F28 | download_size | Expected download size | Compared with bytes_received |
| 0x0A0F30 | bytes_received | Running download counter | Triggers "Download Finished" when == download_size |
| 0x0A0F58 | alloc_buf_size | Total allocated buffer space | Derived from 75% of free memory |
| 0x0A0F88 | saved_dl_size | Download size saved for flash | Copied during buffer swap |
| 0x099E30 | boot_services | UEFI Boot Services Table | All UEFI service calls go through this |
| 0x099EE8 | dl_in_progress | Download active bit flag | Bit 0 = currently downloading |
| 0x095418 | stack_canary | Stack security cookie | Checked at every function epilogue |

### Decompiled Function Insights

**FUN_0000f004 / FUN_0000f1a0 (FastbootFail / FastbootOkay):**
Both are 72-byte thin wrappers that call FUN_0000f04c (FastbootResponse). Ghidra shows unreachable blocks removed, suggesting dead code or optimization artifacts.

**FUN_0000fe30 (DataReadyHandler, 584 bytes):**
The core download data path. When download is active (DAT_00099ee8 bit 0), it accumulates bytes into the buffer. When `bytes_received == download_size`, it logs "Download Finished" and creates an event for the next phase. When download is NOT active, it dispatches to the CommandDispatcher. This function is the `exploit_continue` equivalent — it's where code returns after the download overflow.

**FUN_00010078 (CommandDispatcher, 1580 bytes):**
Sequential command matching: download → flash → erase → ... → unknown command → FastbootFail. The matching uses AsciiStrLen + AsciiStrnCmp (not a function pointer table). Also handles charging state checks and battery verification before processing.

**FUN_00012010 (FlashHandler, 8232 bytes):**
The largest decompiled function. Performs buffer double-swap, checks lock state through a cascade of IsDeviceLocked → IsDeviceCriticalLocked → IsDeviceUnsealed, handles UFS/eMMC/NAND storage types, and contains the partition table update logic.

**FUN_00015a60 (UnlockVerify, 708 bytes):**
Two-path unlock verification: tries VerifyUnlockRequest (0x01731C) first, falls back to VerifyUnlockRequestAlt (0x0173CC). Validates nonce against stored value, checks permission bits at offset +0x50 of the unlock data structure. On success, calls SetUnlockState + FastbootOkay + RebootDevice.

**FUN_000107d8 (FastbootInit, 3972 bytes):**
Buffer allocation sequence: queries memory map → finds largest free block → takes 75% (capped at 1.5GB, minimum checked) → allocates → initializes all buffer pointers to same base. Also publishes fastboot variables and creates event handlers.

## Impact on Exploit Development

### What This Changes
1. **target-portal.c now has correct data layout** — The buffer pointer scan pattern can target 0x0A0F48
2. **Function corrections** — AsciiStrLen/AsciiStrnCmp identification means the command dispatch is simpler than assumed
3. **Lock bypass targets identified** — Three functions (0x032530, 0x032574, 0x032638) can be individually patched
4. **UEFI Boot Services accessible** — At 0x099E30, shellcode can call any UEFI service

### What This Doesn't Change
1. **Aloha's actual addresses are different** — These are terry offsets; blind probing still needed
2. **The blind exploit strategy remains the same** — test0 → test2 → memory dump → full exploit
3. **We still need the aloha ABL** — Whether from memory dump or Marcel's help

## Files Generated

All output files copied to project at:
`portal-freedom/firmware/analysis/ghidra_output/`

- `functions.txt` — 1042 functions
- `string_xrefs.txt` — 605 string cross-references
- `data_pointers.txt` — 556 data→code pointers
- `decompiled.txt` — 12 decompiled function listings

GhidraScript source preserved at:
`/tmp/ghidra_scripts/GhidraExport.java` (also in `/tmp/GhidraExport.java`)

## Next Steps

1. Capture Portal fastboot USB VID/PID (next physical device session)
2. Apply portal-integration.patch and compile xperable with TARGET_ABL_PORTAL
3. Run test0 on Portal — confirm DMA overflow → crash (infinite loop hang)
4. Run test2/test3 — discover buffer-to-code distance on aloha
5. Execute blind memory dump — extract decrypted aloha ABL from RAM
6. With dumped ABL: find aloha's 0x0A0F48 equivalent, complete target-portal.c
