# Guide 01: Entering EDL Mode

| | |
|---|---|
| **Risk Level** | ZERO -- EDL is a standard Qualcomm diagnostic mode built into the hardware |
| **Estimated Time** | 5-10 minutes |
| **Prerequisites** | [Guide 00: Environment Setup](00_environment_setup.md) completed, USB-C cable, Facebook Portal Gen 1 |
| **Device Needed** | Yes |

---

## Overview

This guide teaches you how to put your Facebook Portal Gen 1 (codename: **ohana**) into **EDL mode** -- a hardware-level diagnostic mode present on all Qualcomm-based devices.

**Why is this zero risk?** EDL mode is a read-only diagnostic state built into the Qualcomm chipset itself. Entering EDL does not modify anything on your device. Think of it like opening the hood of a car -- you are looking, not changing. You can exit at any time by simply unplugging the USB cable and power cycling the device.

---

## What is EDL Mode?

EDL stands for **Emergency Download Mode**. It is a low-level diagnostic mode built into Qualcomm processors (your Portal Gen 1 uses a Qualcomm chipset).

Key facts:

- **Hardware-level:** EDL exists in the processor's boot ROM. It cannot be removed, corrupted, or bricked. It is always available.
- **Protocol:** EDL uses the Sahara/Firehose protocol to communicate with the host computer.
- **USB Identity:** When in EDL mode, the Portal identifies itself as `Qualcomm HS-USB QDLoader 9008` over USB.
- **What it allows:** Reading and writing raw flash storage partitions. This is how firmware analysis and modification tools interact with the device.
- **What it does NOT do:** EDL does not boot Android. The screen stays blank. The device is essentially in a "waiting for instructions" state.

---

## What You Need

- Your Facebook Portal Gen 1 (2018, codename ohana)
- A USB-C cable (USB-C to USB-A is more reliable than USB-C to USB-C for this)
- Your Mac with the environment from Guide 00 set up

---

## Step-by-Step Instructions

### Step 1: Disconnect Everything

Unplug the power cable, USB cable, and any other connections from your Portal. The device should be completely disconnected from everything.

### Step 2: Wait for Full Power Off

Wait **30 seconds**. This ensures the Portal is fully powered down and not in a sleep or standby state. The screen should be completely dark with no indicator lights.

### Step 3: Prepare the Button Combination

Locate these three buttons on your Portal:

- **Volume Up** (+)
- **Volume Down** (-)
- **Power**

You will need to press and hold all three simultaneously.

### Step 4: Hold Buttons and Connect USB

This is the critical step. The order matters:

1. **Press and hold** Volume Up + Volume Down + Power **at the same time**
2. **While still holding all three buttons**, plug the USB-C cable into your Portal and into your Mac
3. **Keep holding** all three buttons for a full **10 seconds** after connecting the cable
4. **Release** all buttons

> **Tip:** It helps to have the USB cable already plugged into your Mac and ready to go, so you only need one hand to plug in the Portal end.

### Step 5: Verify the Screen

The screen should be **completely blank** -- no logo, no text, no backlight. This is correct. A blank screen means the device did NOT boot into Android and is sitting in EDL mode.

If you see the Portal logo or any text, the device booted normally. See the Troubleshooting section below.

### Step 6: Detect the EDL Device

Open Terminal on your Mac and run:

```bash
./scripts/edl/detect_edl_device.sh
```

You should see output confirming the device was found, something like:

```
Checking for EDL device...
[FOUND] Qualcomm HS-USB QDLoader 9008
Device is in EDL mode and ready.
```

### Step 7: Confirm with System Profiler (Optional)

If you want to double-check, you can also verify via macOS directly:

```bash
system_profiler SPUSBDataType 2>/dev/null | grep -A 5 "QDLoader\|9008"
```

You should see an entry mentioning `Qualcomm HS-USB QDLoader 9008` with vendor ID `05c6` and product ID `9008`.

---

## How to Exit EDL Mode

Exiting is simple:

1. **Unplug** the USB cable from the Portal
2. **Wait** 5 seconds
3. **Press and hold** the Power button for 3-5 seconds to boot normally

The Portal will restart as usual. Nothing has been changed.

---

## Troubleshooting

### Screen Shows the Portal Logo (Device Booted Normally)

This means the button combination did not register in time. This is the most common issue.

How to fix:

1. Unplug the USB cable
2. Hold Power for 10 seconds to force shut down
3. Wait 30 seconds
4. Try the button combination again, but this time:
   - Make sure you are pressing all three buttons **before** connecting USB
   - Press the buttons firmly and hold them the entire time
   - Try holding for **15 seconds** instead of 10

### Device Not Detected on Mac

If the detection script reports nothing found:

**Check USB connection:**
```bash
system_profiler SPUSBDataType
```

Look through the output for anything Qualcomm-related. If nothing appears at all, the cable might not be making a good connection.

**Try a different cable.** USB-C to USB-A cables (with a USB-A adapter or hub if needed) tend to be more reliable for EDL detection than USB-C to USB-C cables.

**Try a different USB port.** On some Macs, certain ports work better. If you have a USB hub, try bypassing it and connecting directly.

### "Permission Denied" Errors

On macOS, USB device access sometimes requires extra permissions:

```bash
# Check if the device shows up at all
system_profiler SPUSBDataType | grep -i qualcomm
```

If the device appears in system_profiler but the EDL tool cannot access it, this is likely a libusb permissions issue. Try running the detection script with `sudo`:

```bash
sudo ./scripts/edl/detect_edl_device.sh
```

### Screen Shows a Dim Backlight but No Image

This can happen on some units. If the detection script finds the QDLoader 9008 device, you are in EDL mode regardless of what the screen looks like. Trust the USB detection, not the screen.

---

## Understanding What Just Happened

When you held those three buttons and connected power via USB, you interrupted the normal boot sequence. Instead of loading the bootloader and then Android, the Qualcomm processor stayed in its built-in ROM code and entered EDL mode.

In this state:

- The processor is running minimal firmware from its internal ROM (not from flash storage)
- It is listening on USB for Sahara/Firehose protocol commands
- The Android operating system has NOT loaded
- No data on the device has been read or modified

This is the starting point for many of the operations you will learn in later guides.

---

## What's Next?

Now that you know how to enter EDL mode, consider:

- **[Guide 02: Entering Fastboot Mode](02_entering_fastboot_mode.md)** -- learn the other diagnostic mode
- **[Guide 03: Downloading Firmware](03_firmware_download.md)** -- get firmware for offline analysis (no device needed)
- **[Guide 04: Offline Firmware Analysis](04_offline_firmware_analysis.md)** -- study the firmware without touching the device
