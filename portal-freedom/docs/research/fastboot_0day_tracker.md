# Fastboot 0-Day Vulnerability Tracker

**Last Updated:** February 2026

This document tracks the Qualcomm fastboot `oem ramdump` vulnerability discovered in early 2025. This vulnerability is potentially the most promising unlock path for the Facebook Portal if the device's fastboot implementation is affected.

---

## Vulnerability Overview

| Attribute | Details |
|-----------|---------|
| **Discovery** | February 2025 |
| **Discoverer** | Wanbin Mlgm (posted on XDA Forums) |
| **Type** | Stack overflow in fastboot `oem ramdump` handler |
| **Location** | Offset 0x1950 in the fastboot handler |
| **Trigger** | `fastboot oem ramdump <massive parameter>` followed by `fastboot oem uefilog` |
| **Claimed Scope** | "Vast majority of Qualcomm SoCs" including Snapdragon 8 Elite |
| **Public Exploit Code** | None (discoverer offering paid unlocking service only) |
| **CVE Assignment** | No CVE assigned as of February 2026 |

---

## How It Works

Based on the discoverer's public posts, the vulnerability is a stack-based buffer overflow:

1. The fastboot `oem ramdump` command accepts a parameter (normally a memory region specification)
2. The handler copies this parameter to a stack buffer without adequate bounds checking
3. By providing an oversized parameter, the attacker overflows the stack buffer
4. This overwrites the return address on the stack
5. The subsequent `fastboot oem uefilog` command triggers the corrupted return, redirecting execution
6. With a carefully crafted payload, this achieves arbitrary code execution in the bootloader context (EL1/EL3)

The overflow occurs at **offset 0x1950** in the ramdump handler function. The exact exploitation depends on the bootloader version and memory layout.

---

## Demonstrated Devices

The discoverer has publicly demonstrated or claimed unlocking on the following devices:

| Device | SoC | Status |
|--------|-----|--------|
| Xiaomi 13 | Snapdragon 8 Gen 2 | Demonstrated |
| Xiaomi 14 | Snapdragon 8 Gen 3 | Demonstrated |
| Xiaomi 15 | Snapdragon 8 Elite | Demonstrated |
| Xiaomi 17 | (2025 SoC) | Claimed |
| Redmi K90 | (2025 SoC) | Claimed |
| Redmi K80 Pro | Snapdragon 8 Gen 3 | Claimed |

**Note:** All demonstrated devices are Xiaomi/Redmi phones. No smart display, IoT, or Facebook/Meta devices have been tested publicly.

---

## Portal Relevance

### Why This Might Work on Portal

1. The APQ8098 is a Qualcomm SoC (Snapdragon 835 family)
2. The vulnerability is claimed to affect a "vast majority" of Qualcomm SoCs
3. The fastboot implementation on Qualcomm devices shares significant code across SoC families
4. The Portal Gen 1's bootloader is frozen at an old version (pre-2020), making it less likely to be patched

### Why This Might NOT Work on Portal

1. The Portal's fastboot may not implement the `oem ramdump` command at all
2. Facebook may have customized the fastboot implementation and removed or modified the ramdump handler
3. Although APQ8098 (SD835) is a phone-focused SoC, Facebook may have stripped phone-specific fastboot commands
4. The specific offset (0x1950) and memory layout will differ from the demonstrated Xiaomi devices
5. Even if the overflow works, the exploit payload (ROP chain, shellcode) must be crafted specifically for the Portal's bootloader binary

### How to Test

Run the OEM command test script to determine if the Portal's fastboot exposes the `oem ramdump` command:

```bash
./scripts/fastboot/test_oem_commands.sh
```

This script sends various `fastboot oem` commands and records which ones are recognized (even if they return errors) versus which ones are completely unknown. If `oem ramdump` is recognized, the device's fastboot handler has the ramdump code path, and the vulnerability may be exploitable.

**IMPORTANT:** The test script does NOT attempt to exploit the vulnerability. It only checks for command recognition. Actually triggering the overflow with an oversized parameter could crash the bootloader and require a manual reboot.

---

## Related Work

### CVE-2021-1931 and the `xperable` Tool

A related but distinct vulnerability in Qualcomm's fastboot handler:

| Attribute | Details |
|-----------|---------|
| **CVE** | CVE-2021-1931 |
| **Type** | Buffer overflow in fastboot |
| **Target SoC** | SDM845 (Snapdragon 845) |
| **Tool** | `xperable` (public exploit tool) |
| **Result** | Full bootloader unlock on affected Sony Xperia devices |

The `xperable` tool demonstrates that fastboot buffer overflows on Qualcomm SoCs can lead to full bootloader unlocks. The approach:

1. Trigger the buffer overflow in fastboot mode
2. Use ROP (Return-Oriented Programming) to chain together existing code gadgets in the bootloader
3. The ROP chain calls internal functions to:
   - Disable secure boot verification
   - Set the "unlocked" flag in the device state
   - Enable ADB
4. Reboot with an unlocked bootloader

If the 2025 ramdump 0-day is exploitable on APQ8098, a similar approach could be developed for the Portal. However, this requires:
- A dump of the Portal's bootloader binary (available from firmware dumps)
- ARM64 reverse engineering skills to find ROP gadgets
- Understanding of the Portal's specific lock/unlock mechanism

---

## Current Status — RESOLVED (2026-02-26)

### Tested Results
- **`oem ramdump` → "unknown command"** — Facebook stripped this from their ABL
- **`oem uefilog` → "unknown command"** — also stripped
- **`oem set-gpu-preemption` → not tested (almost certainly absent)**
- The 2026 ramdump 0-day is **NOT applicable** to the Facebook Portal 10"
- No public exploit code has been released for any device
- Stack canary protections block independent reproduction on affected devices

### What We Now Know
- Facebook's ABL has an extremely minimal command set (only 2 OEM commands)
- The Portal's fastboot does NOT implement any of the vulnerable OEM commands
- `getvar` overflow (>502 bytes) does NOT cause a hang — tested up to 16KB
- The DMA buffer IS active and accepting large payloads (`fastboot stage 15MB` succeeds)
- CVE-2021-1931 (older, different vulnerability) is a more promising path for the Portal

### Primary Path Forward: CVE-2021-1931
The older CVE-2021-1931 (ABL fastboot buffer overflow, not ramdump-specific) is now the primary exploit path:
1. USB DMA overflow confirmed exploitable on MSM8998 (j4nn/xperable)
2. Portal's APQ8098 uses the same ABL codebase
3. Portal is unpatched (Aug 2019 < Jul 2021 fix)
4. DMA buffer confirmed active on Portal
5. **BLOCKER: Need ABL binary** (not in firmware dump)

See: `journal/006_exploit_research.md` for full analysis

---

## Status Updates

**February 26, 2026 (UPDATED):**
- `oem ramdump` → **NOT PRESENT** — vector CLOSED
- `getvar` overflow → **NOT VULNERABLE** up to 16KB — vector CLOSED
- DMA buffer → **ACTIVE**, accepts 15MB+ payloads
- `fastboot boot` → **STRIPPED** from ABL (unknown command after successful download)
- Full enumeration completed: 64 partitions mapped, 50+ commands tested
- CVE-2021-1931 is now the primary exploit path
- ABL binary remains the critical missing piece

**February 2026 (initial):**
- Initial documentation created
- No public exploit code available
- Portal `oem ramdump` support status: UNTESTED

---

*See also: `journal/005_fastboot_breakthrough.md` (Session 2) for complete fastboot enumeration data.*
