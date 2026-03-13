# APQ8098 (Snapdragon 835) SoC Reference — Portal Gen 1

> **CORRECTION (2026-02-24):** Our initial research indicated the Portal Gen 1 used QCS605. EDL/Sahara interrogation has **confirmed the actual SoC is APQ8098 (Snapdragon 835)**. This document has been updated accordingly.

---

## Overview

| Attribute | Details |
|-----------|---------|
| **Full Name** | Qualcomm APQ8098 |
| **Marketing Name** | Snapdragon 835 (no-modem variant) |
| **Related Chips** | MSM8998 (same die, with LTE modem) |
| **Process Node** | 10nm Samsung 10LPE |
| **CPU Cores** | Octa-core: 4x Kryo 280 Gold (A73-based, up to 2.45 GHz) + 4x Kryo 280 Silver (A53-based, up to 1.9 GHz) |
| **GPU** | Adreno 540 |
| **DSP** | Hexagon 682 |
| **ISP** | Spectra 180 (dual 14-bit ISP) |
| **Modem** | None (APQ variant; MSM8998 has X16 LTE) |
| **Memory** | LPDDR4X, up to 8 GB |
| **Storage** | eMMC 5.1 (APQ8098 default per bkerler config) |
| **Target Market** | Flagship smartphones (2017-2018), smart displays |
| **Security Generation** | secgen 7 (per bkerler/edl qualcomm_config.py) |

---

## Confirmed Device Identity (from EDL/Sahara)

These values were read directly from the Portal Gen 1 on 2026-02-24:

| Field | Value | Notes |
|-------|-------|-------|
| **HWID** | `0x000620e10137b8a1` | Full hardware identifier |
| **MSM_ID** | `0x000620e1` | Maps to APQ8098 in Qualcomm config |
| **OEM_ID** | `0x0137` | Facebook/Meta (decimal: 311) |
| **MODEL_ID** | `0xb8a1` | Portal Gen 1 10" (ohana) |
| **CPU** | `APQ8098` | Snapdragon 835 (no modem) |
| **PK_HASH** | `0x7291ef5c5d99dc05ee00237a1d71b1f572696870b839bb715fba9e89988b4a3f` | Facebook's signing key hash |
| **Serial** | `0x6bb67469` | Device serial number |
| **Sahara Version** | 2 | Protocol version |
| **Storage** | eMMC | Per Qualcomm config for APQ8098 |

**Firehose loader needed:**
```
000620e10137b8a1_7291ef5c5d99dc05_FHPRG.bin
  or
000620e10137b8a1_7291ef5c5d99dc05_ENPRG.bin
```

---

## SoC Family Relationships

APQ8098 is part of the Snapdragon 835 family. This is significant because SD835 was used in dozens of flagship phones, creating a **much larger attack surface** and community of researchers:

```
MSM8998 / APQ8098 (Snapdragon 835) Family
  |
  |-- MSM8998 (with X16 LTE modem) -- Galaxy S8, Pixel 2, OnePlus 5/5T, Essential PH-1
  |-- APQ8098 (no modem) -- Facebook Portal Gen 1, Portal+, Portal TV (WiFi-only devices)
  |
  Shared components:
  - Kryo 280 CPU cores (A73+A53 based)
  - Adreno 540 GPU
  - Hexagon 682 DSP
  - Spectra 180 ISP
  - Same PBL ROM code
  - Same Sahara/Firehose EDL protocol
  - Security generation 7

Previously incorrectly assumed:
  QCS605 / SDM670 / SDM710 Family (Snapdragon 710)
  - DIFFERENT chip entirely (MSM_ID: 0x0AA0E1)
  - Kryo 360 cores, Adreno 615 GPU
  - NOT what the Portal Gen 1 uses
```

**Practical significance:** When searching for firehose programmers, exploits, or documentation:
- Search for **MSM8998** and **APQ8098** (same silicon, different modem config)
- Do NOT search for QCS605/SDM670/SDM710 — those are different chips
- SD835 phone hacking communities (Galaxy S8, Pixel 2, OnePlus 5, Essential PH-1) are relevant
- The Aleph Security EDL research specifically targeted MSM8998/APQ8098

---

## Devices Using APQ8098 / MSM8998

| Device | Manufacturer | SoC Variant | Notes |
|--------|-------------|-------------|-------|
| **Portal 10" Gen 1** | Facebook/Meta | APQ8098 | **Our target device** |
| **Portal+ Gen 1** | Facebook/Meta | APQ8098 | Same family, larger display |
| **Portal TV** | Facebook/Meta | APQ8098 | Same SoC, no display |
| Galaxy S8 / S8+ | Samsung | MSM8998 | Very large hacking community |
| Pixel 2 / 2 XL | Google | MSM8998 | Well-documented boot chain |
| OnePlus 5 / 5T | OnePlus | MSM8998 | Active custom ROM scene |
| Essential PH-1 | Essential | APQ8098 | Same MSM_ID, different OEM key |
| HTC U11 | HTC | MSM8998 | |
| Sony Xperia XZ Premium | Sony | MSM8998 | |

All MSM8998 devices share the same MSM_ID (0x000620e1) but have different OEM_IDs and PK hashes. A firehose signed for Samsung will NOT work on the Portal, but research and exploits targeting the PBL ROM (which is identical across all variants) are applicable.

---

## Security Architecture

### Qualcomm Secure Boot Chain

```
1. PBL (Primary Bootloader)
   |-- Burned into SoC ROM (cannot be modified)
   |-- Contains EDL (Emergency Download) mode
   |-- Contains Sahara protocol handler
   |-- Validates and loads XBL (eXtensible Boot Loader)
   |
2. XBL (eXtensible Boot Loader)
   |-- Stored in eMMC flash
   |-- Signed and verified by PBL
   |-- Initializes DRAM, peripherals, storage
   |-- Loads ABL (Android Boot Loader)
   |
3. ABL (Android Boot Loader / aboot)
   |-- Implements fastboot protocol
   |-- Handles bootloader lock/unlock
   |-- Loads boot.img (kernel + ramdisk)
   |
4. Linux Kernel + Android
   |-- dm-verity verifies system partition
   |-- Android Verified Boot (AVB) enforced
```

### TrustZone

- APQ8098 runs ARM TrustZone with QSEE (Qualcomm Secure Execution Environment)
- Sensitive operations run in the Secure World
- Multiple QSEE vulnerabilities have been found for SD835 by various researchers
- The PBL DRAM allocation address for APQ8098 is `0x00780350` (from qualcomm_config.py)

### Fuse-Based Hardware ID (HWID)

- OTP fuses encode HWID, PK Hash, and anti-rollback counters
- **Our PK_HASH:** `7291ef5c5d99dc05ee00237a1d71b1f572696870b839bb715fba9e89988b4a3f`
- Any firehose programmer must be signed with keys matching this hash
- Anti-rollback counters may prevent downgrading XBL/ABL even with a valid firehose

---

## EDL / Sahara Protocol (Confirmed Working)

### How EDL Works on APQ8098

Successfully tested on our Portal Gen 1 (2026-02-24):

1. Device enters EDL mode via button combo (Vol Down + Power on rear + USB connected)
2. Device appears as `QUSB__BULK` / QDLoader 9008 (VID:PID `05C6:9008`)
3. bkerler/edl connects via Sahara protocol (version 2)
4. Sahara command mode allows reading: Serial, HWID, PK Hash
5. **Without a matching firehose**, the tool cannot proceed to Firehose XML mode
6. Device stays in EDL mode for ~60-120 seconds before timing out

### Required for Full EDL Access

- Physical access to device in EDL mode ✅ (confirmed)
- A USB-C **data** cable (not charge-only!) ✅ (confirmed — first cable was charge-only)
- A **signed firehose programmer** matching HWID/PK hash ❌ (**NOT AVAILABLE**)
- bkerler/edl tool ✅ (installed and working)

### Sahara-Level Operations (No Firehose Required)

These commands work without a firehose and have been tested:
- `secureboot` — reads Sahara device info (HWID, serial, PK hash) ✅
- `pbl <filename>` — dumps Primary Bootloader ROM
- `qfp <filename>` — dumps QFPROM fuses
- `memorydump` — memory dump (if supported)

### Firehose-Level Operations (Require Signed Firehose)

These commands require a valid firehose programmer:
- `printgpt` — read partition table
- `r <partition> <file>` — read partition
- `rl <directory>` — read all partitions
- `w <partition> <file>` — write partition
- `getstorageinfo` — storage details

---

## Known CVEs Relevant to Portal Gen 1

### SD835/MSM8998-Specific Exploits

The Snapdragon 835 has a much larger body of security research than QCS605:

- **Aleph Security EDL Research (2018):** Foundational work on EDL programmer exploitation, specifically targeting MSM8998. Documents "peek and poke" vulnerability (ALEPH-2017028) in firehose programmers that allows arbitrary memory read/write.

- **CVE-2021-1931:** Fastboot buffer overflow in ABL. Basis for the `xperable` tool that unlocked SDM845 devices. May apply to APQ8098 with modification.

### The 2025 Ramdump 0-Day

- Stack overflow in `fastboot oem ramdump` handler
- Claimed to affect "vast majority of Qualcomm SoCs" — APQ8098 is likely in scope
- No public exploit code yet
- See `fastboot_0day_tracker.md` for tracking

### General Qualcomm CVEs (Post-August 2019)

Since Gen 1 firmware has security patches from August 2019, potentially unpatched vulnerabilities include:
- Various TrustZone (QSEE) vulnerabilities for SD835
- Multiple XBL vulnerabilities
- DSP (Hexagon 682) vulnerabilities
- The larger SD835 research community means MORE known vulnerabilities

---

## USB Identification

| Mode | USB VID:PID | USB Product Name | Status |
|------|-------------|------------------|--------|
| EDL/9008 | `05C6:9008` | `QUSB__BULK` | ✅ Confirmed |
| Fastboot | `18D1:D00D` | Android fastboot | Not yet tested |
| ADB | `18D1:4EE7` | Android ADB | Disabled on retail |
| Normal boot | — | Not detected on USB | Expected |

---

## Further Reading

- **Aleph Security:** "Exploiting Qualcomm EDL Programmers" — https://alephsecurity.com/2018/01/22/qualcomm-edl-1/
- **bkerler/edl:** https://github.com/bkerler/edl
- **bkerler/Loaders:** https://github.com/bkerler/Loaders (835 files, search for matching PK hash)
- **XDA Portal thread:** https://xdaforums.com/t/anyone-been-able-to-do-anything-with-a-facebook-portal.3878505/
- **XDA MSM8998 firehose thread:** https://xdaforums.com/t/looking-for-msm8998-firehose-programmer.3835615/
- **temblast.com loader database:** https://www.temblast.com/ref/loaders.htm
- **Qualcomm Security Bulletins** for SD835/MSM8998

---

*See also: `fastboot_0day_tracker.md`, `gen1_vs_gen2.md` (updated with SoC corrections)*
