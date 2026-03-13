# Guide 04: Offline Firmware Analysis

| | |
|---|---|
| **Risk Level** | ZERO -- all analysis happens on your Mac using downloaded files |
| **Estimated Time** | 1-3 hours (take your time, this is where the real learning happens) |
| **Prerequisites** | [Guide 00: Environment Setup](00_environment_setup.md) and [Guide 03: Firmware Download](03_firmware_download.md) completed |
| **Device Needed** | No |

---

## Overview

This is the **most valuable guide in the entire series**. Everything here happens on your Mac using the firmware files you downloaded in Guide 03. Your Portal device stays in a drawer -- you do not need it.

By the end of this guide, you will understand:

- How the Portal's boot image is structured
- What Android system properties control ADB access
- What Facebook-specific security layers exist
- Whether verified boot (vbmeta) needs to be addressed
- The exact changes that would be needed to enable ADB

This knowledge is the foundation for everything that comes after. Rushing through this guide means guessing later. Taking your time here means understanding exactly what you are doing when you eventually modify the device.

---

## What is a Boot Image?

The `boot.img` file is one of the most important partitions on any Android device. It contains:

| Component | What It Is |
|---|---|
| **Kernel** | The Linux kernel that runs the operating system |
| **Ramdisk** | A small filesystem loaded into RAM at boot time |
| **default.prop / build.prop** | System properties that control device behavior |
| **init scripts** | Scripts that run during early boot to configure the system |
| **Kernel command line** | Parameters passed to the kernel at boot |

The ramdisk is particularly important because it contains the `default.prop` file (which sets properties like `ro.debuggable`) and the init scripts (which can enable or disable ADB).

---

## Step-by-Step Instructions

### Step 1: Extract the Boot Image

Run the extraction script, pointing it at your downloaded firmware directory:

```bash
./scripts/firmware/extract_boot_img.sh tools/firmware/ohana
```

This script:

1. Locates `boot.img` (or `boot_a.img`) inside the firmware directory
2. Uses `magiskboot` (via Docker) or `unpackbootimg` to split the boot image into its components
3. Extracts the ramdisk contents
4. Places everything into a working directory at `scripts/boot_img/work/`

You should see output showing the extraction progress:

```
Found boot image: tools/firmware/ohana/boot.img
Extracting boot image...
  - kernel
  - ramdisk
  - dtb (device tree)
  - boot header info
Extracting ramdisk...
  - default.prop
  - init scripts
  - sbin/
  - ...

Extraction complete. Working directory: scripts/boot_img/work/
```

### Step 2: Analyze the Boot Image

Run the analysis script on the extracted boot image:

```bash
./scripts/firmware/analyze_boot_img.sh scripts/boot_img/work/boot.img
```

This script examines the boot image and prints a structured report. Read the output carefully -- it contains the most important information in this entire project.

---

### Step 3: Understand the Key Properties

The analysis output will show you several Android system properties. Here are the critical ones to look for and what they mean:

#### ADB-Related Properties

| Property | Typical Value | What It Means |
|---|---|---|
| `ro.debuggable` | `0` | When `0`, ADB is disabled at the system level. Needs to be `1` to enable ADB. |
| `ro.adb.secure` | `1` | When `1`, ADB requires RSA key authorization. When `0`, ADB accepts any connection. |
| `ro.secure` | `1` | When `1`, the system runs with security enforcement. When `0`, allows root ADB. |
| `persist.sys.usb.config` | `none` or `mtp` | Controls the default USB mode. Needs to include `adb` (e.g., `mtp,adb`) for ADB access. |

> **What you are looking for:** On a stock Portal, `ro.debuggable` is almost certainly `0` and `persist.sys.usb.config` does not include `adb`. These are the primary gates blocking ADB access.

#### Facebook-Specific Properties

Search the analysis output for any properties containing these keywords:

- **`fb`** -- Facebook-specific properties
- **`portal`** -- Portal-specific settings
- **`entitlement`** -- Feature entitlement checks
- **`seal`** -- Tamper detection or integrity sealing

```bash
# You can also search manually in the extracted files:
grep -ri "fb\.\|portal\.\|entitlement\|seal" scripts/boot_img/work/
```

These Facebook-specific properties often add additional layers of security or feature gating on top of standard Android properties. Document every one you find -- they may need to be addressed in addition to the standard ADB properties.

#### Init Scripts That Gate ADB

Look for init scripts that reference ADB, USB configuration, or debugging:

```bash
# Search for ADB-related logic in init scripts
grep -rn "adb\|adbd\|usb\|debug" scripts/boot_img/work/*.rc scripts/boot_img/work/init* 2>/dev/null
```

Pay attention to:

- Conditions that check property values before starting the ADB daemon
- Scripts that override USB configuration at boot
- Services that monitor or enforce security properties

---

### Step 4: Analyze the Verified Boot Metadata (vbmeta)

If a `vbmeta.img` exists in the firmware dump, analyze it:

```bash
# Find vbmeta
find tools/firmware/ohana -name "vbmeta*"

# Run analysis (replace the path with whatever you found above)
./scripts/firmware/analyze_vbmeta.sh tools/firmware/ohana/vbmeta.img
```

#### What is vbmeta?

Android Verified Boot (AVB) uses `vbmeta.img` to store cryptographic hashes of other partitions (boot, system, vendor, etc.). At boot time, the bootloader checks these hashes to verify that partitions have not been modified.

Key things to look for in the vbmeta analysis:

| Detail | Why It Matters |
|---|---|
| **Hash algorithm** | Shows what cryptographic verification is used |
| **Partition list** | Shows which partitions are verified (boot is almost always verified) |
| **Flags** | A flags value of `0` means strict verification. Flags `2` means verification is disabled. |
| **Rollback index** | Anti-rollback protection version number |

> **Key question:** If you modify `boot.img`, will vbmeta verification reject it? If vbmeta has flags `0` (strict), then yes -- you would also need to flash a modified vbmeta with flags `2` (disabled) or re-sign the modified boot image.

---

### Step 5: Document Your Findings

Create a findings document in your journal. This is important -- you will reference these notes repeatedly in future work.

```bash
# Create or open your findings file
nano journal/firmware_analysis_findings.txt
```

Record at minimum:

```
Portal Gen 1 (ohana) Firmware Analysis
=======================================
Date: [today's date]

ADB Properties:
  ro.debuggable = [value]
  ro.adb.secure = [value]
  ro.secure = [value]
  persist.sys.usb.config = [value]

Facebook-Specific Properties:
  [list everything you found with fb/portal/entitlement/seal]

Init Script ADB Logic:
  [which scripts reference ADB, what conditions they check]

Verified Boot (vbmeta):
  Flags: [value]
  Verified partitions: [list]
  Implication: [will modifying boot.img be rejected?]

Partition Scheme:
  A/B: [yes/no]
  Active slot: [a or b, if applicable]

Summary:
  To enable ADB, the following changes appear necessary:
  1. [list changes]
  2. ...
```

---

## Understanding What You Found

Here is a framework for interpreting your findings:

### Scenario A: Simple Case

- `ro.debuggable=0` is the only gate
- vbmeta flags are `2` (verification disabled) or there is no vbmeta
- No Facebook-specific property enforcement

**Implication:** Changing `ro.debuggable` to `1` and setting `persist.sys.usb.config=mtp,adb` in the boot image ramdisk may be sufficient.

### Scenario B: Moderate Case

- `ro.debuggable=0` needs to change
- vbmeta flags are `0` (strict verification)
- Standard init scripts gate ADB

**Implication:** You need to modify the boot image AND flash a modified vbmeta with flags `2` to disable verification. This is two partitions to modify instead of one.

### Scenario C: Complex Case

- Standard ADB properties need to change
- Facebook-specific properties add additional gates
- Custom init scripts enforce Portal-specific security
- vbmeta is strict

**Implication:** Multiple properties need changing, Facebook's custom security layers need to be understood and addressed, and vbmeta needs modification. This requires more research but is still doable.

Most Portal Gen 1 devices fall into Scenario B or C. Do not be discouraged -- the fact that you now understand exactly what is in play is a huge step forward.

---

## Bonus: Compare with Another Device (Optional)

If you downloaded the atlas (Gen 2) firmware in Guide 03, you can run the same analysis on it:

```bash
./scripts/firmware/extract_boot_img.sh tools/firmware/atlas
./scripts/firmware/analyze_boot_img.sh scripts/boot_img/work/boot.img
```

Comparing the two firmwares can reveal:

- Which security measures Facebook added, removed, or changed between generations
- Whether the same approach would work on both devices
- Patterns in how Facebook names and uses custom properties

---

## Troubleshooting

### Extraction Script Fails

**"Docker not found" or "magiskboot not available":**

If you skipped the Docker steps in Guide 00, the extraction script may not have the tools it needs. Go back to Guide 00, Steps 4-5, and install Docker + build the magiskboot image.

**"No boot.img found":**

Check what files actually exist in the firmware directory:

```bash
ls -la tools/firmware/ohana/
```

The boot image might be named differently (e.g., `boot_a.img`, `boot_b.img`). If so, specify the exact path:

```bash
./scripts/firmware/extract_boot_img.sh tools/firmware/ohana/boot_a.img
```

### grep Returns No Results

If searching for Facebook-specific properties returns nothing, the properties might be in the system or vendor images rather than the boot image. These larger images require different extraction tools (like `simg2img` and mounting as a filesystem). The boot image analysis covers the most critical properties, but not all of them.

### "Permission denied" on Extracted Files

```bash
chmod -R u+r scripts/boot_img/work/
```

---

## Quick Reference: Useful Commands for Exploration

Once the boot image is extracted, here are some commands for exploring on your own:

```bash
# List everything in the extracted ramdisk
find scripts/boot_img/work/ -type f | head -50

# Read the default properties
cat scripts/boot_img/work/default.prop

# List all init scripts
ls scripts/boot_img/work/*.rc

# Search for any property across all files
grep -r "property_name" scripts/boot_img/work/

# Look at the directory structure
tree scripts/boot_img/work/ -L 2
```

Take your time exploring. Every file you look at builds your understanding of how the device works.

---

## What's Next?

You now have a detailed understanding of the Portal's firmware structure and security model. This is the end of the zero-risk guide series. Everything beyond this point involves making decisions about modifying the device.

Before proceeding to any modification guides, make sure you have:

- [ ] Completed all analysis steps above
- [ ] Documented your findings in `journal/`
- [ ] Identified which properties need to change
- [ ] Understood whether vbmeta modification is needed
- [ ] Identified any Facebook-specific security layers

Revisit earlier guides if needed:

- **[Guide 00: Environment Setup](00_environment_setup.md)** -- tool installation
- **[Guide 01: Entering EDL Mode](01_entering_edl_mode.md)** -- the mode used for flash operations
- **[Guide 02: Entering Fastboot Mode](02_entering_fastboot_mode.md)** -- device information queries
- **[Guide 03: Downloading Firmware](03_firmware_download.md)** -- firmware acquisition
