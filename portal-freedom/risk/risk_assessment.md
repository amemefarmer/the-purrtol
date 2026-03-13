# Risk Assessment Matrix

> Facebook Portal 10" Gen 1 (2018) — Codename: **aloha** (device tree) / **ohana**
> Platform: Qualcomm APQ8098 (Snapdragon 835 / MSM8998) | Android 9 Portal OS
> Storage: UFS (NOT eMMC) | RAM: 2GB | Bootloader: Locked
> Target audience: Beginners on macOS

---

## How to Read This Matrix

| Column | Meaning |
|--------|---------|
| **Operation** | What you are doing |
| **Risk Level** | ZERO = no device contact; LOW = read-only; MEDIUM = reversible writes; HIGH = potentially irreversible; CRITICAL = brick territory |
| **Reversible?** | Can you undo this operation? |
| **Brick Potential** | None / Low / Medium / High / Permanent |
| **Prerequisites** | What must be true before you attempt this |

---

## Phase 0 — Environment Setup (Host-Side Only)

These operations never touch the device. They happen entirely on your Mac.

| Operation | Risk Level | Reversible? | Brick Potential | Prerequisites |
|-----------|-----------|-------------|-----------------|---------------|
| Install Homebrew | ZERO | Yes (uninstall script) | None | macOS with admin access |
| Install Python 3 via Homebrew | ZERO | Yes (`brew uninstall python`) | None | Homebrew installed |
| Install QDL (`pip install qdl`) | ZERO | Yes (`pip uninstall qdl`) | None | Python 3 installed |
| Install edl (`pip install edl`) | ZERO | Yes (`pip uninstall edl`) | None | Python 3 installed |
| Install android-platform-tools (fastboot/adb) | ZERO | Yes (`brew uninstall --cask android-platform-tools`) | None | Homebrew installed |
| Install Docker Desktop for Mac | ZERO | Yes (drag to Trash) | None | macOS with admin access |
| Build magiskboot Docker container | ZERO | Yes (`docker rmi`) | None | Docker installed |
| Download firmware files from the internet | ZERO | Yes (delete files) | None | Internet connection |
| Offline analysis of firmware files (hex editors, binwalk, file command) | ZERO | Yes | None | Firmware files downloaded |
| Compute SHA-256 checksums of downloaded files | ZERO | Yes | None | Files exist on disk |

---

## Phase 1 — Device Reconnaissance (Read-Only Device Contact)

These operations talk to the device but do NOT write anything to it.

| Operation | Risk Level | Reversible? | Brick Potential | Prerequisites |
|-----------|-----------|-------------|-----------------|---------------|
| Enter EDL mode (QDLoader 9008) via button combo | LOW | Yes (reboot exits EDL) | None | Device powered off; know the button combo |
| Sahara hello / info query via EDL | LOW | Yes (read-only handshake) | None | Device in EDL mode; QDL or edl tool installed |
| Read partition table via EDL (if firehose loaded) | LOW | Yes (read-only) | None | Valid firehose programmer for ohana; device in EDL mode |
| Read individual partitions via EDL (backup) | LOW | Yes (read-only) | None | Valid firehose programmer; device in EDL mode |
| Enter fastboot mode via button combo | LOW | Yes (reboot exits fastboot) | None | Device powered off; know the button combo |
| `fastboot getvar all` (query device variables) | LOW | Yes (read-only query) | None | Device in fastboot mode; fastboot installed |
| `fastboot oem device-info` (check lock state) | LOW | Yes (read-only query) | None | Device in fastboot mode |
| Probe various `fastboot oem <cmd>` read commands | LOW | Yes (read-only if commands are queries) | Low | Device in fastboot mode; understand which commands are safe |
| ADB shell access attempt (if device boots normally) | LOW | Yes (read-only) | None | Device booted; USB connected; ADB enabled (if possible) |

---

## Phase 2 — Backup Creation (Read from Device, Write to Host)

| Operation | Risk Level | Reversible? | Brick Potential | Prerequisites |
|-----------|-----------|-------------|-----------------|---------------|
| Full partition dump via EDL to host | LOW | Yes (read-only on device) | None | Valid firehose; device in EDL; enough disk space (~16GB+) |
| Copy boot.img from device to host | LOW | Yes (read-only on device) | None | EDL or ADB access to boot partition |
| Copy vbmeta from device to host | LOW | Yes (read-only on device) | None | EDL or ADB access to vbmeta partition |
| Verify backup integrity (sha256sum comparison) | ZERO | Yes | None | Backup files on host |
| Store backups to secondary location | ZERO | Yes | None | Backup files exist |

---

## Phase 3 — Modification (Write to Device)

**WARNING: This is where things become potentially irreversible. Triple-check everything.**

| Operation | Risk Level | Reversible? | Brick Potential | Prerequisites |
|-----------|-----------|-------------|-----------------|---------------|
| Flash patched boot.img via fastboot | HIGH | Yes, if you have backup boot.img | Medium | Backup of original boot.img; device in fastboot; patched image verified |
| Flash vbmeta with verification disabled | HIGH | Yes, if you have backup vbmeta | Medium | Backup of original vbmeta; device in fastboot |
| `fastboot erase userdata` (factory reset) | MEDIUM | No (data is gone) | Low | Backups of any data you care about; this wipes user data but does not brick |
| Flash GSI (Generic System Image) to system partition | HIGH | Yes, if you have backup system.img | High | Backup of original system; device in fastboot; correct GSI for arm64 + API level |
| Flash super/system via EDL | HIGH | Yes, if you have backup | High | Valid firehose; backup of original partitions |
| `fastboot oem unlock` (if supported) | HIGH | Possibly irreversible side effects | Medium | Research whether this triggers lockdowns on Portal; backup everything first |

---

## Phase 4 — Advanced / Experimental (Here Be Dragons)

**These operations carry significant risk. Some may use unpatched vulnerabilities (0-day exploits). Proceed only if you fully understand the consequences and have complete backups.**

| Operation | Risk Level | Reversible? | Brick Potential | Prerequisites |
|-----------|-----------|-------------|-----------------|---------------|
| Ramdump probe via EDL (Sahara memory dump) | MEDIUM | Yes (read-only in theory) | Low | Device in EDL; edl tool; understanding of Sahara protocol |
| Large ramdump payload (0-day exploit via Sahara/Firehose) | CRITICAL | Unknown — depends on exploit | High to Permanent | Complete backups; deep understanding of the exploit; acceptance of total loss risk |
| Flash modified XBL/bootloader partitions | CRITICAL | Only if EDL + firehose still work after | Permanent | You should almost NEVER do this; complete backups; valid firehose; expert knowledge |
| Flash modified TrustZone (tz) / HYP / RPM partitions | CRITICAL | Only if EDL + firehose still work after | Permanent | You should almost NEVER do this; these are security-critical partitions |
| Attempt to write custom firehose programmer | CRITICAL | N/A (runs in memory) | High | Deep Qualcomm Sahara knowledge; reverse engineering skills |

---

## Risk Level Summary

```
ZERO      No device contact at all. Pure host-side work.
LOW       Read-only device contact. Nothing is modified on the device.
MEDIUM    Writes to non-critical partitions or erases user data. Recoverable.
HIGH      Writes to boot-critical partitions. Recoverable IF you have backups.
CRITICAL  Writes to foundational firmware. May be unrecoverable even with backups.
```

---

## Golden Rules

1. **Never flash without a backup.** Your backup is your only lifeline.
2. **Never flash xbl, tz, hyp, or rpm** unless you are absolutely certain of what you are doing and why.
3. **Block OTA updates** (via DNS or firewall) before connecting the device to WiFi. An OTA update can silently patch the firmware you are depending on.
4. **Verify checksums** before and after every flash operation.
5. **One change at a time.** Flash one thing, test, confirm it works, then move on.
6. **If in doubt, stop.** Ask the community. A bricked Portal with no firehose is a paperweight.
