# Guide 05: Partition Backup via EDL

| Risk Level | Time Estimate | Prerequisites |
|------------|---------------|---------------|
| **LOW** (read-only operation) | 15-45 minutes | EDL mode access + valid firehose programmer |

---

## Why This Matters

**This is CRITICAL -- your backup is your lifeline.** Do this BEFORE any modifications.

If anything goes wrong during flashing (Guide 07), your backup is the only way to restore your device to a working state. Without a backup, a bad flash means a permanent brick. EDL partition dumps are read-only operations -- they do not modify your device in any way.

---

## Prerequisites

Before you begin, make sure you have:

- [ ] Your Portal can enter EDL mode (see Guide 01)
- [ ] A valid firehose programmer file (.mbn) for your device
- [ ] The `bkerler/edl` tool installed and working (see Guide 00)
- [ ] At least 40 GB of free disk space (to hold all partition dumps)
- [ ] A USB-C cable connected between your Mac and the Portal

---

## Step-by-Step Instructions

### Step 1: Enter EDL Mode

Follow the procedure from Guide 01 to put your Portal into EDL (Emergency Download) mode. Your device should appear as `Qualcomm HS-USB QDLoader 9008`.

Verify the device is detected:

```bash
# On macOS, check for the Qualcomm device
system_profiler SPUSBDataType | grep -i qualcomm
```

You should see a Qualcomm 9008 device listed.

### Step 2: Run the Backup Script

If you have a firehose programmer auto-detected by the tool:

```bash
./scripts/edl/backup_all_partitions.sh
```

### Step 3: If You Have a Specific Firehose File

If you have a specific firehose programmer (for example, one you downloaded or extracted), pass it explicitly:

```bash
./scripts/edl/backup_all_partitions.sh --loader=tools/firehose/my.mbn
```

Replace `my.mbn` with the actual filename of your firehose programmer.

### Step 4: Wait for All Partitions to Dump

The script will read every partition on the device and save it to the `backups/` directory. This takes **15-45 minutes** depending on the storage size and USB speed.

You will see output like:

```
Dumping partition: boot ... OK (67108864 bytes)
Dumping partition: system ... OK (2147483648 bytes)
Dumping partition: vbmeta ... OK (65536 bytes)
...
```

**Do not disconnect the USB cable or interrupt the process.** A partial backup is worse than no backup because you might think you have a safety net when you do not.

### Step 5: Verify the Backup

After the script completes, verify the backup is complete and valid:

```bash
# Check that all files exist and are non-zero size
ls -lh backups/LATEST/

# Verify checksums were generated
cat backups/LATEST/checksums.sha256
```

**What to look for:**

- Every partition file should have a non-zero file size
- The `boot.bin` file should be approximately 64 MB
- The `system.bin` file should be approximately 2 GB
- A `checksums.sha256` file should exist with SHA-256 hashes for every dumped file

### Step 6: Copy the Backup to a Second Location

**Never rely on a single copy.** Copy your entire backup directory to at least one other location:

```bash
# Copy to an external drive (adjust the path to your drive)
cp -r backups/LATEST/ /Volumes/MyExternalDrive/portal_backup/

# Or compress and upload to cloud storage
tar -czf portal_backup_$(date +%Y%m%d).tar.gz backups/LATEST/
```

Suggested backup locations:

- An external USB drive
- A cloud storage service (iCloud, Google Drive, Dropbox)
- A different computer on your network

### Step 7: Protect the Backup Directory

**Never modify the backup directory.** It is your recovery copy.

- Do not rename files inside it
- Do not delete files from it
- Do not use it as a working directory for modifications
- When you need to modify a file (like `boot.bin`), always copy it elsewhere first

---

## If EDL Does Not Work (No Firehose)

If you cannot obtain a working firehose programmer for your device, you cannot take a backup via EDL. Your options are:

1. **Find a compatible firehose programmer:**
   - Search the `bkerler/Loaders` repository on GitHub
   - Check `temblast.com` for Qualcomm programmer databases
   - Search the XDA Forums thread for shared firehose files
   - The "atlas" (Gen 2, 16GB) firehose was shared in December 2025 on XDA

2. **Proceed extremely cautiously with fastboot-only methods:**
   - Fastboot can read some information but cannot dump full partitions on a locked device
   - Without a backup, any flashing operation is irreversible
   - This is strongly discouraged for beginners

3. **Wait for community developments:**
   - Monitor the XDA thread for new firehose files being shared
   - A firehose for one APQ8098/MSM8998 device sometimes works on related devices (but not always -- HWID and PK hash must match)

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Device not detected in EDL mode | Try a different USB-C cable. Some cables are charge-only. Use a data-capable cable. |
| "No loader found" error | You need a firehose .mbn file. See the "If EDL Does Not Work" section above. |
| Backup stalls on a partition | The partition may be corrupted or the USB connection may be unstable. Try again with a shorter/better cable. |
| Checksum file is empty | The backup script may have failed silently. Check the individual file sizes manually. |
| "Permission denied" errors | On macOS, you may need to allow the USB device in System Settings > Privacy & Security. |

---

## What You Should Have After This Guide

- [ ] A complete backup of all device partitions in `backups/LATEST/`
- [ ] SHA-256 checksums for every backed-up file
- [ ] A second copy of the backup on an external drive or cloud storage
- [ ] Confidence that you can restore your device if something goes wrong

---

*Next: Guide 06 -- Modifying boot.img to Enable ADB*
