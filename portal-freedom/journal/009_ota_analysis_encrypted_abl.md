# Experiment 009: OTA Analysis — Encrypted ABL Discovery

**Date:** 2026-02-26
**Risk Level:** ZERO (host-side analysis only)
**Outcome:** MIXED — OTA obtained successfully but bootloader partitions are ENCRYPTED

---

## Marcel's Intel (via XDA)

Contact: @MarcelD505 on XDA
Key findings from Marcel + collaborator:
1. **Earlier firmware versions should be exploitable** but are impossible to downgrade
2. **Early ABLs are "unreadable"** (confirmed: they are encrypted)
3. **Later ABLs are readable** (suggests some versions exist without encryption)
4. **Unlock requires signed response** to nonce (already known)
5. Marcel has:
   - Unpacked LinuxLoader for **terry** (Portal Go)
   - An early ABL "which I can't read" (encrypted)
6. Full ROM download URLs available from Facebook's Graph API (pastebin shared)

## OTA Download — SUCCESS

### API Endpoint
```
https://graph.facebook.com/mobile_release_updates
?fields=...ota.device_type(ota.aloha_prod.ohana.user).version(0).fullbuild(True)...
&access_token=217151932108113|b781e66b808395cdc617f00b785384c7
```

### Metadata
- **Target version:** 1041515800015050
- **File size:** 1,282,501,712 bytes (1.2GB)
- **SHA-256:** `0287084025af63af4063afe2022e81a9bba52d4bd32f011614a441da5ca4297c` ✓ VERIFIED
- **Payload format:** Android A/B OTA (CrAU payload.bin)
- **Downloaded to:** `firmware/ota/aloha_ota_full.zip`

### Partition Extraction
Used `payload_dumper` (Python 3.11) to extract individual partitions:

| Partition | Size | Format | Entropy | Status |
|-----------|------|--------|---------|--------|
| **abl.img** | 212KB | ELF 32-bit ARM | 7.999 | **ENCRYPTED** |
| **xbl.img** | 2.6MB | ELF 64-bit AArch64 | 7.999 | **ENCRYPTED** |
| **tz.img** | 1.8MB | ELF 64-bit AArch64 | 7.989 | **ENCRYPTED** |
| **hyp.img** | 268KB | ELF 64-bit AArch64 | 7.999 | **ENCRYPTED** |
| **rpm.img** | 232KB | ELF 32-bit ARM | 7.972 | **ENCRYPTED** |
| boot.img | 27MB | Android bootimg | 7.460 | **READABLE** |
| keymaster.img | 308KB | ELF 64-bit AArch64 | 7.890 | Likely encrypted |
| devcfg.img | 60KB | ELF 64-bit AArch64 | 7.598 | Compressed/data |

### Encryption Details

ABL structure (Qualcomm MBN/ELF format):
```
Segment 0: NULL  (flags 0x7000000) — Hash table, 0x94 bytes
Segment 1: NULL  (flags 0x2200000) — Certificate chain, 0x1a58 bytes at 0x1000
Segment 2: LOAD  (flags 0x7)       — Code, 200KB at 0x3000, mapped to 0x9FA00000
```

The LOAD segment (actual code) has entropy of 7.9992 bits/byte — essentially
random data, confirming **hardware-level encryption** (Qualcomm Secure Boot).

Only the SoC's PBL (in ROM) has the key to decrypt these images. The encryption
is done at the fuse level using OEM_ID and PK_HASH.

---

## All Known Portal OTA Endpoints

| Device | Codename | Android | Status |
|--------|----------|---------|--------|
| Portal 10" Gen 1 / Portal+ Gen 1 | aloha/ohana | 9 | Downloaded, encrypted |
| Portal 10" Gen 2 / Portal Mini | atlas/omni | 10 | Available |
| Portal+ Gen 2 | cipher | 10 | Available |
| Portal Go | terry | 10 | Available |
| Portal TV | ripley | 9 TV | Available |

---

## Impact on Exploit Strategy

### What Still Works (WITHOUT decrypted ABL)
1. **CVE-2021-1931 DMA overflow** — The vulnerability is in the LIVE bootloader
   code running in RAM, not in the encrypted partition. We can still overflow.
2. **test0 (crash test)** — Sends ARM64 infinite-loop opcodes. No ABL offsets needed.
3. **test2/test3 (distance probing)** — PIC shellcode discovers memory layout.
   Returns buffer-to-code distance via FAIL response.
4. **Live memory dump** — After any code execution, we could craft shellcode
   to READ the decrypted ABL from RAM and send it back.

### What's Blocked
1. **test4/test5 (full exploit)** — Needs LinuxLoader base, download buffer ptr,
   exploit_continue offset — all ABL-specific offsets.
2. **test6+ (capability patching)** — Needs specific code locations in ABL.

### Blind Exploit Strategy (NEW)

The key insight: **the ABL runs DECRYPTED in RAM**. CVE-2021-1931 overwrites
live RAM pages. We can:

1. **Phase 1: Crash test** (test0) — Confirm code execution via hang
2. **Phase 2: Distance probe** (test2) — Find buffer-to-code distance
3. **Phase 3: Memory dump shellcode** — Custom PIC payload that:
   - Discovers its own position
   - Reads N bytes backwards from the code region
   - Formats them as hex in FAIL response string
   - Returns chunks of decrypted ABL code
4. **Phase 4: Reconstruct ABL** — Multiple overflows to dump entire ABL
5. **Phase 5: Full exploit** — Now we have offsets, proceed with test4+

This is more complex than xperable's approach but **doesn't require
the encrypted partition to be readable**.

### Alternative: Marcel's LinuxLoader (terry)

Marcel has an "unpacked LinuxLoader for terry" on gofile. If the terry
Portal Go uses similar ABL architecture (both are Facebook/Qualcomm),
this could serve as a reference for understanding the Portal's ABL
structure, even if offsets differ.

**Action needed:** Access gofile.io/d/t4Hh15 (requires premium or browser)

---

## Next Steps (Priority Order)

1. **Get Marcel's gofile files** — His unpacked LinuxLoader is the fastest path
2. **Ask Marcel how he got the "readable" ABL** — Key question
3. **Design blind memory dump shellcode** — Based on test2/test3 PIC pattern
4. **Run test0 on Portal** — Confirm DMA overflow → code execution
5. **Run test2 on Portal** — Get buffer-to-code distance
6. **Execute memory dump** — Read decrypted ABL from live RAM
7. **Download other device OTAs** — atlas/cipher might have different encryption
