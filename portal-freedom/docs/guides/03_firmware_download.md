# Guide 03: Downloading Firmware for Offline Analysis

| | |
|---|---|
| **Risk Level** | ZERO -- downloading files to your Mac, no device interaction |
| **Estimated Time** | 30-90 minutes (depending on internet speed; these are multi-GB downloads) |
| **Prerequisites** | [Guide 00: Environment Setup](00_environment_setup.md) completed, 15 GB+ free disk space, internet connection |
| **Device Needed** | No |

---

## Overview

In this guide, you will download firmware dump files for the Facebook Portal Gen 1 to your Mac. These are complete system images that were previously extracted from Portal devices and shared publicly for research purposes.

**Why is this zero risk?** You are downloading files to your Mac. You do not need your Portal device at all. Everything in this guide happens entirely on your computer. Think of it like downloading a car manual -- reading the manual does not affect the car.

**Why bother?** Offline firmware analysis (covered in Guide 04) is the single most valuable zero-risk activity in this project. By studying the firmware files, you can learn exactly how the Portal works, what security measures are in place, and what would need to change to enable features like ADB -- all without ever touching the device.

---

## What You Are Downloading

Firmware dumps from `dumps.tadiphone.dev` contain the full set of partition images extracted from Portal devices. These typically include:

| File | What It Is |
|---|---|
| `boot.img` | The boot image containing the kernel and initial ramdisk (this is the most important file) |
| `system.img` | The main Android system partition |
| `vendor.img` | Vendor-specific drivers and configuration |
| `vbmeta.img` | Verified boot metadata (controls boot integrity checking) |
| `recovery.img` | Recovery mode image |
| Various others | Modem firmware, TrustZone images, other partitions |

You do not need to understand all of these right now. Guide 04 will walk you through analyzing the important ones.

---

## Device Codenames

Each Portal model has an internal codename. You will see these throughout the project:

| Codename | Device | Notes |
|---|---|---|
| **ohana** | Portal Gen 1 (2018) | **Your device** -- download this one first |
| **aloha** | Portal+ Gen 1 (2018) | Larger screen variant of Gen 1 |
| **atlas** | Portal Gen 2 | Newer generation, good for comparison |
| **terry** | Portal Go | Portable battery-powered variant |

---

## Step-by-Step Instructions

### Step 1: Check Available Disk Space

These firmware dumps are large (multiple gigabytes). Make sure you have enough room:

```bash
df -h .
```

Look at the "Avail" column. You need at least **15 GB** free. If you plan to download multiple device firmwares, budget **15 GB per device**.

You can also check from Finder: click the Apple menu > About This Mac > Storage.

### Step 2: Download the Ohana (Portal Gen 1) Firmware

Run the download script:

```bash
./scripts/firmware/download_firmware.sh ohana
```

This script clones the firmware repository into `tools/firmware/ohana/`. Because this is a git clone of a large repository, it may take a while depending on your internet connection.

You will see git progress output like:

```
Cloning into 'tools/firmware/ohana'...
remote: Enumerating objects: ...
remote: Counting objects: ...
Receiving objects:  XX% (XXXX/XXXX), X.XX GiB | X.XX MiB/s
```

**Be patient.** On a typical home internet connection, this can take 30-60 minutes or more. Do not interrupt the download.

> **Tip:** If the download fails partway through (due to a network interruption), you can usually resume by running the script again. Git will pick up where it left off if the partial clone directory exists.

### Step 3: Verify the Download

Once the clone completes, verify that the files are there:

```bash
ls tools/firmware/ohana/
```

You should see a list of `.img` files and possibly directories. The exact contents depend on the firmware version that was dumped.

### Step 4: Find the Boot Image

The boot image is the most important file for analysis. Locate it:

```bash
find tools/firmware/ohana -name "boot*"
```

You should see at least one file named `boot.img`. Note the full path -- you will need it in Guide 04.

If you see `boot_a.img` and `boot_b.img`, that means the device uses an A/B partition scheme (this is common on modern Android devices). Both are typically identical on a stock device; you can use either one.

### Step 5 (Optional): Download Additional Firmware

If you have the disk space, downloading the **atlas** (Gen 2) firmware is useful for comparison. Seeing how Facebook changed things between generations can reveal useful patterns:

```bash
./scripts/firmware/download_firmware.sh atlas
```

Other available codenames:

```bash
./scripts/firmware/download_firmware.sh aloha    # Portal+ Gen 1
./scripts/firmware/download_firmware.sh terry     # Portal Go
```

---

## Understanding the Directory Structure

After downloading, your firmware directory will look something like this:

```
tools/firmware/
    ohana/              <-- Portal Gen 1 firmware
        boot.img
        system.img
        vendor.img
        vbmeta.img
        recovery.img
        ... (other partition images)
    atlas/              <-- Portal Gen 2 firmware (if downloaded)
        boot.img
        system.img
        ...
```

Each `.img` file is a raw image of one partition from the device's flash storage. These are the exact bytes that exist on the device's internal storage.

---

## Troubleshooting

### "fatal: unable to access" or Network Errors

If git cannot reach the firmware repository:

1. Check your internet connection: `ping -c 3 github.com`
2. If you are behind a corporate firewall or VPN, try disconnecting from the VPN
3. If the repository is temporarily down, wait an hour and try again

### Download Is Extremely Slow

Firmware repositories are large. Some things to try:

- Use a wired Ethernet connection instead of Wi-Fi
- Download during off-peak hours
- If on a metered connection, be aware this may use several gigabytes of data

### "Not enough space" Errors

Free up disk space or download to an external drive:

```bash
# To use an external drive, create a symlink:
ln -s /Volumes/YourExternalDrive/portal-firmware tools/firmware
```

Make sure the external drive is formatted as APFS or HFS+ (not FAT32, which has a 4 GB file size limit).

### Download Was Interrupted

If the git clone was interrupted partway through:

```bash
# Remove the incomplete clone
rm -rf tools/firmware/ohana

# Start fresh
./scripts/firmware/download_firmware.sh ohana
```

Alternatively, if most of the data was transferred, you can try resuming:

```bash
cd tools/firmware/ohana
git fetch --all
git checkout main
```

---

## What You Have Now

After completing this guide, you have a complete copy of the Portal Gen 1 firmware sitting on your Mac's hard drive. These files are identical to what is stored on your Portal's internal flash memory.

You can now study every aspect of how the device works -- the kernel configuration, the Android system properties, the init scripts, the security settings -- all without ever connecting your Portal.

---

## What's Next?

The natural next step is the most valuable guide in this series:

- **[Guide 04: Offline Firmware Analysis](04_offline_firmware_analysis.md)** -- extract and study the boot image, understand the security model, find the exact properties that control ADB access

You can also revisit the device-interaction guides if you have not tried them yet:

- **[Guide 01: Entering EDL Mode](01_entering_edl_mode.md)** -- hardware diagnostic mode
- **[Guide 02: Entering Fastboot Mode](02_entering_fastboot_mode.md)** -- bootloader interface
