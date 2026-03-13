# Firehose Programmer Files

> What they are, why you need one, how to find one, and how to stay safe.

---

## What Is a Firehose Programmer?

A firehose programmer (sometimes called a "loader" or "MBN file") is a small binary that runs in Qualcomm's Emergency Download (EDL) mode. When a Qualcomm device enters EDL mode (QDLoader 9008), the primary bootloader (PBL) burned into the chip's ROM waits for a host computer to send a programmer binary via the Sahara protocol. This programmer then executes in memory on the device and provides read/write access to the device's storage (eMMC or UFS) through the Firehose XML protocol.

**Without a valid firehose programmer, you can enter EDL mode but you cannot read or write anything.** The PBL will accept the Sahara handshake but reject any programmer that does not pass its signature verification.

### The Chain of Events

```
Device in EDL mode (QDLoader 9008)
        |
        v
Host sends firehose .mbn via Sahara protocol
        |
        v
PBL verifies the firehose signature against fused keys (PK_HASH)
        |
        v
If valid: firehose runs in memory, you get read/write access
If invalid: PBL rejects it, nothing happens
```

---

## Why You Need One

For the Facebook Portal 10" Gen 1 (ohana), the firehose programmer is your key to:

1. **Reading partitions** — Dumping every partition as a backup before you modify anything.
2. **Writing partitions** — Flashing modified boot.img, vbmeta, system images, or GSIs.
3. **Brick recovery** — If the device is in a state where only EDL works (no fastboot, no normal boot), the firehose is your only software-based path to restore it.

Without a firehose, EDL mode is a locked door you can see but cannot open.

---

## How to Identify a Compatible Firehose

Not every firehose file works on every Qualcomm device. Two values must match:

### 1. HWID (Hardware ID)
This identifies the specific Qualcomm chipset. The Portal 10" Gen 1 uses the **APQ8098** (closely related to SDM845). You need a firehose compiled for this hardware.

### 2. PK_HASH (Public Key Hash)
The PBL has OEM-specific public keys fused into the silicon. The firehose must be signed with a private key whose corresponding public key hash matches what is fused on the chip. Facebook has their own signing keys, which means you need a firehose that was signed by (or for) Facebook for Portal devices.

### How to Check
When you enter EDL mode and try to load a firehose, the `edl` or `qdl` tool will typically report the device's HWID and PK_HASH. Compare these values with the metadata of any firehose file you find.

```bash
# Using the edl tool to check device info in EDL mode
edl info

# This will report something like:
# HWID: 0x000XX0XX (chipset identifier)
# PK_HASH: 0xABCDEF... (the hash your firehose must match)
```

---

## Where to Search for Firehose Files

### 1. bkerler/Loaders on GitHub
A well-known community repository of Qualcomm firehose/loader files for various devices.
- Repository: `https://github.com/bkerler/Loaders`
- Search by chipset name (e.g., SDM845, APQ8098) or OEM name (Facebook).
- Note: This repo may not have a Portal-specific loader. Check anyway.

### 2. temblast.com/ref/loaders.htm
A reference page that indexes known Qualcomm loader files by device and chipset.
- URL: `https://temblast.com/ref/loaders.htm`
- Search for "Portal", "ohana", "Facebook", "APQ8098", or "SDM845".

### 3. XDA Developers Forums
The XDA community is the largest Android hacking community. Search for:
- "Facebook Portal firehose"
- "Facebook Portal EDL"
- "ohana firehose"
- "APQ8098 firehose loader"

### 4. Qualcomm Firmware Repositories
Some firmware dump sites host complete Qualcomm firmware packages that include firehose programmers. These can sometimes be found by searching for the device codename + "firmware" or "QDL".

### 5. Ask the Community Directly
Telegram groups, Discord servers, and forums dedicated to Qualcomm reverse engineering sometimes have members who have obtained firehose files for niche devices.

---

## Important Warning: The December 2025 XDA Firehose

A firehose file was posted on XDA Developers forums in December 2025. **This file is for the Portal Gen 2 (codename: atlas), which is the 16GB model, NOT the Portal Gen 1 (codename: ohana).**

- **atlas** = Portal Gen 2 (2019), different hardware, different signing keys
- **ohana** = Portal Gen 1 (2018), which is what this project targets

**The atlas firehose will almost certainly NOT work on an ohana device.** The PBL will reject it because the HWID and/or PK_HASH will not match. Attempting to use it will not harm your device (the PBL simply refuses to load it), but it will waste your time.

Always verify HWID and PK_HASH before assuming a firehose file is compatible.

---

## Safety Warnings

### Do Not Trust Untrusted Firehose Files Blindly

A firehose programmer runs with **full, unrestricted access to your device's storage**. A malicious firehose could:
- Wipe your entire device storage
- Write malware to your boot chain
- Exfiltrate data from your device
- Permanently brick your device by corrupting critical partitions

### Guidelines

1. **Verify the source.** Only download firehose files from known, reputable sources (bkerler's repo, established XDA members with post history, etc.).

2. **Check file hashes.** If the source provides SHA-256 hashes, verify them. If multiple independent sources have the same file with the same hash, that increases confidence.

3. **Read before you run.** If you have the skills, analyze the firehose binary before loading it. Check strings, look for obvious anomalies.

4. **Start with read-only operations.** When you first load a new firehose, use it only to READ partitions. Verify the reads make sense (partition sizes, known strings in boot.img, etc.) before trusting it with write operations.

5. **Never download firehose files from random links in comments or DMs.** Social engineering is real. Stick to established repositories and forums.

---

## If You Cannot Find a Firehose

If no compatible firehose exists for ohana, your options are:

1. **Try to extract one from a firmware update package.** If you can obtain a Facebook Portal OTA update file or factory image, it may contain the firehose programmer.

2. **Hardware ISP.** Bypass the need for a firehose entirely by reading/writing directly to the eMMC chip via hardware. This requires micro-soldering skills and tools like Easy JTAG or Medusa Pro.

3. **Focus on fastboot.** If your device can enter fastboot mode, you may be able to do everything you need without EDL at all. EDL is the fallback; fastboot is the primary flashing path when available.
