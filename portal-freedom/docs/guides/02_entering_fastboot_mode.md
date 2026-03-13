# Guide 02: Entering Fastboot Mode

| | |
|---|---|
| **Risk Level** | ZERO -- fastboot on a locked bootloader is read-only |
| **Estimated Time** | 5-10 minutes |
| **Prerequisites** | [Guide 00: Environment Setup](00_environment_setup.md) completed, USB-C cable, Facebook Portal Gen 1 |
| **Device Needed** | Yes |

---

## Overview

This guide teaches you how to put your Facebook Portal Gen 1 (codename: **ohana**) into **fastboot mode** -- Android's built-in bootloader interface.

**Why is this zero risk?** On retail Portal units, the bootloader is **locked**. A locked bootloader means fastboot will let you read device information, but it will refuse to write or flash anything. You literally cannot damage the device in this mode because it will reject any modification commands.

---

## What is Fastboot Mode?

Fastboot is a protocol and tool that is part of the Android ecosystem. It provides a way to communicate with a device's bootloader before the full Android operating system loads.

Key facts:

- **Bootloader-level:** Fastboot runs at the bootloader stage, after the processor's ROM but before Android starts.
- **Protocol:** Uses the fastboot protocol over USB, communicating with the `fastboot` command-line tool on your Mac.
- **Visual indicator:** Unlike EDL (which shows a blank screen), fastboot shows the Portal logo with a black box containing text like "Please Reboot..." at the bottom.
- **Locked vs Unlocked:** On a locked bootloader (the default), fastboot only allows reading information. On an unlocked bootloader, it also allows writing/flashing partitions.

### Fastboot vs EDL -- What is the Difference?

| | EDL Mode | Fastboot Mode |
|---|---|---|
| **Level** | Hardware (Qualcomm ROM) | Software (Android bootloader) |
| **Screen** | Blank | Portal logo + text |
| **Protocol** | Sahara / Firehose | Fastboot |
| **Mac tool** | bkerler/edl | fastboot (from Android SDK) |
| **Access when locked** | Can still read/write via firehose | Read-only (info queries) |
| **Best for** | Low-level flash operations | Checking device info, flashing (if unlocked) |

Both modes are useful for different purposes. EDL is more powerful but requires specific Qualcomm firehose loaders. Fastboot is simpler and gives you quick access to device information.

---

## What You Need

- Your Facebook Portal Gen 1 (2018, codename ohana)
- A USB-C cable
- Your Mac with the environment from Guide 00 set up

---

## Important: Portal 10" Button Layout

> **CORRECTION (2026-02-24):** Firmware analysis of the device tree revealed that the Portal 10" (Aloha) does **NOT have a Volume Down button**. The device has only two buttons:
>
> | Button | Actual Function | Location |
> |--------|----------------|----------|
> | **Volume Up** | KEY_VOLUMEUP (115) | Top edge |
> | **Mute/Privacy** | KEY_MUTE (113) | Top edge |
>
> XDA instructions referencing "Vol Down" may be for the Portal+ or Portal TV, which have different button layouts. For the Portal 10", try the methods below.

## Step-by-Step Instructions

### Step 1: Power Off the Portal

If your Portal is on, hold the **Power** button (rear of device, near bottom) until it shuts down. Wait a few seconds to make sure it is fully off. The screen should be completely dark.

### Step 2: Connect USB and Hold ALL THREE Buttons

> **CONFIRMED METHOD (2026-02-25):** The working method requires holding ALL THREE buttons simultaneously through multiple boot screens.

1. Unplug all cables (wall power AND USB)
2. Wait for device to fully power down (10 seconds)
3. Connect USB-C **data** cable to Mac
4. Plug in wall power
5. Immediately press and hold **ALL THREE buttons** simultaneously:
   - **Power** (rear of device, near bottom)
   - **Volume Up** (top edge)
   - **Mute/Privacy** (top edge)
6. **Keep holding through MULTIPLE boot screens** — do NOT release when the first logo appears
7. Continue holding until you see "Please Reboot..." text

### Step 3: Wait for Fastboot Screen

Keep holding all three buttons through **multiple screens**. This may take 15-30 seconds. Do not release early.

### Step 4: Confirm the Visual Indicator

You should see:

- The **Portal logo** on screen
- A **black box** near the bottom of the screen with text that says something like **"Please Reboot..."**

This is the fastboot screen. It looks different from a normal boot (which would show the Portal logo and then transition to the home screen).

> **Note:** The exact text may vary by firmware version, but the key indicator is the Portal logo with a text box that does NOT proceed to the normal user interface.

### Step 5: Detect the Fastboot Device

Open Terminal on your Mac and run:

```bash
./scripts/fastboot/detect_fastboot_device.sh
```

You should see output like:

```
Checking for fastboot device...
[FOUND] Device in fastboot mode
Serial: XXXXXXXXXX

Device is in fastboot mode and ready.
```

You can also verify manually:

```bash
fastboot devices
```

This should print a line with your device's serial number followed by `fastboot`.

### Step 6: Query Device Information (Optional)

While in fastboot, you can query useful information:

```bash
# Run the comprehensive enumeration script (recommended):
./scripts/fastboot/enumerate_everything.sh

# Or query individual variables:
fastboot getvar product         # Should show "aloha"
fastboot getvar serialno        # Device serial number
fastboot getvar secure          # Whether secure boot is enabled (yes)
fastboot getvar unlocked        # Whether bootloader is unlocked (no)
fastboot getvar slot-count      # A/B partition scheme (2)
fastboot getvar current-slot    # Which slot is active (a or b)
fastboot getvar variant         # Storage type (APQ UFS)
```

> **Note:** `fastboot getvar all` returns "unknown command" on this bootloader.
> Use the enumeration script or query variables individually.

---

## Understanding the Locked Bootloader

When you run `fastboot getvar unlocked`, you will almost certainly see:

```
unlocked: no
```

This means the bootloader is **locked**. On a locked bootloader:

- **Allowed:** `fastboot getvar`, `fastboot oem device-info`, and other read-only commands
- **Blocked:** `fastboot flash`, `fastboot erase`, `fastboot oem unlock`, and all write commands

If you try to flash something, you will get an error like:

```
FAILED (remote: 'Flashing is not allowed in Lock State')
```

This is a safety feature. It means you cannot accidentally brick your device through fastboot. This is why the risk level for this guide is zero.

---

## How to Exit Fastboot Mode

You have two options:

**Option A: Reboot via command**
```bash
fastboot reboot
```

**Option B: Force reboot via hardware**

Hold the **Power** button for **10 seconds** until the device restarts.

Both options will boot the Portal back into its normal operating mode.

---

## Troubleshooting

### Device Boots Normally Instead of Fastboot

If the Portal goes straight to the home screen instead of the fastboot screen:

1. Hold Power (rear button) for 10 seconds to force shut down
2. Wait 10 seconds for full power down
3. Try **all three methods** (Vol Up, Mute, or Both buttons)
4. Make sure you are holding the button(s) BEFORE plugging in wall power
5. Hold for at least 15 seconds after power is connected
6. Try different USB cable positions (with/without USB data cable)
7. The Portal 10" has NO Volume Down button — do not confuse Mute for Vol Down

### Confirmed Device Response

When fastboot is working, you should see:
```
818PGA02P110MQ09	fastboot
```

The device identifies as:
- **Product:** aloha
- **Variant:** APQ UFS
- **Secure:** yes
- **Unlocked:** no
- **Current-slot:** b

### "fastboot devices" Shows Nothing

**Check that fastboot is installed:**
```bash
which fastboot
fastboot --version
```

If not found, install it:
```bash
brew install android-platform-tools
```

**Check USB connection:**
```bash
system_profiler SPUSBDataType
```

Look for an Android-related USB device in the output.

**Try a different cable or port.** USB-C to USB-A tends to be more reliable.

### "fastboot devices" Shows "no permissions"

This is a macOS permissions issue. Try:

```bash
sudo fastboot devices
```

If that works, you may need to create a udev rule or adjust USB permissions. For most macOS setups, this should not be necessary.

### Screen Shows "SECURE BOOT: ENABLED"

This is normal and expected. Secure boot being enabled does not prevent you from using fastboot in read-only mode. It just means the device verifies the integrity of what it boots, which is standard for retail devices.

---

## What Information to Record

While in fastboot mode, record these values in your journal for future reference:

| Variable | Command | Why It Matters |
|---|---|---|
| Product name | `fastboot getvar product` | Confirms your device codename |
| Serial number | `fastboot getvar serialno` | Unique device identifier |
| Secure boot | `fastboot getvar secure` | Security enforcement level |
| Unlocked state | `fastboot getvar unlocked` | Whether flashing is possible |
| Slot count | `fastboot getvar slot-count` | A/B partition layout info |
| Current slot | `fastboot getvar current-slot` | Which partition set is active |

---

## What's Next?

Now that you can access both EDL mode (Guide 01) and fastboot mode, consider:

- **[Guide 03: Downloading Firmware](03_firmware_download.md)** -- get firmware images for offline analysis
- **[Guide 04: Offline Firmware Analysis](04_offline_firmware_analysis.md)** -- study the firmware without touching the device
