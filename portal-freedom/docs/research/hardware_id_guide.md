# Hardware Identification Guide: Which Portal Do You Have?

Before starting any repurposing work, you need to know exactly which Portal model you have. Different models have different codenames, different firmware, and potentially different unlock methods. This guide covers how to identify your device using physical features, branding, and model numbers.

---

## Quick Identification Table

| Model | Year | Display | Key Physical Feature |
|-------|------|---------|---------------------|
| Portal (10") Gen 1 | 2018 | 10" | Chunky frame, visible front speaker grille |
| Portal+ Gen 1 | 2018 | 15.6" | Pivoting screen on cylindrical stand |
| Portal TV | 2019 | None (HDMI) | Small dongle-like box, no screen |
| Portal Mini | 2019 | 8" | Small slim frame, privacy switch |
| Portal (10") Gen 2 | 2019 | 10" | Slim picture-frame design, privacy switch |
| Portal+ Gen 2 | 2019 | 14" | Slim frame, tilting stand |
| Portal Go | 2021 | 10" | Battery-powered, detachable from charging cradle |

---

## Detailed Identification by Model

### Portal (10") Gen 1 (2018)

**Codenames:** `aloha` / `ohana`

**How to identify:**
- **Chunky, thick frame** around the display -- noticeably thicker than Gen 2
- **Visible front speaker grille** along the bottom bezel (horizontal slot pattern)
- **Clip-on camera cap** for privacy (a small plastic piece that clips over the camera lens). It is NOT a sliding switch -- it physically snaps on and off
- **Landscape only** -- the device has a fixed stand and does not support portrait orientation
- **Branding**: Says "Portal from Facebook" on the back (Facebook-branded, not Meta)
- **Back panel**: Large, slightly textured back with a prominent circular logo area

**SoC:** APQ8098 (Snapdragon 835) — confirmed via EDL/Sahara
**Storage:** 16 GB or 32 GB eMMC

**Hardware Buttons (confirmed via device tree source):**
| Button | Function | Key Code |
|--------|----------|----------|
| Top button 1 | Volume Up | KEY_VOLUMEUP (115) |
| Top button 2 | Mute/Privacy | KEY_MUTE (113) |

> **Note:** There is NO Volume Down button on the Portal 10" Gen 1. The second button is a Mute/Privacy toggle, not Volume Down.

**EDL Identity (confirmed 2026-02-24):**
- HWID: `0x000620e10137b8a1`
- CPU: APQ8098 (MSM_ID: `0x000620e1`)
- OEM_ID: `0x0137` (Facebook/Meta)
- PK_HASH: `0x7291ef5c5d99dc05ee00237a1d71b1f572696870b839bb715fba9e89988b4a3f`

**Why it matters for repurposing:** Gen 1 firmware is stuck on older security patches (August 2019), making it potentially more vulnerable to known Qualcomm exploits. The APQ8098 (Snapdragon 835) has a much larger research community than QCS605, as it powered many flagship phones (Galaxy S8, Pixel 2, OnePlus 5). However, no publicly shared firehose programmer exists for APQ8098 + Facebook's signing key as of early 2026.

---

### Portal+ Gen 1 (2018)

**Codename:** Not confirmed publicly

**How to identify:**
- **15.6-inch screen** -- significantly larger than any other Portal model
- **Pivoting screen mounted on a cylindrical stand** -- the screen can rotate between landscape and portrait
- The cylindrical base contains the speaker (good audio quality)
- **Branding**: "Portal from Facebook"
- Much heavier than other models (the stand adds significant weight)

**Storage:** 32 GB UFS 2.1

**Why it matters for repurposing:** The UFS storage (rather than eMMC) may affect which tools and procedures work. The large, high-resolution display (1920x1080) makes this the most attractive model for repurposing as a dashboard or video endpoint.

---

### Portal TV (2019)

**Codename:** Not confirmed publicly

**How to identify:**
- **No screen at all** -- this is a small box that connects to your TV via HDMI
- Small, roughly rectangular black box (about the size of an Apple TV)
- Has an HDMI port, USB-C port, and power barrel connector (12V 2A)
- Comes with a remote control
- **Branding**: "Portal from Facebook"

**Storage:** eMMC (size varies)

**Why it matters for repurposing:** Different form factor means different use cases. Could potentially become a media streaming box or thin client if unlocked.

---

### Portal Mini (2019)

**Codename:** Not confirmed publicly

**How to identify:**
- **8-inch screen** -- the smallest Portal with a display
- Slim, picture-frame-like design (similar to Gen 2, but smaller)
- **Sliding physical privacy switch** on top to cover the camera
- **Branding**: "Portal from Facebook" (early units) or may have transitional branding

**Storage:** Not publicly confirmed

**Why it matters for repurposing:** Smallest display, but same QCS605 SoC. Good candidate for a compact smart home dashboard.

---

### Portal (10") Gen 2 (2019)

**Codenames:** `atlas` / `omni`

**How to identify:**
- **Slim, picture-frame design** -- dramatically thinner than Gen 1
- **Sliding privacy switch** on top of the device (covers the camera when slid)
- **Supports portrait orientation** -- the stand allows you to rotate the display 90 degrees
- Thinner bezels than Gen 1
- Cleaner, more minimal design overall
- **Branding**: "Portal from Facebook"

**Storage:** 16 GB or 32 GB (storage type may differ from Gen 1)

**Why it matters for repurposing:** This is currently the most promising model for repurposing. A firehose programmer for the "atlas" variant (16GB) was shared on XDA in December 2025. If verified, this would enable EDL-based partition reading and writing.

---

### Portal+ Gen 2 (2019)

**Codename:** Not confirmed publicly

**How to identify:**
- **14-inch screen** (slightly smaller than the Gen 1 Portal+ at 15.6")
- Slim picture-frame design with a tilting stand (not the cylindrical pivoting stand of Gen 1)
- **Sliding privacy switch** on top
- **Branding**: "Portal from Facebook"

**Storage:** 32 GB

---

### Portal Go (2021)

**Codename:** `terry`

**How to identify:**
- **Battery-powered** -- this is the only Portal that can operate without being plugged in
- Comes with a **charging cradle** (the device docks into the cradle for charging)
- 10-inch screen
- Portable design with a handle-like shape at the back
- **Branding**: "Meta Portal" (this was released after the Meta rebrand)

**Storage:** 32 GB

**Why it matters for repurposing:** The battery makes this the most versatile for repurposing as a portable tablet. However, it is a newer device with potentially stronger security measures.

---

## Identifying by Branding

The branding on the device tells you the era it was manufactured:

| Branding | Era | Models |
|----------|-----|--------|
| **"Portal from Facebook"** | 2018-2021 | Gen 1 (all), Gen 2 (all), Portal TV, Portal Mini |
| **"Meta Portal"** | 2021-2022 | Portal Go, later production runs of other models |

If your device says "Meta Portal," it was manufactured after Facebook's rebrand to Meta (October 2021). These later-production units may have updated firmware or security measures.

---

## Finding Your Model Number

The model number provides a definitive identification:

1. **Check the back or bottom of the device** -- there should be a regulatory label with an FCC ID and model number
2. **In Portal settings** (if the device still boots):
   - Go to **Settings** (swipe down from top, tap gear icon)
   - Navigate to **About** or **Device Info**
   - Look for:
     - Model number
     - Serial number
     - Firmware version (e.g., `1.42.3`)
     - Android version (should be Android 9)
     - Security patch level (e.g., `August 1, 2019` for Gen 1)

---

## Checking Firmware Version

If your device still boots to the Portal interface:

1. Swipe down from the top of the screen
2. Tap the **Settings** gear icon
3. Look for **About** or **Software Information**
4. Note the **firmware version** and **security patch level**

Key firmware details:

- **Gen 1 devices** are typically stuck on security patches from **August 2019**
- **Gen 2 and later** may have more recent patches
- The latest firmware version across all models was approximately **1.42.3**
- Meta stopped pushing firmware updates after discontinuing the product line

---

## What to Do After Identification

Once you know your model:

1. **Record the model name, codename, and generation** for reference throughout the project
2. **Check the research docs** (`gen1_vs_gen2.md`) for model-specific considerations
3. **Search the XDA Forums thread** for your specific codename to find relevant discussions
4. **Determine which unlock path** is most viable for your model:
   - Gen 2 "atlas": EDL + firehose is the most promising path
   - Gen 1 "aloha/ohana": Bootloader exploit may be needed
   - Other models: Research status varies

---

*See also: `gen1_vs_gen2.md` for critical differences between generations that affect the repurposing effort.*
