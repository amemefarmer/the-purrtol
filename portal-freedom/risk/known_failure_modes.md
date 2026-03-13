# Known Failure Modes

> Facebook Portal 10" Gen 1 (2018) — Codename: **ohana**
> Community-documented failures and dead ends. Learn from others' mistakes.

---

## 1. ADB Sideload in Recovery Appears Functional but ADB Never Connects

**What happens:**
The Portal's recovery mode displays what looks like a standard Android recovery menu, including an "Apply update from ADB" option. Selecting this option appears to put the device into ADB sideload mode. However, when you run `adb devices` or `adb sideload <file>` on the host, the device never appears.

**Why it fails:**
Facebook likely stripped or disabled the ADB daemon in their recovery implementation. The UI element is inherited from AOSP recovery but the underlying service either does not start or is configured to reject all connections. The USB interface may not switch to the ADB protocol at all.

**What to do instead:**
Do not rely on ADB sideload as a flashing path. Use EDL (QDLoader 9008) mode or fastboot mode for writing to the device.

---

## 2. OEM Unlock Toggle in Developer Options May Trigger Lockdowns

**What happens:**
Some users have reported that accessing hidden developer options (through various UI tricks) and toggling OEM unlock does not actually unlock the bootloader. Worse, toggling this setting may trigger additional security measures such as a factory reset, re-engagement of verified boot in a stricter mode, or logging that flags the device.

**Why it fails:**
Facebook controls the OEM unlock flow on Portal devices. Unlike stock Android phones from Google or OnePlus where `fastboot oem unlock` is a supported path, Facebook has no reason to allow bootloader unlocking and may have booby-trapped the toggle.

**What to do instead:**
Do not toggle OEM unlock unless you have a complete backup of every partition and are prepared for the device to factory reset or enter a more locked-down state. Research the specific firmware version you are running before attempting this.

---

## 3. USB-C "Maintenance Boot Mode" with OS Hard Disk Is Unreproducible

**What happens:**
There are scattered reports (mostly for Portal TV) of a special USB boot mode where connecting certain USB-C devices or hard drives during boot causes the device to enter a maintenance or alternate boot path. These reports have not been reliably reproduced on the Portal 10" Gen 1.

**Why it fails:**
The behavior, if it ever existed, may have been specific to certain firmware versions, specific USB devices, or specific Portal hardware revisions. It may also have been a misidentification of normal EDL or fastboot mode entry.

**What to do instead:**
Do not spend time chasing this. Use the known, reliable entry methods: EDL via button combo, and fastboot via button combo. Document the exact button combos that work for your specific device.

---

## 4. Browser-Based Exploits to Reach Android Settings Have Been Patched

**What happens:**
Earlier firmware versions allowed users to exploit the Portal's built-in web browser (accessible through certain flows) to navigate to `intent://` URIs or use JavaScript tricks to break out of the Portal shell and access the underlying Android settings. This allowed some users to enable developer options, toggle settings, and even sideload apps.

**Why it fails:**
Facebook has patched these browser escapes in subsequent firmware updates. If your Portal has been connected to WiFi and received OTA updates, these exploits are almost certainly no longer available.

**What to do instead:**
Check your exact firmware version before attempting any browser-based approach. If your firmware is recent, these paths are closed. Focus on hardware-level approaches (EDL, fastboot) rather than software-level escapes. This is also why blocking OTA updates is critical — if you happen to have an older firmware, you want to keep it.

---

## 5. Port 8889 HTTPS on Portal TV — No Exploitation Path Found

**What happens:**
Network scanning (nmap) of the Portal TV has revealed an HTTPS service listening on port 8889. This discovery generated excitement in the community as a potential attack surface for remote access.

**Why it fails:**
Despite the port being open, no one has documented a successful exploitation path. The service likely requires Facebook-signed certificates for mutual TLS authentication, serves only internal diagnostic data, or has no useful API endpoints exposed. This finding is specific to Portal TV and may not apply to Portal 10" Gen 1 at all.

**What to do instead:**
Do not rely on network-based attack surfaces. The most promising paths are through the Qualcomm EDL interface (hardware-level) and fastboot. Network services on Facebook devices are likely well-hardened.

---

## 6. Recovery Mode 10-Second Countdown — Easy to Miss Timing

**What happens:**
When entering recovery mode on the Portal, there is a roughly 10-second window where you must make a selection from the recovery menu. If you miss this window, the device may automatically reboot back into the normal OS (or attempt to).

**Why it fails:**
The countdown is not obvious. If you are not watching carefully or are still fumbling with button combinations, you can miss the window entirely and need to start over.

**What to do instead:**
- Have your plan ready before entering recovery mode. Know exactly which option you want to select.
- Be ready to press the selection button immediately upon seeing the recovery menu.
- If you miss it, power off completely and try again. Do not panic.
- Consider recording video of the screen so you can review any messages that flash by quickly.

---

## 7. OTA Updates Can Silently Patch Exploitable Firmware

**What happens:**
Connecting a Portal to WiFi, even briefly, can trigger an automatic OTA (Over-The-Air) firmware update. Facebook pushes these updates silently in the background. The device may download and stage the update without any visible indication, then apply it on the next reboot.

**Why it fails:**
If you are relying on a specific firmware version that has known exploitable paths (older Sahara vulnerabilities, browser escapes, specific fastboot behaviors), an OTA update can silently close those doors. You may not even realize the firmware has changed until your exploit no longer works.

**What to do instead:**
**Block DNS before connecting to WiFi.** This is critical and should be done before the device ever touches your network.

Options (in order of preference):
1. **Do not connect to WiFi at all** if you do not need network access.
2. **Block Facebook OTA domains at your router** before connecting:
   - `portal.facebook.com`
   - `fbportal.com`
   - `ota.portal.facebook.com`
   - `*.fbcdn.net`
3. **Use an isolated network** (guest WiFi or VLAN) with no internet access.
4. **Use a Pi-hole** or similar DNS sinkhole to block Facebook domains.

If the device has already updated, check your new firmware version and reassess your available options.

---

## Summary Table

| # | Failure Mode | Severity | Workaround Available? |
|---|-------------|----------|----------------------|
| 1 | ADB sideload non-functional | Medium | Yes — use EDL/fastboot instead |
| 2 | OEM unlock toggle risks | High | Partial — backup everything first |
| 3 | USB-C maintenance boot | Low | No — unreproducible, ignore it |
| 4 | Browser exploits patched | Medium | Conditional — depends on firmware version |
| 5 | Port 8889 unexploitable | Low | No — ignore it, focus on EDL/fastboot |
| 6 | Recovery countdown | Low | Yes — be prepared and quick |
| 7 | Silent OTA updates | High | Yes — block DNS before WiFi |
