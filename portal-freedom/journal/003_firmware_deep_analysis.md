# Experiment 003: Offline Firmware Deep Analysis

**Date:** 2026-02-24
**Duration:** ~45 minutes
**Risk Level:** ZERO (offline analysis only, no device interaction)
**Outcome:** SUCCESS — major findings about ADB gating, partition layout, button mapping, and HAL structure

---

## Objective

Perform deep offline analysis of the `aloha` firmware dump from dumps.tadiphone.dev to understand:
1. Full partition layout
2. How ADB is gated (what controls enable/disable)
3. Boot chain and bootloader partitions
4. Hardware button mapping
5. Facebook-proprietary HAL structure
6. Attack surface for enabling ADB or unlocking bootloader

## Source Material

- **Firmware dump:** `dumps.tadiphone.dev/dumps/facebook/aloha.git`
- **Branch:** `aloha_prod-user-9-PKQ1.191202.001-1041481900013050-prod-keys`
- **Size:** 4.4 GB, 5,438 files
- **Build date:** Tue Dec 3 17:33:09 PST 2024 (vendor build.prop)

---

## Key Findings

### 1. CRITICAL: ADB Gating Mechanism Discovered

ADB is controlled by the **bootloader** via a kernel command line parameter, NOT just by build properties.

**The chain:**
1. Bootloader (ABL) sets `ro.boot.force_enable_usb_adb` in kernel cmdline
2. Init scripts in `init.common.usb.rc` read this property
3. On `aloha_prod-user` builds, when `force_enable_usb_adb=0`:
   - `persist.vendor.usb.config` → `none`
   - `sys.usb.config` → `none`
   - `/sys/class/android_usb/android0/enable` → `0`
   - `adbd` is **stopped**
   - USB gadget is completely disabled

**Implication:** Even if we modify `ro.debuggable=1` in `prop.default`, the bootloader-level flag will **override** and disable ADB. To truly enable ADB, we need to EITHER:
- Modify the bootloader (ABL) to set `force_enable_usb_adb=1`
- Flash a modified boot.img that ignores the bootloader flag
- Change the build flavor from `aloha_prod-user` to `aloha_vendor-user` (which has ADB enabled!)

**Escape hatch found:** The init scripts have a special case:
```
on property:ro.vendor.build.flavor=aloha_vendor-user
    setprop persist.sys.usb.config adb
```
If `ro.vendor.build.flavor` is set to `aloha_vendor-user`, ADB is automatically enabled regardless of the bootloader flag. This is Facebook's internal development build flavor.

### 2. Complete Partition Layout (from fstab.aloha)

| Partition | Mount Point | Type | A/B | Notes |
|-----------|------------|------|-----|-------|
| system | / | ext4 | Yes (slotselect) | System-as-root, dm-verity |
| userdata | /data | ext4 | No | Encrypted (ICE), quota |
| modem | /vendor/firmware_mnt | vfat | Yes (slotselect) | Read-only |
| bluetooth | /vendor/bt_firmware | vfat | Yes (slotselect) | Read-only |
| dsp | /vendor/dsp | ext4 | Yes (slotselect) | Read-only |
| persist | /mnt/vendor/persist | ext4 | No | No trim |
| **xbl** | none | emmc | Yes (slotselect) | **Qualcomm eXtensible Boot Loader** |
| **rpm** | none | emmc | Yes (slotselect) | RPM firmware |
| **tz** | none | emmc | Yes (slotselect) | **TrustZone** |
| **devcfg** | none | emmc | Yes (slotselect) | Device config |
| **hyp** | none | emmc | Yes (slotselect) | Hypervisor |
| **pmic** | none | emmc | Yes (slotselect) | PMIC firmware |
| **abl** | none | emmc | Yes (slotselect) | **Android BootLoader** |
| **keymaster** | none | emmc | Yes (slotselect) | Keymaster TA |
| **cmnlib** | none | emmc | Yes (slotselect) | Common lib (32-bit) |
| **cmnlib64** | none | emmc | Yes (slotselect) | Common lib (64-bit) |
| misc | /misc | emmc | No | Boot control |
| sdcard | /storage/sdcard1 | vfat | No | External (if present) |

**Boot chain:** XBL → ABL → kernel (boot.img) → Android init

### 3. No Bootloader Binaries in Dump

The tadiphone dump does NOT include:
- `abl.elf` / `abl.img` (Android BootLoader)
- `xbl.elf` / `xbl.img` (eXtensible Boot Loader)
- `tz.img` extracted from device (the `tz.img` in the dump IS a valid ARM64 ELF — 1.8MB TrustZone image)

The `tz.img` IS present and contains:
- OEM_ID 0x0137 (Facebook) embedded in signing certificate
- QSEE Attestation Root CA chain
- SHA256 hash signing references

### 4. CRITICAL: Button Mapping — No Volume Down!

The device tree source (`06_dtbdump_Facebook,_Inc._-_Aloha_PVT1.0.dts`) reveals the Portal 10" (Aloha) has only **two GPIO keys**:

| Button | Label | Linux Key Code | GPIO |
|--------|-------|---------------|------|
| Top button (near edge) | `volume_up` | `0x73` (KEY_VOLUMEUP = 115) | PMIC GPIO 6 |
| Second button | `volume_mute` | `0x71` (KEY_MUTE = 113) | PMIC GPIO 5 |

**There is NO `volume_down` key defined.** The button we assumed was "Vol Down" is actually the **mute/privacy** button (KEY_MUTE).

**Impact on fastboot entry:**
- XDA instructions say "hold Vol Down" — but **Portal 10" has no Vol Down**
- The correct key combo for fastboot might be Vol Up + Power, or Mute + Power, or a different combination entirely
- This explains why all our fastboot entry attempts failed

### 5. Facebook Proprietary HALs

From `manifest.xml`, the device has 8 Facebook-specific HAL services:

| HAL | Purpose |
|-----|---------|
| `vendor.facebook.hardware.alohamanagervendor@1.0` | Message cache (JSON-based, `/mnt/vendor/persist/aloha/recv_msg.json`) |
| `vendor.facebook.hardware.bluetoothanalyticshidl@1.0` | Bluetooth analytics/telemetry |
| `vendor.facebook.hardware.fwanalytics@1.0` | Firmware analytics engine |
| `vendor.facebook.hardware.installkeybox@1.2` | DRM key provisioning (PlayReady, HDCP1/2, Widevine) |
| `vendor.facebook.hardware.ledanimation@1.0` | LED animation control |
| `vendor.facebook.hardware.privacystate@1.0` | Privacy state management (camera/mic kill switch) |
| `vendor.facebook.hardware.thermalnotifier@1.0` | Thermal notifications |
| `vendor.facebook.hardware.virtualcameramanager@1.0` | Virtual camera management |

### 6. USB Configuration

- **Normal mode VID/PID:** `0x2ec6` (Facebook) / `0x1801` (ADB product ID, from `init.aloha.rc`)
- **Recovery mode VID/PID:** `0x18d1` (Google) / `0xD001`
- **Accessory mode VID/PID:** `0x18d1` / `0x2d00`
- **USB controller:** `a800000.dwc3` (DWC3 USB controller)
- **Default USB config:** `none` (ADB disabled by default on prod builds)

### 7. Display & Touch

- **Display:** WQHD panel, 160 DPI (`TARGET_SCREEN_DENSITY := 160`)
- **Panel backlight:** `panel0-backlight` (range with SW brightness control)
- **Touch controller:** I2C address `5-0034` (firmware update via sysfs `check_fw`)
- **Audio:** Knowles DSP (SPI bus `spi2.0`), Waves audio processing

### 8. OTA Update Payload Key

The OTA update verification public key is stored at:
`boot/ramdisk/etc/update_engine/update-payload-key.pub.pem`

This is a 2048-bit RSA public key. If we could sign an OTA payload with the corresponding private key, we could push an update through the normal update_engine path. However, the private key is held by Facebook/Meta.

### 9. Build Flavors

From init scripts, the firmware supports multiple build flavors:
- `aloha_prod-user` — Production Portal 10" (ADB disabled, our unit)
- `aloha_vendor-user` — Development Portal 10" (**ADB enabled!**)
- `ripley_prod-user` — Production Portal TV (ADB disabled)
- `ripley_vendor-user` — Development Portal TV (**ADB enabled!**)

### 10. Ramdump Infrastructure

The device has full Qualcomm ramdump support:
- `/dev/block/bootdevice/by-name/ramdump` partition exists
- `/sys/kernel/dload/emmc_dload` controls eMMC dump mode
- `/sys/kernel/dload/dload_mode` controls download mode
- `/sys/module/msm_poweroff/parameters/download_mode` controls crash download mode
- `persist.vendor.sys.enable_ramdumps=0` (disabled in prod)
- `subsystem_ramdump` binary in vendor/bin

When ramdumps are enabled (`persist.vendor.sys.enable_ramdumps=1`):
- `download_mode` is set to 1
- `emmc_dload` is set to 1
- All subsystem restart levels set to "system" (full system crash = ramdump)

---

## Attack Surface Analysis

### Path 1: Modified boot.img (Requires unlocked bootloader or EDL write)
**Target:** Change `ro.vendor.build.flavor` from `aloha_prod-user` to `aloha_vendor-user`
**Effect:** ADB auto-enabled
**Difficulty:** HIGH — requires either unlocked bootloader or EDL with firehose to flash

### Path 2: Bootloader (ABL) modification
**Target:** Change `ro.boot.force_enable_usb_adb` from 0 to 1
**Effect:** ADB enabled even on prod builds
**Difficulty:** VERY HIGH — ABL is signed, would need to disable verified boot

### Path 3: Persist partition modification
**Target:** Write `persist.sys.usb.config=adb` to persist partition
**Effect:** Might enable ADB on next boot (if not overridden by init scripts)
**Difficulty:** MEDIUM — persist partition is not A/B, accessible via EDL if we had firehose

### Path 4: Recovery mode with ADB
**Target:** Boot into recovery mode (which has ADB enabled with root!)
**Effect:** Get root shell in recovery
**Difficulty:** UNKNOWN — recovery init.rc enables ADB on `ro.debuggable=1`, but prod build has `ro.debuggable=0`
**Note:** Recovery mode USB identity uses Google VID (`0x18d1`), not Facebook

### Path 5: Ramdump exploitation
**Target:** Enable ramdumps, trigger crash, dump memory via EDL/Sahara
**Effect:** Could extract encryption keys, bootloader state
**Difficulty:** HIGH — ramdumps disabled in prod, would need property modification first

### Path 6: Fastboot with correct buttons
**Target:** Enter fastboot using correct button combination (NOT Vol Down — try Mute + Power or Vol Up + Power)
**Effect:** Access fastboot commands, test OEM unlock mechanism
**Difficulty:** LOW — just need to find the right combo
**NEW INSIGHT:** All previous attempts used the wrong button

---

## Next Steps

1. **Try fastboot with CORRECT buttons:**
   - Mute (privacy) button instead of Vol Down
   - Vol Up + Power
   - Both buttons + Power
   - Try each combo with wall power plugging sequence

2. **Search for ABL/XBL in other firmware dumps:**
   - Check `atlas` (Gen 2) dump for bootloader binaries
   - These might be structurally similar enough to understand the command table

3. **Analyze the tz.img further:**
   - The TrustZone binary might contain unlock challenge-response code
   - Look for QSEE TrustZone apps (TAs) related to bootloader unlock

4. **Research `aloha_vendor-user` build:**
   - If we could change just the build flavor property, ADB would be enabled
   - This property might be patchable in boot.img's prop.default

5. **Investigate recovery mode:**
   - Recovery has ADB with root shell (`--root_seclabel=u:r:su:s0`)
   - But only activates on `ro.debuggable=1`
   - Could recovery be entered without modifying the property?

---

*The mute button / Vol Down confusion is potentially the single biggest blocker we've had. All fastboot entry attempts used the wrong button.*
