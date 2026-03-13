# Sanitization Report — Sensitive Data Audit

**Date:** 2026-03-13
**Scope:** All files in `portal-freedom/`, plus `.claude/` project files
**Files scanned:** ~204 source files, 31 journal entries, 12+ log files, build caches, configs, plans
**Status:** AUDIT ONLY — no files modified

---

## Summary

| Severity | Count | Action Required |
|----------|-------|-----------------|
| **HIGH** | 3 | Must redact before any sharing |
| **MEDIUM** | 8 | Should redact before public sharing |
| **LOW** | 9 | Optional; redact if strict privacy needed |
| **FLAG FOR REVIEW** | 3 | Ambiguous — needs your judgment |

---

## HIGH SEVERITY — Must Redact

### H1. Facebook Graph API Access Token

| | |
|---|---|
| **Type** | API credential (app_id\|app_secret format) |
| **Value** | `217151932108113\|b781e66b808395cdc617f00b785384c7` |
| **Location** | `journal/009_ota_analysis_encrypted_abl.md` line ~28 |
| **Context** | Embedded in Facebook Graph API URL for OTA firmware download |
| **Risk** | Allows API calls as that application; could be revoked/abused |
| **Redaction** | Replace with `<REDACTED_FB_ACCESS_TOKEN>` |

### H2. Device Serial Number

| | |
|---|---|
| **Type** | Hardware serial number (uniquely identifies this specific Portal unit) |
| **Value** | `818PGA02P110MQ09` |
| **Locations** | |

| File | Lines |
|------|-------|
| `journal/005_fastboot_breakthrough.md` | 36, 64-65, 152-153 |
| `journal/016_ret_fill_and_fine_grained_binary_search.md` | 69, 73 |
| `journal/018_addr_spray_breakthrough.md` | 62 |
| `journal/fastboot_getvar_all.txt` | 220 |
| `journal/fastboot_unlock_nonce.txt` | 1 |

| **Risk** | Ties all research to one physical device; could be used for warranty/support harassment |
| **Redaction** | Replace with `<DEVICE_SERIAL>` everywhere |

### H3. SoC / EDL Serial Number

| | |
|---|---|
| **Type** | Chip-level serial (uniquely identifies this specific SoC) |
| **Value** | `0x6bb67469` |
| **Locations** | |

| File | Lines |
|------|-------|
| `journal/001_edl_sahara_query.md` | 75 |
| `docs/research/qcs605_reference.md` | 39 |

| **Risk** | Uniquely identifies the individual chip |
| **Redaction** | Replace with `<EDL_SERIAL>` |

---

## MEDIUM SEVERITY — Should Redact Before Public Sharing

### M1. Bootloader Unlock Nonces

| | |
|---|---|
| **Type** | Cryptographic challenge tokens (ephemeral, but contain serial) |
| **Values** | `D1B469083E0E08E5818PGA02P110MQ09`, `5362BF7B992BA33D818PGA02P110MQ09`, `88E00C53E2F32249818PGA02P110MQ09`, `173A00D542E56FE7...` |
| **Locations** | `journal/005` (lines 64-65, 152-153), `journal/016` (line 73), `journal/018` (line 69), `journal/fastboot_unlock_nonce.txt` |
| **Redaction** | Replace with `<UNLOCK_NONCE><DEVICE_SERIAL>` |

### M2. Local Username in Filesystem Paths

| | |
|---|---|
| **Type** | macOS username (`vibebox`) leaked via absolute paths |
| **Pattern** | `/Users/vibebox/Documents/Facebook_Portal/...` |
| **Locations (high-count files)** | |

| File | Occurrences |
|------|-------------|
| `tools/xperable/pe-parse/build-native/CMakeCache.txt` | 25+ lines |
| `tools/xperable/pe-parse/build-native/TargetDirectories.txt` | 21 lines |
| `tools/xperable/pe-parse/build-native/InstallScripts.json` | 3 lines |
| `firmware/analysis/analyze_linuxloader.py` | lines 28-29 |
| `firmware/analysis/python_analysis_output.txt` | lines 738-739 |
| `.claude/projects/.../memory/MEMORY.md` | line 4 |

| **Redaction** | Replace `/Users/vibebox` with `<USER_HOME>` or use relative paths |

### M3. Local Tool Paths Revealing Username

| | |
|---|---|
| **Type** | Home-directory tool paths |
| **Pattern** | `~/portal-tools/edl/.venv` |
| **Locations** | |

| File | Lines |
|------|-------|
| `journal/001_edl_sahara_query.md` | 20, 63 |
| `journal/004_firehose_search_and_strategy_pivot.md` | 42 |
| `scripts/edl/backup_all_partitions.sh` | 25 |
| `scripts/edl/flash_partition.sh` | 31 |
| `scripts/edl/query_device_info.sh` | 28-29 |
| `scripts/setup/setup_bkerler_edl.sh` | 35-36 |
| `scripts/setup/verify_environment.sh` | 76-77 |

| **Redaction** | Replace `~/portal-tools/edl/.venv` with `<EDL_VENV_PATH>` in docs; use `$EDL_VENV` env variable in scripts |

### M4. Local Network IP Addresses

| | |
|---|---|
| **Type** | RFC1918 private IPs from test network |
| **Values** | `192.168.2.1` (Mac bridge), `192.168.2.2` (Portal DHCP), `172.20.10.4` (iPhone tethering) |
| **Locations** | |

| File | Context |
|------|---------|
| `captive-portal/dnsmasq.conf` | lines 13, 16 |
| `captive-portal/setup_hotspot.sh` | bridge IP references |
| `captive-portal/payloads/post_exploit.sh` | line 12 (ADB connect IP) |
| `journal/020_captive_portal_setup.md` | lines 97, 124 |
| `captive-portal/logs/*.jsonl` (all 12 files) | Client IP `192.168.2.2` in every request |
| `captive-portal/logs/user_agents.txt` | All ~500KB of entries |

| **Redaction** | Replace with `<BRIDGE_IP>`, `<DEVICE_IP>`, `<TETHERING_IP>` in docs/configs. In scripts, use variables (e.g., `$BRIDGE_IP`). |

### M5. HTTP Request Logs (Full Device Fingerprint Data)

| | |
|---|---|
| **Type** | Complete HTTP headers, timestamps, client IPs, User-Agent strings, exploit stage reports |
| **Location** | `captive-portal/logs/` directory (12 JSONL files + 1 TXT, totaling ~800KB) |
| **Files** | `requests_2026-03-03.jsonl` through `requests_2026-03-13.jsonl`, `user_agents.txt`, `exploit_reports.jsonl`, `device_reports.jsonl` |
| **Risk** | Contains device fingerprint, connection timestamps, exploit test results with exact timing |
| **Redaction** | Add entire `captive-portal/logs/` to `.gitignore`. Do NOT include in any public repo. If log examples needed, create sanitized samples. |

### M6. Facebook Graph API OTA Endpoint URL

| | |
|---|---|
| **Type** | Full API URL with embedded access token |
| **Value** | `https://graph.facebook.com/mobile_release_updates?access_token=217151932108113\|b781e66b808395cdc617f00b785384c7&...` |
| **Location** | `journal/009_ota_analysis_encrypted_abl.md` lines 26-28 |
| **Redaction** | Replace full URL with `https://graph.facebook.com/mobile_release_updates?access_token=<REDACTED>&...` |

### M7. Device-Specific Kernel Addresses (Pre-KASLR)

| | |
|---|---|
| **Type** | Kernel symbol addresses from this device's specific firmware build |
| **Values** | e.g., `selinux_enforcing=0xffffff800a925a94`, `epi_cache=0xffffff800a6174b8`, etc. |
| **Locations** | `journal/020`, `journal/024`, `journal/026`, `journal/028`, `journal/029`, `captive-portal/payloads/portal_offsets.h` (all 152 lines) |
| **Risk** | Device-firmware-specific but not personally identifying. However, these are the exact offsets needed to exploit THIS firmware build. |
| **Redaction** | **FLAG FOR REVIEW** — these are integral to the technical documentation. Redacting them removes the research value. See Flag F1 below. |

### M8. Build/Firmware Identifier Strings

| | |
|---|---|
| **Type** | Android build fingerprint, security patch level, build ID |
| **Values** | `aloha_prod-user`, `PKQ1.191202.001`, `2019-08-01`, `Chrome/86.0.4240.198` |
| **Locations** | `journal/020` (User-Agent), `journal/003`, MEMORY.md, multiple journal entries |
| **Risk** | Identifies exact firmware version. Publicly known for Portal devices, but confirms your device hasn't been updated. |
| **Redaction** | Optional — these are class-level identifiers, not personal |

---

## LOW SEVERITY — Optional Redaction

### L1. Wi-Fi SSID

| | |
|---|---|
| **Value** | `PortalNet` |
| **Locations** | `journal/020` (lines 122-128), `journal/021` (line 19), `captive-portal/setup_hotspot.sh` (line 318) |
| **Redaction** | Replace with `<TEST_SSID>` or leave as-is (purpose-built test network, not a home SSID) |

### L2. USB Vendor/Product IDs

| | |
|---|---|
| **Values** | `0x2EC6:0x1800` (Facebook Portal fastboot), `0x05C6:0x9008` (Qualcomm EDL), `0x2EC6:0x1801` (Facebook ADB) |
| **Locations** | 8+ files including `tools/xperable/xperable.c` (line 1411), `journal/001`, `journal/012`, MEMORY.md |
| **Redaction** | Not needed — class-level identifiers, same for all Portal Gen 1 devices |

### L3. Device-Class Identifiers (HWID, MSM_ID, OEM_ID, MODEL_ID, PK_HASH)

| | |
|---|---|
| **Values** | `HWID=0x000620e10137b8a1`, `MSM_ID=0x000620e1`, `OEM_ID=0x0137`, `MODEL_ID=0xb8a1`, `PK_HASH=0x7291ef5c...988b4a3f` |
| **Locations** | 15+ files (`journal/001`, `journal/004`, `docs/research/qcs605_reference.md`, `docs/research/hardware_id_guide.md`, MEMORY.md, etc.) |
| **Redaction** | Not needed — these identify the device MODEL (all Portal Gen 1 units share them), not the individual unit |

### L4. Homebrew / Tool Installation Paths

| | |
|---|---|
| **Values** | `/opt/homebrew/bin/cmake`, `/opt/homebrew/bin/ghidraRun`, `/opt/homebrew/Cellar/ghidra/12.0.3/...`, `/opt/homebrew/opt/libusb/...` |
| **Locations** | `CMakeCache.txt`, `journal/008`, `journal/011`, various scripts |
| **Redaction** | Low priority — reveals macOS ARM64 with Homebrew (common setup). Redact CMakeCache.txt via `.gitignore` for build-native/ |

### L5. Third-Party Usernames (XDA Community Members)

| | |
|---|---|
| **Values** | `Marcel (@MarcelD505)`, `marcel505`, `Leapon` |
| **Locations** | `README.md` (line 76), `journal/004` (lines 87-88), `journal/005` (line 308), `journal/006` (line 127), `journal/009` (line 10), `journal/010` (line 11), `docs/research/exploit_adaptation_guide.md` (line 97) |
| **Redaction** | Consider replacing with `<XDA_USER>` if they haven't consented to being named in this context |

### L6. Process IDs and Runtime Addresses from Device Tests

| | |
|---|---|
| **Values** | PIDs: 15555, 4795, 4949, 4866, 5082, 5486, 5028, etc. Wasm_mem addresses: 0x33ec0000, 0x5a780000, etc. |
| **Locations** | `journal/021` (line 157), `journal/027` (lines 23, 41-42), `journal/028` (lines 12, 15), `journal/029` (line 87) |
| **Redaction** | Not needed — ephemeral ASLR-randomized values, change every run |

### L7. Network Interface Names

| | |
|---|---|
| **Values** | `en8` (iPhone USB), `bridge100`/`bridge101` (macOS bridge), `ap1` (WiFi AP) |
| **Locations** | `journal/020` (lines 120-127), `dnsmasq.conf`, `setup_hotspot.sh` |
| **Redaction** | Low priority — standard macOS interface names |

### L8. OTA File Hashes

| | |
|---|---|
| **Value** | `SHA-256: 0287084025af63af4063afe2022e81a9bba52d4bd32f011614a441da5ca4297c` |
| **Location** | `journal/009_ota_analysis_encrypted_abl.md` line 33 |
| **Redaction** | Not needed — identifies firmware file, not person |

### L9. dm-verity Key ID

| | |
|---|---|
| **Value** | `veritykeyid=id:e36e29643be137513034d96a5b5a8209e4464d20` |
| **Location** | `tools/firmware/aloha/boot/info.txt` line 3 |
| **Redaction** | Not needed — class-level (same for all units with this firmware) |

---

## FLAGGED FOR REVIEW — Needs Your Judgment

### F1. Kernel Addresses in `portal_offsets.h` and Journals

The file `captive-portal/payloads/portal_offsets.h` (152 lines) and multiple journal entries contain exact pre-KASLR kernel addresses for this firmware build. These are technically required for the exploit to work and are integral to the research documentation, but they also lower the bar for anyone targeting the same firmware.

**Options:**
- A) Leave as-is (standard in security research publications)
- B) Redact values, keep symbol names (readers would need to extract offsets themselves)
- C) Move to a separate `offsets.dat` file excluded from public sharing

### F2. Unrelated Project Names in Claude Plans

Two plan files in `~/.claude/plans/` reference unrelated projects:
- `quirky-enchanting-pillow.md` — references a `netpulse` project (Telegram scraping)
- `cheeky-rolling-blum.md` — references a `meshy_pipeline` project (3D mesh)

These aren't in the portal-freedom repo but reveal other work on this machine.

**Options:**
- A) Ignore (these files won't be in a portal-freedom repo)
- B) Delete the plan files if the projects are complete

### F3. `captive-portal/logs/exploit_reports.jsonl` (1,589 lines, 293KB)

Contains timestamped exploit test results with exact status codes, PIDs, UIDs, and kernel data from every device test run. This is a detailed operational log.

**Options:**
- A) Exclude entirely from any public sharing (`.gitignore`)
- B) Include a sanitized sample (5-10 representative entries, stripped of timestamps)
- C) Include as-is (standard for research reproducibility)

---

## Recommended `.gitignore` Additions

```gitignore
# Build artifacts (contain absolute paths)
tools/xperable/pe-parse/build-native/

# Logs (contain device fingerprints, timestamps, IPs)
captive-portal/logs/

# Firmware dump (large, contains device-specific data)
tools/firmware/

# Analysis outputs with hardcoded paths
firmware/analysis/python_analysis_output.txt
```

---

## Redaction Placeholders (Reference Table)

| Placeholder | Replaces |
|-------------|----------|
| `<REDACTED_FB_ACCESS_TOKEN>` | `217151932108113\|b781e66b808395cdc617f00b785384c7` |
| `<DEVICE_SERIAL>` | `818PGA02P110MQ09` |
| `<EDL_SERIAL>` | `0x6bb67469` |
| `<UNLOCK_NONCE>` | `D1B469083E0E08E5`, `5362BF7B992BA33D`, etc. |
| `<BRIDGE_IP>` | `192.168.2.1` |
| `<DEVICE_IP>` | `192.168.2.2` |
| `<TETHERING_IP>` | `172.20.10.4` |
| `<USER_HOME>` | `/Users/vibebox` |
| `<EDL_VENV_PATH>` | `~/portal-tools/edl/.venv` |
| `<TEST_SSID>` | `PortalNet` |
| `<XDA_USER>` | `Marcel (@MarcelD505)` |

---

## Files Requiring No Changes

The following file categories were audited and found clean:
- All `.s` / `.S` assembly payloads (contain only code, no PII)
- `captive-portal/www/exploit/rce_chrome86.html` (no PII, only exploit code)
- `captive-portal/www/index.html` (no PII)
- `captive-portal/server.py` (binds `0.0.0.0`, no hardcoded secrets)
- All reference exploit files under `payloads/cve-*-reference/` (third-party code, no local PII)
- `stage2_kernel.c` (uses offset defines, no hardcoded paths)
- Bluetooth MAC addresses in firmware (`system/etc/bluetooth/interop_database.conf`) — stock AOSP interop database, not user-specific

---

*Generated by security audit on 2026-03-13. Review all flagged items before proceeding.*
