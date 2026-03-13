# Guide 06: Modifying boot.img to Enable ADB

| Risk Level | Time Estimate | Prerequisites |
|------------|---------------|---------------|
| **ZERO** when working offline | 30 minutes offline work | A `boot.img` file from your backup |
| **HIGH** when flashing to device | 5 minutes to flash | EDL mode + firehose + full backup (Guide 05) |

---

## What This Does

This guide walks you through modifying the Portal's `boot.img` to enable ADB (Android Debug Bridge). ADB is the standard Android debugging tool that lets you connect to the device from your Mac, run commands, install apps, and transfer files.

On retail Portal units, ADB is completely disabled. The boot image contains property flags that explicitly turn it off. By modifying these flags, we can create a boot image that (if accepted by the bootloader) will enable ADB access.

### What Gets Changed

The following Android system properties are modified in the boot image's ramdisk:

| Property | Original Value | Modified Value | Purpose |
|----------|---------------|----------------|---------|
| `ro.debuggable` | `0` | `1` | Marks the build as debuggable |
| `ro.adb.secure` | `1` | `0` | Disables ADB authentication requirement |
| `ro.secure` | `1` | `0` | Disables secure mode restrictions |
| `persist.sys.usb.config` | `mtp` (or similar) | `mtp,adb` | Adds ADB to the USB configuration |

---

## Prerequisites

Before you begin, make sure you have:

- [ ] A complete backup from Guide 05 (specifically `boot.bin`)
- [ ] The project scripts installed (see Guide 00)
- [ ] `mkbootimg` / `unpackbootimg` tools available (installed via Guide 00)

---

## Step-by-Step Instructions

### Step 1: Unpack the Boot Image

Copy your backed-up boot image into the working directory and unpack it:

```bash
./scripts/boot_img/unpack_boot_img.sh scripts/boot_img/work/boot.img
```

This extracts the boot image into its component parts:

- **Kernel** -- the Linux kernel binary
- **Ramdisk** -- the initial root filesystem (this is what we modify)
- **Device tree** -- hardware configuration data
- **Boot parameters** -- kernel command line, addresses, etc.

You should see output confirming successful extraction.

### Step 2: Review Current Properties

Before making changes, review the current property values to understand what you are starting with:

```bash
cat scripts/boot_img/work/ramdisk_extracted/default.prop
```

You should see something like:

```
ro.debuggable=0
ro.adb.secure=1
ro.secure=1
persist.sys.usb.config=mtp
...
```

These are the values that lock out ADB access on retail units.

### Step 3: Modify the Properties

First, do a dry run to see what would change without actually modifying anything:

```bash
./scripts/boot_img/modify_props.sh --dry-run
```

Review the output carefully. It should show exactly which lines will be changed and what the new values will be.

When you are satisfied, run the modification for real:

```bash
./scripts/boot_img/modify_props.sh
```

### Step 4: Repack the Boot Image

Rebuild the boot image with the modified ramdisk:

```bash
./scripts/boot_img/repack_boot_img.sh
```

This creates a new boot image that is identical to the original except for the modified properties in the ramdisk.

### Step 5: Verify the Modified Boot Image

Run the verification script to confirm the modification was applied correctly:

```bash
./scripts/boot_img/verify_boot_img.sh
```

This should confirm:

- The image is a valid Android boot image
- The ramdisk contains the modified property values
- The image size is reasonable (similar to the original)
- The image structure is intact

### Step 6: Locate Your Modified Image

The modified boot image is saved at:

```
scripts/boot_img/work/modified_boot.img
```

This file is what you will flash to the device in Guide 07. **Do not overwrite your original backup.**

---

## Important Warning

**Flashing the modified boot.img to your device is a HIGH RISK operation.**

Here is why:

1. **Secure Boot verification**: The Portal's bootloader verifies the cryptographic signature of the boot image before loading it. A modified boot image will have a different hash, which may cause the bootloader to reject it entirely.

2. **Boot loop risk**: If the bootloader rejects the modified image, the device will enter a boot loop (repeatedly trying and failing to boot). You will need to use EDL mode and your backup to recover.

3. **vbmeta dependency**: You will almost certainly need to also flash a modified `vbmeta` image with verification disabled (covered in Guide 07). Without this, even a correctly modified boot image will be rejected.

4. **No guarantees**: Even with vbmeta verification disabled, the bootloader may have additional checks that prevent modified images from running.

---

## Understanding the Boot Image Structure

For those who want to understand what is happening under the hood:

```
boot.img
  |-- header (boot image metadata: kernel size, ramdisk size, addresses)
  |-- kernel (compressed Linux kernel)
  |-- ramdisk (compressed cpio archive)
  |     |-- init (the first process)
  |     |-- default.prop (system properties -- THIS IS WHAT WE MODIFY)
  |     |-- init.rc (init scripts)
  |     |-- sbin/ (essential binaries including adbd)
  |     |-- ...
  |-- device_tree (hardware description)
```

The `default.prop` file in the ramdisk is read very early in the boot process, before the system partition is mounted. This is why modifying it can enable ADB even when the system partition has verification enabled.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "unpack failed" error | Make sure the boot image is a valid Android boot image. Verify with `file scripts/boot_img/work/boot.img`. |
| `default.prop` not found in ramdisk | The ramdisk structure may differ. Look for `prop.default` or check subdirectories. |
| Repacked image is much larger/smaller than original | Something went wrong during repack. Start over from a fresh copy of the backup. |
| Verification script reports errors | Do not flash a boot image that fails verification. Start over from Step 1. |

---

## What You Should Have After This Guide

- [ ] An unpacked and inspected original boot image
- [ ] A modified `default.prop` with ADB-enabling properties
- [ ] A repacked `modified_boot.img` at `scripts/boot_img/work/modified_boot.img`
- [ ] Verification that the modified image is structurally valid
- [ ] Understanding that flashing this image carries significant risk

---

*Next: Guide 07 -- Flashing Modified Images*
