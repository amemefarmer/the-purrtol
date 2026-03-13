# Experiment 004: Firehose Loader Search & Strategic Pivot

**Date:** 2026-02-24
**Duration:** ~30 minutes
**Risk Level:** ZERO (research only)
**Outcome:** No firehose loader found anywhere. Strategy pivots to browser/BT exploit chain.

---

## Context

After confirming that fastboot is unreachable via hardware buttons (journal 002-003), the firehose loader became the critical path. Without it, we cannot:
- Read/write eMMC partitions via EDL
- Write BCB to misc partition to trigger fastboot
- Flash modified boot.img or ABL

## Search Scope

Searched exhaustively across:
1. bkerler/Loaders repository (835+ files)
2. temblast.com loader database (1763 loaders)
3. hoplik/Firehose-Finder (357 files)
4. hovatek.com collection
5. XDA Forums (16+ pages of Portal thread)
6. 4pda.to forums
7. Aleph Security firehorse framework
8. Qualcomm leaked collections
9. Telegram channels (android_dumps)

## Result: NO LOADER EXISTS

**No Facebook Portal / APQ8098 (OEM_ID 0x0137) firehose loader exists in any public repository.**

Key reasons:
- Facebook/Meta devices use proprietary signing keys never leaked
- APQ8098 (MSM_ID `0x000620e1`) is distinct from MSM8998 (`0x0005e0e1`) — even loaders for other SD835 devices have the wrong MSM_ID
- Secure boot strictly enforces OEM_ID + PK_HASH matching — cross-OEM loaders are rejected
- The firehose programmer isn't stored on the device's eMMC — it exists only on Facebook's build servers

## bkerler/edl Loader System

The Loaders directory at `~/portal-tools/edl/Loaders/` is empty (submodule not initialized). Even if initialized, no matching loader would be found.

**Expected filename:** `0620e10137b8a1_7291ef5c5d99dc05_FHPRG.bin`

**Loader search order in edl:**
1. Exact HWID + PK_HASH match
2. MSM_ID + PK_HASH match
3. Fallback for unfused devices (not applicable — our device is fused)

## Sahara-Only Operations (What We CAN Do Without Firehose)

```bash
edl secureboot        # ✅ Already done — got device identity
edl pbl pbl.bin       # ⚠️ May work — dumps PBL from memory
edl peekhex <addr> <size>  # ⚠️ May work — raw memory reads
edl qfp qfp.bin      # ⚠️ May work — QFPROM fuse dump
```

These don't require a firehose loader. The PBL dump and fuse dump could provide useful intelligence.

---

## Viable Attack Paths (Ranked)

### Path 1: Chrome/Browser Exploit Chain ⭐ MOST PROMISING
- Portal runs **Chrome 121** (based on community reports, ~Jan 2024)
- Multiple 2024 CVEs affect Chrome 121: CVE-2024-2887, etc.
- Attack flow: Navigate Portal's browser to exploit page → sandbox escape → kernel exploit → root shell → enable ADB
- **No physical access to bootloader needed**
- Requires: crafting/finding a working exploit for Chrome 121 on Android 9 / ARM64
- XDA user harrylepothead proposed this in July 2025

### Path 2: Bluetooth RCE (CVE-2020-0022) ⭐ PROMISING
- Security patch is August 2019, well before the February 2020 fix
- Android 9 Bluetooth is vulnerable to remote code execution
- Attack flow: Pair with Portal via BT → send exploit payload → gain code execution → enable ADB
- marcel505 on XDA reported Portal disconnects BT before payload completes, but may not be fully exhausted
- Requires: BT proximity, custom exploit adaptation for APQ8098

### Path 3: CVE-2021-1931 ABL Fastboot Exploit
- APQ8098 is confirmed vulnerable (patch Aug 2019, fix Jul 2021)
- j4nn's "xperable" exploit demonstrates this on Sony Xperia (also MSM8998)
- **Blocked by:** Can't reach fastboot to deliver the exploit
- Could become viable IF we get fastboot access via another method

### Path 4: Contact Developer Unit Owners
- **marcel505** has dev/unlocked Portal on XDA
- **Leapon** has dev Portal+ with root
- Either could dump ABL/XBL partitions: `dd if=/dev/block/bootdevice/by-name/abl_a of=/sdcard/abl_a.img`
- ABL dump would enable CVE-2021-1931 reverse engineering
- XBL dump could reveal signing chain information

### Path 5: Kernel Exploit (CVE-2019-2215)
- "Bad Binder" use-after-free, affects Android 9 kernel
- Portal's security patch (Aug 2019) predates the October 2019 fix
- Would need code execution context first (e.g., from browser or BT exploit)
- Useful as privilege escalation step in a chain

### Path 6: PMIC RESIN Hardware Mod
- Open device, find PM8998 RESIN pad, wire to button or jumper
- Would enable fastboot entry via hardware
- Risk: physical damage, voiding any possibility of return
- Last resort option

---

## Recommended Next Steps

1. **Try PBL dump and QFPROM read** — enter EDL mode and try `edl pbl` and `edl qfp`. These don't need firehose and could reveal useful data.

2. **Investigate Chrome version** — the Portal's built-in browser version is critical. If it's Chrome 121 or earlier, browser exploits become the primary path.

3. **Post on XDA thread** — describe the button/RESIN finding and ask marcel505 or Leapon for ABL/XBL partition dumps.

4. **Research CVE-2020-0022 (BlueFrag)** — determine if there's a working PoC for Android 9 ARM64 that could be adapted.

5. **Research Chrome 121 exploits** — check for public PoCs for CVE-2024-2887 or other V8/Blink RCEs affecting Chrome 121.

---

*The project pivots from bootloader-level attacks (EDL/fastboot) to application-level attacks (browser/BT). The Portal's extremely outdated software is actually its biggest vulnerability.*
