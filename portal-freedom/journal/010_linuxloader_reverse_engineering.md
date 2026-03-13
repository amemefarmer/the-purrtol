# Experiment 010: LinuxLoader Reverse Engineering

**Date:** 2026-02-26
**Risk Level:** ZERO (host-side binary analysis only)
**Outcome:** SUCCESS — Complete fastboot architecture mapped from terry LinuxLoader

---

## Summary

Deep reverse engineering of `LinuxLoader-terry.efi` (724KB PE32+ AArch64 EFI application from Marcel @MarcelD505) revealed the complete fastboot implementation architecture used by Facebook Portal devices. Despite this being from the Portal Go (terry/SDM670), the build paths confirm it shares the aloha codebase and the function structure will match our Portal 10" Gen 1.

## Analysis Methods

1. **Python pefile analysis** — PE header, section layout, all 4352 strings extracted
2. **AArch64 ADRP+ADD pattern scan** — Found all code-to-string cross-references
3. **Function prologue detection** — STP X29, X30 pattern identified ~69 functions
4. **Data section pointer clustering** — Identified dispatch tables and vtables
5. **BL instruction density mapping** — Found hotspot code regions
6. **Specific opcode pattern search** — CMP #0x200, LDR patterns from xperable

## Key Discoveries

### 1. Fastboot Function Architecture

The entire fastboot implementation follows a clean UEFI pattern:

- **FastbootFail (0x00F004)** — Sends FAIL response back to host
- **FastbootOkay (0x00F1A0)** — Sends OKAY response back to host
- **AsciiStrLen (0x03BFF4) + AsciiStrnCmp (0x03C294)** — Command matching (see journal 011 correction)
- **FastbootPublishVar (0x014F24)** — Publishes getvar variables

### 2. Command Registration Pattern

Every fastboot command is registered with TWO function calls:
```
ADRP x0, #page         ; Load command string page
ADD  x0, x0, #offset   ; Complete string address
BL   0x03BFF4           ; Register command name (matching function)
...
ADRP x1, #page         ; Load handler function pointer
ADD  x1, x1, #offset
BL   0x03C294           ; Register handler
```

### 3. Complete Command Map

| Command | String Address | Code Registration | Handler Region |
|---------|---------------|-------------------|----------------|
| download | 0x073797 | 0x0100F4 | 0x014D00 |
| flash: | 0x072571 | 0x010230 | 0x012000 |
| erase: | 0x0720D7 | 0x0102B8 | 0x014100 |
| boot-recovery | 0x0723FF | 0x0148D0 | 0x026600 |
| boot-fastboot | 0x07240F | 0x014980 | 0x026600 |
| reboot | 0x0735C5 | 0x025EAC | 0x014870 |

### 4. CVE-2021-1931 Target Area

The download command handler is around **0x014D00**:
- Size validation: "Requested download size is more than max allowed" (0x014DE0)
- Buffer allocation: "Fastboot Buffer Size allocated: %ld" (0x010BE4)
- Completion: "Download Finished\n" referenced at 0x00FED8

The buffer allocation in fastboot init (0x010B34-0x010BE4) shows:
- Minimum buffer allocation error at 0x010B34
- Free memory check at 0x010B60
- Not enough memory at 0x010B98
- Success log at 0x010BE4

### 5. Lock/Unlock Architecture

The unlock flow involves:
1. **Allow-unlock check** (0x01170C): "IsAllowUnlock is %d"
2. **Nonce generation** (0x01442C): Uses PRNG protocol
3. **Unlock validation** (0x0144E8): "OEM Unlock Request Failed"
4. **Unlock success** (0x015C9C): "Fastboot unlock is now allowed." → FastbootOkay
5. **Lock state enforcement** across flash (0x012238), erase (0x014148), boot (0x016B74)
6. **Device info report** (0x073510): "Device unlocked: %a", "Device critical unlocked: %a", "Device unsealed: %a"

### 6. Developer Mode Exists!

"Portal is starting up in developer mode" at 0x096C76 — confirms a developer mode codepath.

### 7. ADB Gating

- ADB lock handler at 0x016BFC: "Adb is now locked" → FastbootOkay
- Boot cmdline includes: "androidboot.hardware=cipher" (0x0779CA)

---

## Size Comparison: Sony p114 vs Portal terry

| Feature | Sony p114 (MSM8998) | Portal terry (SDM670) |
|---------|--------------------|-----------------------|
| Code section | 0xE7000 (924KB) | 0x94000 (608KB) |
| Total image | ~1MB | 741KB (0xB5000) |
| FastbootFail | 0x28E64 | 0x00F004 |
| Download area | 0x24B3C | 0x014D00 |
| Flash lock check | 0x264D0 | 0x012238 |
| Erase lock check | 0x282C4 | 0x014148 |
| Unlock handler | 0x4D9E4 | 0x015AA0 |
| Download buf ptr | 0xFB658 | TBD (Ghidra) |
| BL state struct | 0xF3B78 | TBD (Ghidra) |

Terry is approximately **0.66x the size** of the Sony p114 LinuxLoader, which means aloha (our target) may be somewhere in between.

---

## Impact on Exploit Strategy

### Confirmed Viable

1. **test0 (crash)** — Infinite-loop opcodes. No ABL knowledge needed.
2. **test2/test3 (distance probe)** — PIC shellcode searches for BL-to-FastbootFail pattern. We now know FastbootFail's role and can design the search pattern for aloha.
3. **Memory dump** — Once code execution is achieved, shellcode can read the decrypted ABL from RAM and send chunks back via FAIL response strings.
4. **Full exploit** — After dump, all offsets known for target-portal.c.

### Key Insight for Blind Exploit

The **FastbootFail function** is the anchor point. In every LinuxLoader:
- It's called from the "unknown command" handler
- It's called from the "Download Finished" area
- The `BL FastbootFail` opcode pattern is unique and searchable

The xperable test2 shellcode searches for `B3 ED FF 97` which encodes a specific BL offset. For our aloha target, the opcode will be different (different distance), but the **technique is the same**: scan backwards from the overflow landing zone for BL instructions targeting a common utility function.

---

## Files Created

| File | Purpose |
|------|---------|
| `firmware/analysis/analyze_linuxloader.py` | Python analysis script (pefile + pattern matching) |
| `firmware/analysis/python_analysis_output.txt` | Full analysis output |
| `firmware/analysis/all_strings.txt` | Complete string extraction (4352 strings) |
| `firmware/analysis/analysis_results.json` | Machine-readable results |
| `firmware/analysis/linuxloader_offset_map.md` | Comprehensive offset mapping |
| `journal/010_linuxloader_reverse_engineering.md` | This journal entry |

---

## Next Steps

1. **Ghidra deep analysis** — Load in Ghidra for full disassembly with function/variable naming
   - Find exact download_buffer_ptr offset in .data
   - Find exploit_continue return address
   - Find bl_state_struct location
   - Map the VerifiedBootDxe module if embedded

2. **Design blind memory dump shellcode** — Based on the FastbootFail anchor pattern
   - Position-independent AArch64 code
   - Searches for BL-to-FAIL pattern to find return address
   - Reads N bytes from code region
   - Formats as hex in FAIL response string

3. **Run test0 on Portal** — Confirm DMA overflow → code execution (infinite-loop hang)

4. **Run test2 on Portal** — Discover buffer-to-code distance on aloha

5. **Execute memory dump** — Read decrypted aloha ABL from live RAM

6. **Create target-portal.c** — With discovered aloha offsets

7. **Contact Marcel** — Ask about "readable later ABLs" methodology
