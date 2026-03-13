# Guide 07: Flashing Modified Images

| Risk Level | Time Estimate | Prerequisites |
|------------|---------------|---------------|
| **HIGH** | 10-30 minutes | EDL mode + firehose programmer + **FULL BACKUP** (Guide 05) |

---

## This Is the Point of No Return

Flashing modified images permanently alters the partitions you write to. Once you flash a partition, the only way to undo it is to flash the backup copy back.

**Your backup is your safety net.** If you have not completed Guide 05 (Partition Backup via EDL), stop here and go do that first. Do not proceed without a verified, complete backup stored in at least two locations.

---

## Prerequisites

Before you begin, make sure you have:

- [ ] A **complete, verified backup** in `backups/LATEST/` (Guide 05)
- [ ] A **second copy** of that backup on an external drive or cloud storage
- [ ] Your Portal can enter **EDL mode** with a working firehose programmer
- [ ] A **modified boot.img** from Guide 06 at `scripts/boot_img/work/modified_boot.img`
- [ ] `avbtool` installed (for creating the disabled vbmeta image)
- [ ] A USB-C data cable connected between your Mac and the Portal

---

## Step-by-Step Instructions

### Step 1: Verify You Have a Full Backup

This is not optional. Check your backup directory:

```bash
# List the backup contents
ls -lh backups/LATEST/

# Verify critical files exist and have non-zero sizes
test -s backups/LATEST/boot.bin && echo "boot.bin: OK" || echo "boot.bin: MISSING"
test -s backups/LATEST/vbmeta.bin && echo "vbmeta.bin: OK" || echo "vbmeta.bin: MISSING"
test -s backups/LATEST/system.bin && echo "system.bin: OK" || echo "system.bin: MISSING"
```

**If any critical file is missing or zero-sized, STOP. Go back to Guide 05 and redo the backup.**

### Step 2: Enter EDL Mode

Put your Portal into EDL (Emergency Download) mode following the procedure from Guide 01.

Verify the device is detected:

```bash
system_profiler SPUSBDataType | grep -i qualcomm
```

### Step 3: Flash Modified vbmeta First (Disable Verification)

You must disable Android Verified Boot (AVB) before flashing a modified boot image. Otherwise, the bootloader will detect that the boot image has been tampered with and refuse to boot.

**Create a disabled vbmeta image:**

```bash
avbtool make_vbmeta_image --flags 2 --output vbmeta_disabled.img
```

The `--flags 2` parameter sets the "disable verification" flag. This tells the bootloader to skip hash verification of other partitions (including boot).

**Flash the disabled vbmeta:**

```bash
./scripts/edl/flash_partition.sh vbmeta vbmeta_disabled.img
```

Wait for confirmation that the flash completed successfully.

### Step 4: Flash the Modified Boot Image

Now flash the modified boot image that enables ADB:

```bash
./scripts/edl/flash_partition.sh boot scripts/boot_img/work/modified_boot.img
```

Wait for confirmation that the flash completed successfully. Do not disconnect during this process.

### Step 5: Power Cycle the Device

After both partitions have been flashed:

1. Disconnect the USB-C cable
2. Press and hold the power button for 10 seconds to force power off (if the device is on)
3. Wait 5 seconds
4. Press the power button to turn the device on
5. Reconnect the USB-C cable to your Mac

### Step 6: Check for ADB (If It Boots)

If the device boots successfully, check whether ADB is now accessible:

```bash
adb devices
```

If you see your device listed (even as "unauthorized"), ADB is working. You may need to:

```bash
# If device shows as unauthorized, try:
adb kill-server
adb start-server
adb devices
```

### Step 7: If Boot Loop -- Restore From Backup

If the device is stuck in a boot loop (repeatedly showing the Portal logo and restarting), do not panic. This is expected if secure boot rejects the modified image.

**Recovery procedure:**

1. Force power off (hold power button 10 seconds)
2. Re-enter EDL mode (Guide 01)
3. Flash the original boot image from your backup:

```bash
./scripts/edl/flash_partition.sh boot backups/LATEST/boot.bin
```

4. Flash the original vbmeta from your backup:

```bash
./scripts/edl/flash_partition.sh vbmeta backups/LATEST/vbmeta.bin
```

5. Power cycle the device -- it should boot normally again

---

## What Might Happen

After flashing modified images, you will see one of these outcomes:

### Best Case: Normal Boot with ADB
- Device boots to the Portal home screen
- `adb devices` shows the device
- You have full ADB shell access
- **This is rare but possible**, especially if the bootloader's verification is truly disabled by the vbmeta flag

### Likely Case: Yellow/Orange Boot State Warning
- Device shows a yellow or orange warning screen during boot (similar to "Your device has been unlocked" on other Android devices)
- This is actually a **good sign** -- it means the bootloader detected the modification but is proceeding anyway
- The device may boot after a delay
- ADB may or may not work depending on how the bootloader handles the warning state

### Expected if Verification Fails: Boot Loop
- Device repeatedly restarts, never reaching the home screen
- The bootloader is rejecting the modified boot image despite the vbmeta flag
- This means the device has additional verification beyond standard AVB
- **Recovery**: Follow Step 7 above to restore from backup

### Worst Case: Hard Brick (Extremely Rare)
- Device does not respond at all -- no screen, no USB detection, no EDL mode
- This is very unlikely with boot/vbmeta modifications alone (these partitions do not affect the primary bootloader)
- If this happens, the device may still be recoverable via EDL if the PBL (Primary Bootloader) in the SoC ROM is intact

---

## Important Notes

- **Flash order matters**: Always flash vbmeta before boot. If you flash a modified boot without disabling verification first, the device will definitely reject it.
- **Do not flash system**: Do not attempt to flash a modified system partition at this stage. The system partition is much larger and more complex. Get ADB working first.
- **One change at a time**: Flash only what is necessary. The fewer partitions you modify, the easier it is to diagnose problems and recover.
- **Keep EDL access**: As long as your device can enter EDL mode (which is controlled by the SoC ROM, not by anything you can flash), you can always recover.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Flash failed" error | Check that your firehose programmer is valid and the EDL connection is stable. |
| Device does not power on after flash | Try entering EDL mode directly (button combo while connecting USB). Restore backup. |
| ADB shows "no devices" after successful boot | ADB may need a different USB mode. Try: `adb kill-server && adb start-server`. |
| Yellow warning screen with countdown | Wait for the countdown to finish. The device may boot normally after. |
| `avbtool` command not found | Install via: `pip3 install avbtool` or check your PATH. |

---

## What You Should Have After This Guide

- [ ] Modified vbmeta and boot images flashed to the device
- [ ] Knowledge of your device's response to the modifications
- [ ] Either working ADB access, or a restored device with backup images
- [ ] An understanding of the recovery procedure if things go wrong

---

*Next: Guide 08 -- Installing a Generic System Image (GSI)*
