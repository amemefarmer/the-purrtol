# Brick Recovery Procedures

> Facebook Portal 10" Gen 1 (2018) — Codename: **ohana**
> This document covers what to do when things go wrong.

---

## Severity Levels at a Glance

| Level | Name | Symptom | Prognosis |
|-------|------|---------|-----------|
| 1 | Soft Brick | Boot loop (stuck on Facebook logo) | Recoverable |
| 2 | Fastboot Brick | Stuck in fastboot, won't boot OS | Recoverable |
| 3 | EDL-Only | Only QDLoader 9008 shows up on USB | Recoverable IF you have a valid firehose |
| 4 | Dead USB | No USB response at all | Difficult; may require hardware intervention |

---

## Level 1: Soft Brick (Boot Loop)

### Symptoms
- Device shows the Facebook/Portal logo repeatedly
- Device reboots in a loop and never reaches the home screen
- Screen may flash or show an error briefly before restarting

### Cause
Typically caused by a bad boot.img flash, corrupted system partition, or a failed GSI install.

### Recovery Procedure

1. **Power off the device completely.**
   - Hold the power button for 15+ seconds until the screen goes dark.
   - Wait 10 seconds.

2. **Enter EDL mode via button combo.**
   - With the device powered off, hold the correct button combination for your Portal model.
   - Look for **QDLoader 9008** to appear on your Mac:
     ```
     system_profiler SPUSBDataType | grep -i qualcomm
     ```
   - You should see something like `Qualcomm HS-USB QDLoader 9008`.

3. **Load your firehose programmer and flash backup partitions.**
   ```bash
   # Using edl tool — flash your BACKUP boot.img
   edl w boot boot.img.backup

   # Flash your BACKUP vbmeta (restores verified boot state)
   edl w vbmeta vbmeta.img.backup
   ```

4. **Reboot the device.**
   ```bash
   edl reset
   ```

5. **Verify the device boots normally.**

### If EDL Is Not Accessible
- Try entering **fastboot mode** instead (different button combo).
- From fastboot, flash the backup:
  ```bash
  fastboot flash boot boot.img.backup
  fastboot flash vbmeta vbmeta.img.backup
  fastboot reboot
  ```

---

## Level 2: Fastboot Brick (Stuck in Fastboot)

### Symptoms
- Device shows a fastboot screen or text-mode display
- Device responds to `fastboot devices` on your Mac
- Device will not boot into the normal OS

### Cause
Typically caused by a corrupted system or boot partition, or a flash operation that was interrupted.

### Recovery Procedure

1. **Confirm fastboot connectivity.**
   ```bash
   fastboot devices
   ```
   You should see your device serial number listed.

2. **Flash all backup partitions from fastboot.**
   ```bash
   fastboot flash boot boot.img.backup
   fastboot flash vbmeta vbmeta.img.backup
   fastboot flash system system.img.backup    # if you have it
   fastboot reboot
   ```

3. **If fastboot flash commands fail or hang**, enter EDL mode:
   - Some devices support `fastboot oem edl` or `fastboot reboot edl`.
   - Otherwise, try the hardware button combo to enter EDL from a powered-off state (hold power button 15s to force off first).

4. **From EDL, flash all backup partitions.**
   ```bash
   edl w boot boot.img.backup
   edl w vbmeta vbmeta.img.backup
   edl w system system.img.backup
   edl reset
   ```

---

## Level 3: EDL-Only (QDLoader 9008 Responds)

### Symptoms
- Device does not boot at all (no logo, no fastboot)
- Plugging in USB shows **QDLoader 9008** on the host
- This is the lowest software-accessible recovery mode

### Cause
Corrupted bootloader chain, bad XBL flash, or TrustZone corruption. The Qualcomm primary bootloader (PBL) in ROM is still functional and is presenting the EDL (Emergency Download) interface.

### Recovery Procedure

#### If You Have a Valid Firehose Programmer for ohana

1. **Confirm EDL connectivity.**
   ```bash
   system_profiler SPUSBDataType | grep -i qualcomm
   ```

2. **Flash ALL backup partitions.**
   ```bash
   edl w xbl xbl.img.backup
   edl w xbl_config xbl_config.img.backup
   edl w boot boot.img.backup
   edl w vbmeta vbmeta.img.backup
   edl w system system.img.backup
   edl w tz tz.img.backup
   edl w hyp hyp.img.backup
   edl w rpm rpm.img.backup
   edl w aboot aboot.img.backup      # if applicable
   # Flash any other partitions you backed up
   edl reset
   ```

3. **Verify the device boots.**

#### If You Do NOT Have a Valid Firehose Programmer

This is a serious situation. Without a firehose programmer that matches your device's HWID and PK_HASH, you cannot communicate with the device through EDL beyond the initial Sahara handshake.

**Options:**
- **Search for a compatible firehose.** See `tools/firehose/README.md` for where to look.
- **Ask the community.** XDA Developers forums, Telegram groups for Qualcomm hacking.
- **Hardware ISP (In-System Programming).** This involves micro-soldering wires directly to the eMMC flash chip on the board and using a hardware programmer (like an Easy JTAG or Medusa Pro) to write directly to storage. This is a last resort and requires specialized equipment and skills.

---

## Level 4: Dead USB (No USB Response)

### Symptoms
- Device shows nothing on screen
- No USB device appears when plugged in (no QDLoader 9008, no fastboot, nothing)
- Device may or may not charge (check for LED or warmth)

### Cause
Could be hardware failure, severely corrupted low-level firmware, battery completely drained, or a USB-C port issue.

### Recovery Procedure

1. **Try a different USB cable.**
   - Use a **USB-C to USB-A** cable (not USB-C to USB-C). Some EDL connections are more reliable with USB-A host ports.
   - Try multiple known-good cables.

2. **Try a different USB port on your Mac.**
   - If using a hub, connect directly to the Mac.
   - Try every available port.

3. **Check if the device charges.**
   - Plug in and leave it for 30+ minutes.
   - Feel for warmth near the charging port.
   - Look for any charging LED indicator.

4. **Try the button combo for 30+ seconds.**
   - With the USB cable plugged in, hold the EDL button combo for a full 30 seconds or more.
   - Check USB devices on your Mac while holding:
     ```bash
     # Run this in a loop while holding buttons
     while true; do system_profiler SPUSBDataType 2>/dev/null | grep -i qualcomm && break; sleep 1; done
     ```

5. **Try with device unplugged from power, hold buttons, then plug in USB.**
   - Sometimes the sequence matters: hold buttons first, then connect cable.

6. **Last Resort: Hardware ISP.**
   - This requires opening the device and micro-soldering to the eMMC chip.
   - You will need specialized equipment (Easy JTAG, Medusa Pro, or similar).
   - This is beyond beginner skill level. Consider finding a local repair shop experienced with Qualcomm devices.
   - **Do NOT attempt this unless you are comfortable with surface-mount soldering on tiny pads.**

---

## Prevention Tips

These tips will help you avoid needing the recovery procedures above.

### 1. Always Backup First
- Before flashing ANYTHING, dump every partition you can access.
- Store backups in at least two locations (see `backups/README.md`).
- Verify backup integrity with checksums before flashing.

### 2. Never Flash Critical Partitions Unless Absolutely Sure
The following partitions are boot-critical. Corrupting them can make EDL recovery impossible without a firehose or hardware ISP:
- **xbl** / **xbl_config** (Qualcomm eXtensible Boot Loader)
- **tz** (TrustZone — ARM secure world)
- **hyp** (Hypervisor)
- **rpm** (Resource Power Manager firmware)

**Rule of thumb:** If you did not create the image yourself and do not understand exactly what it contains, do NOT flash it to any of these partitions.

### 3. Block OTA Updates via DNS
Facebook's OTA servers can silently push firmware updates that patch exploitable versions. Before connecting your Portal to WiFi:

- **Option A: Router-level DNS block.**
  Block the following domains at your router:
  ```
  portal.facebook.com
  fbportal.com
  ota.portal.facebook.com
  *.fbcdn.net           # broad; may break other Facebook services
  ```

- **Option B: Pi-hole or local DNS.**
  Add the above domains to your blocklist.

- **Option C: Isolated network.**
  Put the Portal on a VLAN or guest network with no internet access. It only needs local network for your purposes.

### 4. One Change at a Time
- Flash one partition, reboot, verify.
- If something breaks, you know exactly which change caused it.

### 5. Document Everything
- Use the experiment template in `journal/experiment_template.md`.
- Record what you flashed, from where, checksums, and results.
- Future-you will thank present-you.
