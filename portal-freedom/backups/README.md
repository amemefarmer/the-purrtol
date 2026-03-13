# Backup Strategy

> Your backups are the ONLY recovery path if flashing goes wrong.
> Without backups, a bricked device may be unrecoverable.

---

## Naming Conventions

Use the following naming format for all backup files:

```
<partition>_<firmware_version>_<date>.img
```

### Examples

```
boot_v1.2.3_20260215.img
vbmeta_v1.2.3_20260215.img
system_v1.2.3_20260215.img
xbl_v1.2.3_20260215.img
userdata_v1.2.3_20260215.img
```

### Rules

- **Partition name**: Use the exact partition name as reported by the device (e.g., `boot`, `vbmeta`, `system`, `xbl`, `tz`, `hyp`, `rpm`, `userdata`).
- **Firmware version**: The Portal firmware version active at the time of backup. If unknown, use `unknown` (e.g., `boot_unknown_20260215.img`).
- **Date**: Use `YYYYMMDD` format. This is the date you took the backup.
- **Extension**: Always use `.img` for raw partition images.
- **No spaces in filenames.** Use underscores only.

### Full Partition Dump

When dumping all partitions at once, store them in a dated subdirectory:

```
backups/
  full_dump_v1.2.3_20260215/
    boot.img
    vbmeta.img
    system.img
    xbl.img
    xbl_config.img
    tz.img
    hyp.img
    rpm.img
    userdata.img
    modem.img
    ... (all partitions)
    checksums.sha256
```

---

## Verification Procedures

**Every backup must be verified.** An unverified backup is not a backup — it is a false sense of security.

### Generate Checksums After Backup

Immediately after creating a backup, generate SHA-256 checksums:

```bash
# For a single file
shasum -a 256 boot_v1.2.3_20260215.img > boot_v1.2.3_20260215.img.sha256

# For an entire directory of backups
cd backups/full_dump_v1.2.3_20260215/
shasum -a 256 *.img > checksums.sha256
```

### Verify Checksums Before Flashing

Before using any backup file for recovery, verify it has not been corrupted:

```bash
# Verify a single file
shasum -a 256 -c boot_v1.2.3_20260215.img.sha256

# Verify all files in a dump
cd backups/full_dump_v1.2.3_20260215/
shasum -a 256 -c checksums.sha256
```

Every file should report `OK`. If any file reports a mismatch, do NOT use it for flashing.

### Sanity Checks

Beyond checksums, perform basic sanity checks on backup files:

```bash
# Check file size is non-zero and reasonable
ls -lh boot_v1.2.3_20260215.img

# Check the file type (should be "data" or "Android bootimg" for boot.img)
file boot_v1.2.3_20260215.img

# For boot.img, look for the Android boot magic bytes
xxd boot_v1.2.3_20260215.img | head -1
# Should start with: 414e 4452 4f49 4421 (which is "ANDROID!" in ASCII)
```

---

## Storage Recommendations

### The Two-Copy Rule (Minimum)

Keep **at least two copies** of every backup, on **different physical storage devices**:

1. **Copy 1: Local disk.** Your Mac's internal drive, in the `backups/` directory of this project.
2. **Copy 2: External drive.** A USB flash drive, external SSD, or external HDD that is stored separately.

### Offsite Copy (Strongly Recommended)

Keep at least one copy in a location physically separate from your workspace:

- **Cloud storage.** Upload to Google Drive, iCloud, Dropbox, or similar. Partition images are typically a few hundred MB each (system.img may be several GB). Consider compressing first:
  ```bash
  # Compress a backup directory
  tar czf full_dump_v1.2.3_20260215.tar.gz full_dump_v1.2.3_20260215/
  ```
- **Different physical location.** Another room, another building, a friend's house.

### Why Offsite?

If your Mac's drive fails and your external drive was sitting next to it when the coffee spilled, both copies are gone. An offsite copy protects against localized disasters.

### Storage Checklist

- [ ] Backup files exist on Mac's local disk
- [ ] Backup files copied to external drive
- [ ] SHA-256 checksums generated and stored alongside backups
- [ ] Checksums verified on each copy after transfer
- [ ] At least one copy is offsite or in cloud storage
- [ ] Backup file sizes are non-zero and match across copies

---

## Critical Reminder

**Backups are your ONLY recovery path.**

If you flash a bad image and your device will not boot:
- **With backups**: Enter EDL or fastboot, flash the backup, device is restored.
- **Without backups**: Your device may be permanently bricked. You would need to find someone else's backup for the same device and firmware version (unlikely) or resort to hardware-level recovery (expensive, difficult).

**Take the time to back up properly. It is the single most important step in this entire project.**

Do not skip it. Do not rush it. Do not tell yourself "I'll do it later."
Back up first. Verify the backup. Then proceed.
