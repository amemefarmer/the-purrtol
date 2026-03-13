# Guide 08: Installing a Generic System Image (GSI)

| Risk Level | Time Estimate | Prerequisites |
|------------|---------------|---------------|
| **HIGH** | 1-4 hours | Unlocked bootloader with working ADB access |

---

## This Is the Endgame

This guide covers turning your Facebook Portal into a real Android tablet by flashing a Generic System Image (GSI). A GSI is a pre-built Android system image that works on any device supporting Project Treble (Android 8.0+). Since the Portal runs Android 9, it supports Treble.

**If you have reached this point with a working ADB connection and an unlockable bootloader, congratulations -- you are past the hardest part.**

---

## Prerequisites

Before you begin, make sure you have:

- [ ] A Portal with **working ADB access** (from Guide 07)
- [ ] An **unlocked bootloader** (or the ability to flash via EDL)
- [ ] A **complete backup** of all partitions (Guide 05)
- [ ] A **USB-C data cable** connected to your Mac
- [ ] At least **4 GB of free disk space** for the GSI download
- [ ] A **stable internet connection** for downloading the GSI

---

## Step-by-Step Instructions

### Step 1: Download a GSI

Get an ARM64 GSI from phhusson's GitHub (the most widely used GSI builds):

**URL:** `https://github.com/phhusson/treble_experimentations/releases`

**Which variant to download:**

- **Architecture**: `arm64` (the APQ8098/Snapdragon 835 is a 64-bit ARM processor)
- **Partition type**: Start with `A/B` (most Portal models use A/B partitions). If that does not work, try `A-only`.
- **GApps vs Vanilla**: Choose `vgapps` if you want Google Play Store pre-installed, or `vanilla` for a clean AOSP build without Google services.
- **Android version**: Android 13 or 14 GSIs are recommended for the best balance of compatibility and features.

The downloaded file will be a compressed image (`.img.xz` or `.img.gz`). Extract it:

```bash
# For .xz files
xz -d system-arm64-ab-vanilla.img.xz

# For .gz files
gunzip system-arm64-ab-gapps.img.gz
```

You should now have a `system.img` file (typically 1.5-3 GB).

### Step 2: Reboot to Bootloader

From your ADB-connected Portal:

```bash
adb reboot bootloader
```

Wait for the device to reboot into fastboot/bootloader mode. Verify:

```bash
fastboot devices
```

You should see your device listed.

### Step 3: Flash Disabled vbmeta

Disable Android Verified Boot so the system can accept the new GSI:

```bash
fastboot flash vbmeta vbmeta_disabled.img --disable-verification --disable-verity
```

Note: If you already flashed a disabled vbmeta in Guide 07, this step reinforces it via fastboot with the additional `--disable-verity` flag.

### Step 4: Flash the System Image

Flash the GSI to the system partition:

```bash
fastboot flash system system.img
```

This will take several minutes depending on the image size and USB speed. Do not disconnect during this process.

If you get a "system partition too small" error, you may need a smaller GSI variant or a `slim` build.

### Step 5: Wipe User Data

**WARNING: This erases ALL user data on the device. This is necessary for a clean GSI boot.**

```bash
fastboot -w
```

This reformats the userdata and cache partitions.

### Step 6: Reboot

```bash
fastboot reboot
```

### Step 7: Wait for First Boot

The first boot after flashing a GSI takes significantly longer than a normal boot. **Be patient.**

- The screen may stay black for 1-2 minutes
- You may see the Android boot animation for 5-10 minutes
- The device may reboot once or twice during initial setup
- **Do not force power off during this process** unless the device has been stuck for more than 15 minutes with no change

### Step 8: Complete Android Setup

Once the device boots, you will see the standard Android setup wizard:

1. Select your language
2. Connect to WiFi
3. Skip or complete Google account setup
4. Complete initial configuration

You now have a general-purpose Android device.

### Step 9: Test Hardware Compatibility

After setup, systematically test each hardware component to identify what works and what does not:

| Component | How to Test | Notes |
|-----------|------------|-------|
| **Touchscreen** | Tap, swipe, pinch-to-zoom in Settings | Should work on most GSIs |
| **Camera** | Open a camera app | May require custom drivers; smart framing will not work |
| **Microphone array** | Record a voice memo or make a call | 8-mic array may only present as stereo or mono |
| **WiFi** | Connect to your network in Settings | Usually works (Qualcomm WCN3990 has good mainline support) |
| **Speakers** | Play audio in Settings > Sound | Should work |
| **Bluetooth** | Pair a device in Settings > Bluetooth | Usually works |
| **USB-C** | Connect peripherals (keyboard, mouse, storage) | Data transfer should work |
| **Screen rotation** | Rotate the device (Gen 2 only) | Portrait mode on Gen 1 is not supported (landscape only) |

---

## Post-Install Configuration

### Option A: General-Purpose Android Tablet

Install apps from the Play Store (if you flashed a GApps variant) or via F-Droid / APK sideloading.

### Option B: Smart Home Dashboard (Home Assistant)

1. Install the Home Assistant Companion app
2. Configure it to connect to your HA instance
3. Set the app to launch on boot (use a launcher app like "Fully Kiosk Browser" for kiosk mode)
4. Mount the Portal in your kitchen, hallway, or workshop

### Option C: Video Conferencing Endpoint

1. Install Zoom, Google Meet, Microsoft Teams, or your preferred video app
2. The Portal's wide-angle camera and microphone array make it excellent for this use case
3. Position it on a desk or shelf for hands-free calls

### Option D: Digital Photo Frame

1. Install a photo frame app (e.g., Fotoo, Photo Slideshow)
2. Connect to Google Photos, local storage, or a NAS
3. Set to auto-start and disable screen timeout

### Installing Google Apps (If You Chose Vanilla)

If you flashed a vanilla GSI and want Google services later:

1. Install MicroG (open-source Google services replacement): `https://microg.org/`
2. Or flash a GApps package via recovery (requires a custom recovery)
3. Or re-flash with a GApps variant of the GSI

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Device stuck on boot animation for 15+ minutes | Force power off (hold power 10s), re-enter fastboot, try `fastboot -w` again, then reboot. |
| "system partition too small" error | Download a smaller/slim GSI variant. Some GSIs exceed the Portal's system partition size. |
| No touchscreen after boot | This is a driver compatibility issue. Try a different GSI version or a build specifically targeting APQ8098/MSM8998 (Snapdragon 835). |
| No WiFi | Check if the WiFi firmware files are present. Some GSIs need vendor-specific firmware. |
| No sound | Audio routing may need configuration. Check `Settings > Sound` and try different output paths. |
| Boot loop after GSI flash | Re-enter fastboot, reflash the original system from backup: `fastboot flash system backups/LATEST/system.bin` |
| Camera does not work | Camera support on GSIs is often limited. The Portal's camera module may need device-specific drivers. |
| Screen orientation is wrong | Use an app like "Rotation Control" from the Play Store to force landscape or portrait. |

---

## Alternative GSI Sources

If phhusson's builds do not work well, try:

- **Andy Yan's GSI builds**: Maintained LineageOS-based GSIs with broader device support
- **ErfanGSI**: Tool for creating custom GSIs
- **DSU Loader**: Android's Dynamic System Updates feature (if available) lets you test GSIs without permanently flashing

---

## What You Should Have After This Guide

- [ ] A Portal running a standard Android GSI
- [ ] Working touchscreen, WiFi, and audio (at minimum)
- [ ] A general-purpose Android device ready for your chosen use case
- [ ] Knowledge of which hardware components work and which need further driver work

---

## Congratulations

You have successfully transformed a discontinued Facebook Portal into a functional Android device. The Portal hardware -- with its excellent camera, microphone array, speakers, and display -- can now serve whatever purpose you choose.

---

*This is the final guide in the core series. Check the research documents for ongoing developments and deeper technical details.*
