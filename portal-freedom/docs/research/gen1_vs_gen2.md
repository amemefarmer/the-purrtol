# Gen 1 vs Gen 2: Critical Differences for Repurposing

This document covers the technical differences between the Portal Gen 1 and Gen 2 that directly affect the repurposing effort. **Critically, they use DIFFERENT SoCs** — Gen 1 uses APQ8098 (Snapdragon 835), while Gen 2 likely uses QCS605. Both run Android 9, but there are significant differences in security, storage, firmware, and available tools.

> **CORRECTION (2026-02-24):** EDL/Sahara interrogation confirmed Gen 1 uses **APQ8098 (Snapdragon 835)**, not QCS605 as previously assumed. This is a completely different chip family. The Dec 2025 atlas firehose is incompatible not just due to signing, but because it targets a different SoC entirely.

---

## Summary Comparison

| Attribute | Gen 1 (2018) | Gen 2 (2019) |
|-----------|-------------|-------------|
| **Codenames** | `ohana` / `aloha` | `atlas` / `omni` |
| **SoC** | **APQ8098 (Snapdragon 835)** ✅ confirmed | QCS605 (assumed, unconfirmed) |
| **MSM_ID** | `0x000620e1` ✅ confirmed | Likely `0x0AA0E1` |
| **OEM_ID** | `0x0137` (Facebook) ✅ confirmed | Unknown |
| **PK_HASH** | `7291ef5c...` ✅ confirmed | Different signing key |
| **Android Version** | Android 9 (Pie) | Android 9 (Pie) |
| **Security Patches** | August 2019 (frozen) | More recent (varies) |
| **Storage Type** | eMMC ✅ confirmed | May use UFS |
| **Known Firehose** | None for APQ8098 + FB signing key | Yes (atlas, Dec 2025 XDA post) |
| **Signing Chain** | Fully identified via Sahara | Partially documented |
| **Secondary Market Price** | $15-30 | $15-30 |
| **Best Unlock Path** | SD835 exploit research / community firehose | EDL + firehose |

---

## Detailed Differences

### 1. SoC and Signing Chains

**Gen 1 and Gen 2 use DIFFERENT SoCs:**
- **Gen 1:** APQ8098 (Snapdragon 835) — confirmed via EDL/Sahara, MSM_ID `0x000620e1`
- **Gen 2:** Likely QCS605 (Snapdragon 710 family) — not yet confirmed via EDL

They also have **different signing chains**. This means:

- A firehose programmer file (.mbn) that works on Gen 2 may **not** work on Gen 1
- The firehose must be signed with keys that match the device's HWID (Hardware ID) and PK hash (Public Key hash)
- Even within the same generation, different production runs or storage configurations (16GB vs 32GB) may have different signing
- Qualcomm burns fuse values during manufacturing that determine which signed programmers are accepted

**Practical impact:** You cannot assume a firehose for one model will work on another, even if they share the same SoC.

### 2. Storage Technology

**Gen 1: eMMC (embedded MultiMediaCard)**
- Older, slower storage interface
- Tools and procedures for eMMC are well-documented in the Android hacking community
- eMMC can sometimes be accessed directly via ISP (In-System Programming) by soldering to test points on the PCB
- The fastboot variant string on Gen 1 may show `APQ eMMC` or similar

**Gen 2: Potentially UFS (Universal Flash Storage)**
- Newer, faster storage interface
- UFS uses a different protocol than eMMC, so backup/restore tools may behave differently
- UFS has been confirmed on at least the Portal+ Gen 1 (`APQ UFS` variant string), and Gen 2 models may also use it
- ISP access to UFS is more difficult than eMMC

**Practical impact:** Scripts and tools that work for eMMC-based devices may need modifications for UFS. Check your fastboot variant string to confirm.

### 3. Firmware and Security Patch Level

**Gen 1:**
- Security patches frozen at **August 1, 2019**
- This is significant because it means Gen 1 devices are vulnerable to every Qualcomm security vulnerability discovered after that date
- Known CVEs that may be relevant: CVE-2021-1931 (fastboot buffer overflow), various TrustZone vulnerabilities
- The older firmware may have weaker bootloader protections

**Gen 2:**
- Received firmware updates for longer
- May have more recent security patches
- Potentially patched against some of the vulnerabilities that affect Gen 1
- The bootloader may have additional hardening

**Practical impact:** Gen 1's older firmware makes it a better target for known exploits, but the lack of a firehose programmer is a significant obstacle. Gen 2's newer firmware may be more secure, but the available firehose makes EDL access possible.

### 4. Available Firehose Programmers

**Gen 1:** No publicly available firehose programmer as of early 2026.
- Searches of `bkerler/Loaders`, `temblast.com`, and XDA have not yielded a working programmer
- Without a firehose, EDL mode is accessible but non-functional (you can enter 9008 mode but cannot read or write partitions)
- Community efforts to find or extract a Gen 1 firehose are ongoing

**Gen 2:** A firehose programmer for the "atlas" variant (16GB) was posted on XDA in December 2025.
- The poster claimed it works with QPST to flash partitions
- This has not been independently verified by multiple users
- If legitimate, it enables the full EDL workflow: backup, modify, flash
- It may or may not work on the "omni" variant or 32GB models

**Practical impact:** This is the single biggest differentiator right now. If you want to follow the EDL-based approach (Guides 05-07), you need a Gen 2 atlas unit.

### 5. Codenames and Firmware Sources

**Gen 1:**
- `aloha`: Primary codename for the 10" Gen 1
- `ohana`: Secondary/alternate codename
- Firmware available at `dumps.tadiphone.dev/dumps/facebook`

**Gen 2:**
- `atlas`: Primary codename for the 10" Gen 2 (this is the model with the shared firehose)
- `omni`: Secondary/alternate codename
- Firmware also available at the same dump site

These codenames appear in partition labels, build strings, and kernel configurations. Knowing your codename helps when searching for model-specific information.

### 6. Physical and Design Differences

Beyond the technical differences, the physical design affects practicality:

**Gen 1:**
- Thicker, heavier frame
- Landscape only (no portrait support)
- Clip-on camera cap (easy to lose)
- Visible front speaker grille

**Gen 2:**
- Slim picture-frame design
- Supports portrait orientation
- Integrated sliding privacy switch
- More tablet-like form factor (better for repurposing as a general device)

---

## Decision Matrix: Which Should You Get?

| If your goal is... | Recommended |
|---------------------|-------------|
| Follow the EDL/firehose path (Guides 05-07) | **Gen 2 (atlas, 16GB)** |
| Exploit bootloader vulnerabilities | **Gen 1** (older firmware, more known CVEs) |
| Best display for dashboard use | **Portal+ Gen 1** (15.6" 1080p) |
| Portable / battery-powered device | **Portal Go** |
| Cheapest entry point for experimentation | **Whichever is cheapest** ($15-30 on secondary market) |
| Highest chance of success (as of early 2026) | **Gen 2 atlas** (only model with a shared firehose) |

---

## The Pragmatic Fallback

If you have a Gen 1 and the bootloader exploit path proves too difficult or you lack reverse engineering expertise:

**Acquiring a Gen 2 atlas unit ($15-30) is the pragmatic fallback.**

These devices are widely available on eBay, Goodwill, Facebook Marketplace, and other secondary markets for very low prices. The cost of a second device is negligible compared to the time you might spend trying to find a Gen 1 firehose or develop a bootloader exploit.

Consider the Gen 1 as a learning/experimentation platform for understanding the hardware and tools, and the Gen 2 as your primary target for actually achieving a working unlock.

---

## Key Unknowns (As of Early 2026)

- Whether the December 2025 atlas firehose actually works for partition read/write
- Whether a modified boot image will be accepted by the Gen 2 bootloader (even with disabled vbmeta)
- Whether the Gen 1 and Gen 2 have identical bootloader unlock challenge-response mechanisms
- Whether the fastboot 0-day (see `fastboot_0day_tracker.md`) affects both generations equally
- Whether any Gen 1 firehose files exist in private collections that might be shared in the future

---

*See also: `hardware_id_guide.md` for identifying your specific model, `qcs605_reference.md` for SoC details, `fastboot_0day_tracker.md` for the latest on the Qualcomm vulnerability.*
