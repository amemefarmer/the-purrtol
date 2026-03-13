# Experiment 001: EDL Mode Entry + Sahara Device Query

**Date:** 2026-02-24
**Duration:** ~45 minutes (including troubleshooting)
**Risk Level:** LOW (read-only)
**Outcome:** SUCCESS — device identity fully confirmed

---

## Objective

Enter EDL (Emergency Download) mode on the Portal Gen 1 and read the device's hardware identity via the Sahara protocol.

## Equipment

- Facebook Portal 10" Gen 1 (2018), codename "ohana"
- Mac (Apple Silicon, macOS)
- USB-C to USB-C data cable (second cable — first was charge-only)
- Wall power adapter connected to Portal
- bkerler/edl v3.62 (installed at ~/portal-tools/edl/.venv)

## Procedure

### 1. USB Connection Troubleshooting

**Problem:** Initial USB-C cable did not carry data — device never appeared on USB.

**Resolution:** Swapped to a different USB-C cable. Data-capable cables work; charge-only cables do not expose the device on USB.

**Lesson learned:** Always verify your USB-C cable carries data. The Portal shows NO indication on its screen that EDL mode has been entered.

### 2. Button Identification

**Problem:** Initially pressed buttons on TOP of device (volume controls / privacy slider). These are NOT the power button.

**Resolution:** The power button is on the **REAR of the device, near the bottom**. This is critical for entering EDL mode.

Portal Gen 1 button layout:
- **Top edge:** Volume Up, Volume Down, privacy slider (NOT power)
- **Rear, near bottom:** Power button

### 3. EDL Mode Entry

**Steps that worked:**
1. Portal plugged into wall power (normal boot, showing Portal UI)
2. USB-C data cable connected between Mac and Portal
3. Hold **Vol Down** + **Power (rear)** simultaneously
4. Screen goes blank/black — no lights, no LED, no visual feedback
5. Device appears on USB as `QUSB__BULK` within ~2-3 seconds

**USB identification:**
```
USB Product Name: QUSB__BULK
idVendor: 1478 (0x05C6 — Qualcomm)
idProduct: 36872 (0x9008 — QDLoader 9008)
USB Vendor Name: Qualcomm CDMA Technologies MSM
```

### 4. Sahara Query

**Command:** `python edl.py secureboot --debugmode`

**Bug encountered:** bkerler/edl failed with `FileNotFoundError: logs/log.txt`. Fixed by creating `~/portal-tools/edl/logs/` directory.

**Another bug:** Initially tried `python edl.py info` which is NOT a valid subcommand. The correct command for Sahara-level queries is `secureboot`.

### Results

```
Version 0x2
------------------------
HWID:              0x000620e10137b8a1 (MSM_ID:0x000620e1,OEM_ID:0x0137,MODEL_ID:0xb8a1)
CPU detected:      "APQ8098"
PK_HASH:           0x7291ef5c5d99dc05ee00237a1d71b1f572696870b839bb715fba9e89988b4a3f
Serial:            0x6bb67469
```

**Post-query behavior:** The tool attempts to find a matching firehose loader. Since none exists for our HWID+PK_HASH combination (`000620e10137b8a1_7291ef5c5d99dc05_[FHPRG/ENPRG].bin`), it falls through to streaming mode, which also fails. The device remains in EDL mode during this process.

---

## Critical Discovery: SoC Identification

### Expected: QCS605 (Snapdragon 710 family)
### Actual: APQ8098 (Snapdragon 835)

**This is a major correction.** All prior research (including the deep_dive.md, XDA forums, and various teardown reports) assumed the Portal Gen 1 used a QCS605. The EDL/Sahara readout definitively proves it uses **APQ8098**, which is the no-modem variant of the **MSM8998 / Snapdragon 835**.

### Why This Matters

1. **Larger research community:** MSM8998/SD835 was used in Galaxy S8, Pixel 2, OnePlus 5/5T, Essential PH-1, HTC U11, and many more. This means far more security research, exploit development, and community tooling exists.

2. **Different chip family:** QCS605 (MSM_ID `0x0AA0E1`) is a completely different chip from APQ8098 (MSM_ID `0x000620e1`). Any tools, loaders, or exploits targeting QCS605 are NOT applicable.

3. **Aleph Security research:** The foundational EDL exploitation research by Aleph Security specifically targeted MSM8998/APQ8098. Their peek-and-poke vulnerability findings are directly relevant.

4. **Signing chain identified:** OEM_ID `0x0137` is Facebook/Meta's Qualcomm OEM identifier. All Facebook devices (Portal, Portal+, Portal TV Gen 1) likely share this OEM_ID and potentially the same PK_HASH.

5. **Firehose search pivoted:** Need to search for APQ8098/MSM8998 firehose programmers signed with Facebook's key (PK_HASH `7291ef5c...`), not QCS605 programmers.

---

## Files Updated

- `docs/research/qcs605_reference.md` → Completely rewritten as APQ8098 reference
- `docs/research/gen1_vs_gen2.md` → Updated with SoC correction
- `docs/research/hardware_id_guide.md` → Added EDL identity data
- `docs/adr/001_primary_approach.md` → Updated SoC reference
- `docs/adr/002_device_considerations.md` → Updated SoC comparison
- `scripts/edl/query_device_info.sh` → Fixed (was using invalid `edl info` command)
- `README.md` → Updated SoC reference
- `MEMORY.md` → Updated with all confirmed device data

## Next Steps

1. **Try fastboot mode** — enter fastboot (Vol Down + Power?), query all variables
2. **Probe OEM commands** — check for `oem ramdump` and other fastboot OEM commands
3. **Attempt PBL dump** — `python edl.py pbl pbl_dump.bin` while in EDL mode
4. **Search for APQ8098 firehose loaders** signed with Facebook's key in:
   - bkerler/Loaders repository (835 files)
   - temblast.com database
   - hoplik/Firehose-Finder
   - OneLabsTools/Programmers
5. **Contact XDA dev unit owner** about extracting xbl.elf or firehose from their dev Portal+
6. **Research PBL exploits** for SD835 that could bypass the signed-programmer requirement
