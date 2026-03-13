# Go-Forward Plan — Portal Freedom Project

**Date:** 2026-02-26
**Status:** Phase 1 (Reconnaissance) COMPLETE → Phase 2 (Exploit Development) BLOCKED on ABL

---

## Where We Are

After 3 days of intensive work (Feb 24-26), we have:

- **Fully identified the device**: APQ8098 (SD835), UFS storage, 2GB RAM, Android 9
- **Mapped all access modes**: EDL (Sahara only, no firehose), Fastboot (3-button method)
- **Enumerated everything**: 64 partitions, 50+ OEM commands, complete variable dump
- **Closed dead-end paths**: No firehose exists, no oem ramdump, no getvar overflow, no fastboot boot/fetch
- **Confirmed the exploit surface**: CVE-2021-1931 DMA buffer overflow is viable, USB DMA accepts 15MB+
- **Identified the single blocker**: We need the 1MB ABL binary to proceed

### What's Been Ruled Out
| Path | Why it's closed |
|------|----------------|
| Firehose/EDL partition read | No firehose exists for APQ8098 + FB OEM_ID (exhaustively searched) |
| 2026 Qualcomm 0-day (ramdump) | `oem ramdump` not present in Portal ABL |
| getvar overflow (>502 bytes) | Tested to 16KB, no hang/crash |
| `fastboot boot` (unsigned RAM boot) | Command stripped from ABL |
| `fastboot fetch` (partition read) | Not supported |
| `fastboot flash` (direct flash) | Blocked by lock state |
| `flashing unlock` (standard) | Blocked by `get_unlock_ability: 0` |
| OEM unlock response commands | No matching command exists (8 variants tested) |

### What's Still Open
| Path | Status | Probability |
|------|--------|-------------|
| **CVE-2021-1931** (ABL buffer overflow) | VIABLE — needs ABL binary | 70% if ABL obtained |
| **Developer unit ABL dump** | Untried — need to contact Marcel | 40% |
| **OTA update interception** | Untried | 20% |
| **Community future work** | Passive monitoring | Unknown |

---

## The Critical Path: ABL Binary

Everything converges on one artifact: the **ABL (Android Bootloader) binary**.

- Partition: `abl_a` or `abl_b`
- Size: 1MB (0x100000)
- Format: UEFI PE executable (Qualcomm LinuxLoader)
- Contains: fastboot implementation, unlock logic, boot verification
- **NOT in the tadiphone firmware dump** (verified: no PE/UEFI files anywhere)

### How to Get It (ranked by likelihood)

**1. Developer Unit Dump (BEST OPTION — try first)**
- Marcel (@MarcelD505 on X/Twitter) posted on XDA about finding an unsealed Portal
- A dev/unsealed unit would have ADB root access
- Command: `adb shell dd if=/dev/block/bootdevice/by-name/abl_b of=/sdcard/abl_b.img`
- Action: Post on XDA thread, reach out on Twitter

**2. OTA Update Package**
- Portal checks for OTA updates via HTTPS
- Updates may include ABL partition images (A/B devices update all partitions)
- Action: Connect Portal to WiFi through a proxy, capture update URL
- Alternative: Search for cached OTA packages on the userdata partition
- The update payload key is RSA 2048-bit (public key in firmware dump)

**3. Other Firmware Dumps**
- Check dumps.tadiphone.dev for Portal+ or Portal TV (may share ABL)
- Check other firmware dump sites: firmware.mobi, androidfilehost, etc.
- Action: Systematic search

**4. Direct UFS Chip-Off (LAST RESORT)**
- Physically desolder UFS chip, read with programmer
- Requires specialized equipment and skill
- Risk: physical damage to device
- Action: Only if all other paths fail

---

## Phase 2 Plan: CVE-2021-1931 Exploitation

Once we have the ABL binary, here is the exploitation path:

### Step 1: ABL Analysis (Ghidra)
- Load ABL PE binary in Ghidra (AARCH64 UEFI)
- Use `uefi-firmware-parser` to extract LinuxLoader module
- Identify: fastboot command table, USB DMA buffer address, download handler
- Map: ASLR behavior, page permissions, executable regions
- Find: `IsUnlocked` flag location, `VerifiedBootDxe` entry points

### Step 2: Environment Setup
- Clone `j4nn/xperable` repo
- Set up Linux VM (Ubuntu) with:
  - Custom kernel patch for 16MB USB transfers (provided in xperable repo)
  - libusb-1.0-dev, cmake, pe-parse library
  - Cross-compilation toolchain for AARCH64 position-independent code
- Build xperable and understand its structure

### Step 3: Offset Adaptation
- Compare Sony's LinuxLoader offsets with Facebook's
- Identify differences in memory layout, ASLR range, page table structure
- Build Portal-specific probing payloads (position-independent AARCH64)
- Key challenge: Facebook's custom modifications change all offsets

### Step 4: Exploit Development
- Phase 1: Probe — send PIC payloads to determine ABL base address
- Phase 2: Hijack — redirect DMA download buffer to arbitrary address
- Phase 3: Patch — overwrite LinuxLoader to achieve persistent code execution
- Phase 4: Unlock — patch IsUnlocked flag, disable VerifiedBootDxe

### Step 5: Post-Unlock
- `fastboot flashing unlock` should now succeed
- Flash modified boot.img with: `ro.debuggable=1`, `ro.adb.secure=0`
- Alternatively: disable dm-verity via vbmeta, flash GSI system image
- Enable ADB permanently

---

## Phase 3 Plan: Custom ROM / GSI

Once bootloader is unlocked:

### Option A: Patched Stock + ADB
- Modify boot.img: set `ro.boot.force_enable_usb_adb=1`
- Disable dm-verity: `fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img`
- Keep Portal OS but with ADB access and root

### Option B: GSI (Generic System Image)
- Device is Treble-compatible (`ro.treble.enabled=true`)
- VNDK version 28 (Android 9 / Pie)
- System-as-root, A/B partitions
- Compatible GSI: ARM64, system-as-root, A/B
- Flash: `fastboot flash system_a gsi.img`
- Requires: disable AVB first

### Option C: LineageOS / Custom ROM
- MSM8998 has strong LineageOS support (OnePlus 5, Pixel 2)
- Would need device tree adaptation for Portal hardware (display, cameras, mics)
- Longer-term project after initial unlock

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|-------------|
| Obtain ABL binary | 1-4 weeks | Community outreach, OTA hunting |
| ABL reverse engineering | 1-2 weeks | Ghidra, UEFI RE skills |
| Exploit adaptation | 2-4 weeks | ARM64 exploit dev, xperable study |
| Testing & refinement | 1-2 weeks | Iterative with device in fastboot |
| Post-unlock setup | 1-3 days | Boot.img mod or GSI flash |
| **Total** | **5-12 weeks** | **From ABL acquisition** |

If ABL is never obtained: project stalls until community finds alternative.

---

## Immediate Action Items (This Week)

- [ ] **Post on XDA thread** — share our complete enumeration data, ask for ABL dump
- [ ] **Contact Marcel @MarcelD505** — ask about dev unit ABL partition
- [ ] **Clone xperable repo** — study exploit structure locally
- [ ] **Install Ghidra** — prepare for ABL reverse engineering
- [ ] **Set up Linux VM** — Ubuntu with custom kernel for 16MB USB transfers
- [ ] **Search for OTA URLs** — check Portal network traffic, DNS queries
- [ ] **Search other dump sites** — firmware.mobi, androidfilehost, etc.

---

## Files Modified This Session
- `MEMORY.md` — Complete rewrite with all confirmed data
- `journal/005_fastboot_breakthrough.md` — Added Session 2 deep enumeration
- `journal/006_exploit_research.md` — Updated with tested/closed paths
- `docs/adr/007_fastboot_0day_assessment.md` — Status: RESOLVED
- `docs/research/fastboot_0day_tracker.md` — Updated with test results
- `docs/guides/02_entering_fastboot_mode.md` — Confirmed 3-button method
- `risk/risk_assessment.md` — Corrected device identification
- `README.md` — Updated discoveries, approaches, and community asks
- `scripts/fastboot/enumerate_everything.sh` — NEW comprehensive script

---

*The reconnaissance phase is complete. Every accessible surface has been probed. The entire project now hinges on obtaining one file: the 1MB ABL binary from the `abl_b` partition.*
