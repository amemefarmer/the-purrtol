# Experiment 005: FASTBOOT MODE REACHED — BREAKTHROUGH!

**Date:** 2026-02-25
**Risk Level:** LOW (read-only fastboot queries on locked bootloader)
**Outcome:** SUCCESS — fastboot mode entered, full device info and unlock nonce captured!

---

## How Fastboot Was Reached

**METHOD: All three buttons (Power rear + Vol Up + Mute) held through multiple boot screens**

1. USB-C data cable connected to Mac
2. Wall power connected
3. Press and hold ALL THREE buttons simultaneously:
   - **Power** (rear, near bottom of device)
   - **Volume Up** (top edge)
   - **Mute/Privacy** (top edge)
4. Continue holding through multiple Portal screens (logo, etc.)
5. Eventually the device shows "Please Reboot..." — the fastboot indicator

**Key difference from earlier failed attempts:**
- Earlier we tried only 2 buttons at a time (Vol Up + plug power, Mute + plug power)
- The rear Power button was NOT included in the earlier attempts
- Holding through MULTIPLE screens was necessary (not releasing after first screen)
- This suggests the ABL checks for a multi-button combo, possibly Power+VolUp together

---

## Key Data Captured

### Device Identity
| Variable | Value |
|----------|-------|
| product | aloha |
| serialno | 818PGA02P110MQ09 |
| variant | **APQ UFS** |
| secure | yes |
| unlocked | no |
| current-slot | b |
| slot-count | 2 |
| kernel | uefi |
| max-download-size | 536870912 (512MB) |
| hw-revision | 20001 |
| hw-major | 0x05 |
| hw-minor | 0x01 |

### ⚠️ CRITICAL: Storage is UFS, NOT eMMC!

`variant: APQ UFS` — the Portal 10" Gen 1 uses **UFS storage**, not eMMC as we previously assumed! This changes the EDL firehose requirements (need UFS programmer, not eMMC).

### Security State
| Property | Value |
|----------|-------|
| Device unlocked | false |
| Device critical unlocked | false |
| Device unsealed | false |
| ADB allowed | false |
| Verity mode | true |

### 🔑 UNLOCK NONCE CAPTURED!

```
Unlock Request: D1B469083E0E08E5818PGA02P110MQ09
```

The nonce is: `D1B469083E0E08E5` followed by the serial number. This is the challenge in the challenge-response bootloader unlock mechanism.

### Complete Partition Table

**A/B partitions (has-slot: yes):**
- system_a/b: 0xC0000000 (3 GB each) — ext4
- vendor_a/b: 0xC0000000 (3 GB each)
- boot_a/b: 0x4000000 (64 MB each)
- modem_a/b: 0x6E00000 (112 MB each)
- abl_a/b: 0x100000 (1 MB each)
- xbl_a/b: 0x3D9000 (~3.8 MB each)
- tz_a/b: 0x200000 (2 MB each)
- rpm_a/b: 0x80000 (512 KB each)
- hyp_a/b: 0x80000 (512 KB each)
- pmic_a/b: 0x80000 (512 KB each)
- bluetooth_a/b: 0x100000 (1 MB each)
- dsp_a/b: 0x1000000 (16 MB each)
- keymaster_a/b: 0x80000 (512 KB each)
- cmnlib_a/b: 0x80000 (512 KB each)
- cmnlib64_a/b: 0x80000 (512 KB each)
- devcfg_a/b: 0x20000 (128 KB each)
- vbmeta_a/b: 0x10000 (64 KB each)
- oemtzg_a/b: 0x80000 (512 KB each)
- mdtp_a/b: 0x2000000 (32 MB each)
- mdtpsecapp_a/b: 0x400000 (4 MB each)

**Non-A/B partitions:**
- userdata: 0x429DD7000 (~16.6 GB) — ext4
- misc: 0x100000 (1 MB)
- frp: 0x80000 (512 KB)
- keystore: 0x80000 (512 KB)
- ssd: 0x2000 (8 KB)
- persist: 0x2000000 (32 MB)
- persist_bak: 0x2000000 (32 MB)
- splash: 0x20A4000 (~32 MB)
- storsec: 0x1BE4E000 (~446 MB)
- logdump: 0x4000000 (64 MB)
- various other small partitions

### OEM Commands Tested
| Command | Result |
|---------|--------|
| `oem device-info` | ✅ Works — shows unlock/verity state |
| `oem get_unlock_bootloader_nonce` | ✅ Works — returns nonce! |
| `oem help` | ❌ Unknown command |
| `oem ramdump enable` | ❌ Unknown command |
| `oem ramdump` | ❌ Unknown command |
| `oem get_unlock_ability` | ❌ Unknown command |
| `oem unlock` | ❌ Unknown command |
| `oem select-display-panel` | ❌ Unknown command |
| `oem enable-charger-screen` | ❌ Unknown command |

---

## Analysis

### The Unlock Mechanism
The nonce `D1B469083E0E08E5818PGA02P110MQ09` must be signed with Facebook/Meta's private key. The signed response would be sent back via a command like:
```
fastboot oem unlock_bootloader <signed_response>
```

Without Meta's signing key, the unlock cannot proceed through the official path.

### CVE-2021-1931 (ABL Fastboot Exploit) — NOW VIABLE!
**This is the game-changer.** With fastboot access confirmed:
- The device IS in fastboot mode
- We can send fastboot commands
- CVE-2021-1931 exploits a buffer overflow in the ABL's fastboot command parser
- The Portal's security patch (Aug 2019) predates the fix (Jul 2021)
- j4nn's "xperable" exploit for Sony Xperia demonstrates this on MSM8998
- We need to: (1) extract ABL from tadiphone dump or this device, (2) reverse engineer it, (3) adapt the exploit

### UFS vs eMMC Discovery
The `variant: APQ UFS` finding means:
- Previous assumption of eMMC was WRONG
- UFS (Universal Flash Storage) is faster and has different command interfaces
- EDL firehose programmers are different for UFS vs eMMC
- The firehose filename would include "ufs" not "emmc"

---

## Additional Findings (Second Round of Commands)

### Nonce is Randomized
- First call: `D1B469083E0E08E5818PGA02P110MQ09`
- Second call: `5362BF7B992BA33D818PGA02P110MQ09`
- The 16-char hex nonce changes each request, serial number appended

### Unlock Ability
- `fastboot flashing get_unlock_ability` → **0** (OEM unlock NOT enabled in settings)
- `fastboot flashing unlock` → "Flashing Unlock is not allowed"
- `fastboot oem unlock_bootloader` → unknown command (Facebook's custom unlock path)
- The device uses Facebook's proprietary challenge-response: `oem get_unlock_bootloader_nonce` + signed response

### Commands Summary
| Command | Result |
|---------|--------|
| `oem get_unlock_bootloader_nonce` | ✅ Returns randomized nonce |
| `oem device-info` | ✅ Shows lock/verity state |
| `flashing get_unlock_ability` | ✅ Returns 0 (locked) |
| `flashing unlock` | ❌ "Flashing Unlock is not allowed" |
| `oem unlock_bootloader` | ❌ Unknown command |
| `oem unlock` | ❌ Unknown command |
| `oem ramdump` / `oem ramdump enable` | ❌ Unknown command |
| `oem help` | ❌ Unknown command |
| `oem fb_mode_set` | ❌ Unknown command |
| `oem disable-verity` | ❌ Unknown command |

---

---

## Session 2 — Deep Enumeration (2026-02-26)

### getvar all — WORKS!
Despite returning "unknown command" in the previous session, `getvar all` worked this time
and returned the complete partition table + all variables. Saved to logs.

### Complete Partition Table (from getvar all)

**A/B partitions (19 partition pairs):**
| Partition | Size | Type |
|-----------|------|------|
| system_a/b | 0xC0000000 (3 GB) | ext4 |
| vendor_a/b | 0xC0000000 (3 GB) | raw |
| boot_a/b | 0x4000000 (64 MB) | raw |
| modem_a/b | 0x6E00000 (112 MB) | raw |
| mdtp_a/b | 0x2000000 (32 MB) | raw |
| dsp_a/b | 0x1000000 (16 MB) | raw |
| abl_a/b | 0x100000 (1 MB) | raw |
| bluetooth_a/b | 0x100000 (1 MB) | raw |
| xbl_a/b | 0x3D9000 (~3.8 MB) | raw |
| tz_a/b | 0x200000 (2 MB) | raw |
| mdtpsecapp_a/b | 0x400000 (4 MB) | raw |
| rpm_a/b | 0x80000 (512 KB) | raw |
| hyp_a/b | 0x80000 (512 KB) | raw |
| pmic_a/b | 0x80000 (512 KB) | raw |
| keymaster_a/b | 0x80000 (512 KB) | raw |
| cmnlib_a/b | 0x80000 (512 KB) | raw |
| cmnlib64_a/b | 0x80000 (512 KB) | raw |
| oemtzg_a/b | 0x80000 (512 KB) | raw |
| devcfg_a/b | 0x20000 (128 KB) | raw |
| vbmeta_a/b | 0x10000 (64 KB) | raw |

**Non-A/B partitions:**
| Partition | Size | Type |
|-----------|------|------|
| userdata | 0x429DD7000 (~16.6 GB) | ext4 |
| storsec | 0x1BE4E000 (~446 MB) | raw |
| splash | 0x20A4000 (~32 MB) | raw |
| persist | 0x2000000 (32 MB) | raw |
| persist_bak | 0x2000000 (32 MB) | raw |
| logdump | 0x4000000 (64 MB) | raw |
| dip | 0x100000 (1 MB) | raw |
| toolsfv | 0x100000 (1 MB) | raw |
| ddr | 0x100000 (1 MB) | raw |
| misc | 0x100000 (1 MB) | raw |
| logfs | 0x800000 (8 MB) | raw |
| fsc | 0x1D9000 (~1.8 MB) | raw |
| fsg | 0x200000 (2 MB) | raw |
| modemst1 | 0x200000 (2 MB) | raw |
| modemst2 | 0x200000 (2 MB) | raw |
| sti | 0x200000 (2 MB) | raw |
| keystore | 0x80000 (512 KB) | raw |
| frp | 0x80000 (512 KB) | raw |
| apdp | 0x40000 (256 KB) | raw |
| msadp | 0x40000 (256 KB) | raw |
| sec | 0x4000 (16 KB) | raw |
| ssd | 0x2000 (8 KB) | raw |
| devinfo | 0x1000 (4 KB) | raw |
| cdt | 0x1000 (4 KB) | raw |
| limits | 0x1000 (4 KB) | raw |
| dpo | 0x1000 (4 KB) | raw |

**Total: 38 A/B partitions + 26 non-A/B = 64 partitions**

### Slot State
| Slot | Retry Count | Unbootable | Successful |
|------|------------|------------|------------|
| a | 6 | no | yes |
| b | 6 | no | yes |

Both slots are healthy. Active slot: **b**.

### Additional Variables Discovered
| Variable | Value |
|----------|-------|
| hw-major | 0x05 |
| hw-minor | 0x01 |
| hw-revision | 20001 |
| kernel | uefi |
| erase-block-size | 0x1000 (4 KB) |
| logical-block-size | 0x1000 (4 KB) |
| version-bootloader | (empty) |
| version-baseband | (empty) |

### Buffer Overflow Testing
| Test | Result |
|------|--------|
| getvar 10-16000 bytes | All returned "Variable Not found" — **no hang/crash** |
| fastboot fetch boot_b | "Device does not support fetch command" |
| fastboot boot boot.img | Download 27MB OKAY, then "unknown command" |
| fastboot flash boot boot.img | Download 27MB OKAY, then "Flashing is not allowed" |
| fastboot stage 15MB | **OKAY** — accepted 15MB into DMA buffer |
| fastboot flash 15MB | Download 15MB OKAY, then "Flashing is not allowed" |

**Key finding:** `fastboot boot` command is **removed from this ABL** — "unknown command" after successful download. Facebook stripped it. `fastboot flash` exists but is blocked by lock state.

### USB DMA Buffer Behavior (CVE-2021-1931 relevant)
- `fastboot stage` accepts 15MB payloads without issue
- `max-download-size: 536870912` (512MB)
- Data transfer to device works — the DMA buffer is accepting data
- Device survives all large payloads without crash
- This confirms the USB DMA path is active and functional

### Unlock Command Discovery
- `oem unlock_bootloader [token]` — unknown command (no matching response command exists)
- `oem submit_unlock_bootloader_response` — unknown
- All 8 unlock response command variants — unknown
- `flashing unlock` (no args) — "not allowed" (recognized, blocked by ability=0)
- `flashing unlock [token]` — "unknown flashing command" (args not supported)
- `flashing unlock_critical` — "not allowed" (same as unlock)
- `flashing lock` — "Device already: locked!"
- `flashing lock_critical` — "Device already: locked!"

**Conclusion:** The `oem get_unlock_bootloader_nonce` generates nonces but there is NO visible command to submit a signed response. The unlock mechanism may be entirely server-side (Meta's factory provisioning tool) or the response path is hidden/obfuscated in the ABL binary.

### Extended OEM Command Scan
Tested 43+ additional OEM commands (get-token, set-token, dump, status, info, config,
reboot, edl, dload, recovery, crashdump, etc.) — **ALL returned "unknown command"**.
Facebook's ABL has an extremely minimal command set:
- `oem device-info` ✅
- `oem get_unlock_bootloader_nonce` ✅
- Everything else: ❌

---

## Next Steps

1. **Obtain ABL binary** — the CRITICAL blocker for CVE-2021-1931
   - Contact Marcel (@MarcelD505) for dev unit ABL dump
   - Search for OTA update packages that may include ABL
2. **Adapt xperable exploit** — once ABL is obtained
   - Extract LinuxLoader UEFI module with uefi-firmware-parser
   - Reverse engineer with Ghidra to find offsets
   - Build Portal-specific position-independent payloads
3. **Investigate the unlock mechanism** — reverse engineer ABL to find where the nonce response is processed (it's hidden from command line)

---

*Fastboot access is CONFIRMED and REPRODUCIBLE (3-button method). The CVE-2021-1931 ABL exploit is now the primary attack vector. The ABL binary is the only missing piece.*
