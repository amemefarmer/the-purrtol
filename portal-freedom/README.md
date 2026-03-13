# Portal Freedom

**Repurposing a Facebook Portal Gen 1 into a general-purpose Android tablet.**

Meta discontinued the Portal line in 2022 and has been stripping features since. These devices contain excellent hardware (APQ8098 / Snapdragon 835 SoC, 13MP camera, 8-mic array, 10" display) — currently rotting as e-waste. This project documents every approach to unlocking them.

> **Key Discoveries (2026-02-24 → 02-26):**
> - Portal Gen 1 uses **APQ8098 (Snapdragon 835)**, not QCS605. Confirmed via EDL/Sahara.
> - Storage is **UFS** (not eMMC). Confirmed via fastboot.
> - **Fastboot accessible** via 3-button hold (Power + Vol Up + Mute through multiple screens).
> - Device is **vulnerable to CVE-2021-1931** (ABL buffer overflow, unpatched Aug 2019 < Jul 2021 fix).
> - USB DMA buffer accepts 15MB+ payloads — exploit primitive confirmed active.
> - **ABL binary not in firmware dump** — this is the sole remaining blocker.

## Quick Start

```bash
# 1. Set up your environment (macOS)
./scripts/setup/install_dependencies.sh
./scripts/setup/setup_bkerler_edl.sh
./scripts/setup/verify_environment.sh

# 2. Download and analyze firmware OFFLINE (zero risk)
./scripts/firmware/download_firmware.sh ohana
./scripts/firmware/analyze_boot_img.sh tools/firmware/ohana/boot.img

# 3. Connect your Portal and explore (read-only, low risk)
./scripts/edl/detect_edl_device.sh
./scripts/fastboot/query_fastboot_vars.sh
```

## Device Support

| Model | Gen | Codename | Firehose Available | Status |
|-------|-----|----------|-------------------|--------|
| Portal 10" | Gen 1 (2018) | aloha/ohana | No | Primary target |
| Portal+ | Gen 1 (2018) | — | No | Similar hardware |
| Portal 10" | Gen 2 (2019) | omni/atlas | Yes (Dec 2025) | Best odds |
| Portal Go | — | terry | No | Untested |

## Safety Protocol

This project follows a strict risk hierarchy:

1. **ZERO RISK** operations first (offline analysis, tool setup)
2. **READ-ONLY** device operations next (EDL info query, fastboot getvar)
3. **REVERSIBLE WRITE** operations only after full backup
4. **IRREVERSIBLE** operations only after explicit confirmation

Every script that writes to the device requires typing `YES` to confirm. Every script supports `--dry-run`.

**Back up EVERYTHING before modifying ANYTHING.**

## Project Structure

```
docs/research/    Technical research and reference material
docs/guides/      Step-by-step beginner-friendly guides (numbered 00-08)
docs/adr/         Architecture Decision Records (why we chose what)
scripts/setup/    Environment setup automation
scripts/edl/      Qualcomm EDL mode tools
scripts/fastboot/ Android fastboot mode tools
scripts/firmware/ Offline firmware analysis
scripts/boot_img/ Boot image modification
tools/            Firehose files, firmware dumps, Docker
backups/          Partition backups (not in git)
risk/             Risk assessment and recovery procedures
journal/          Experiment logs
```

## Approaches (Ranked by Feasibility) — Updated 2026-02-26

| # | Approach | Probability | Effort | Risk | Status |
|---|----------|------------|--------|------|--------|
| 1 | **CVE-2021-1931 ABL exploit** | 70% if ABL obtained | Very High | Medium | DMA confirmed; need ABL binary |
| 2 | Developer unit ABL dump | 40% | Low (for us) | None | Need to contact Marcel (@MarcelD505) |
| 3 | OTA update interception | 20% | Medium | Low | Untested |
| 4 | EDL + Firehose Flash | 10%* | Medium | Medium-High | No firehose exists publicly |
| 5 | Hardware ISP / Direct UFS Read | 80% | Extreme | Very High | Last resort |
| 6 | GSI Flash (post-unlock) | 90% | Low | Low | Blocked until bootloader unlocked |

*No firehose programmer exists for APQ8098 + Facebook OEM_ID 0x0137 (exhaustively searched)

## Community Resources

- **XDA Thread**: [Portal Hacking Discussion](https://xdaforums.com/t/anyone-been-able-to-do-anything-with-a-facebook-portal.3878505/)
- **Firmware Dumps**: dumps.tadiphone.dev/dumps/facebook
- **bkerler/edl**: github.com/bkerler/edl (primary EDL tool)
- **Reddit**: r/FacebookPortal

## Contributing

Found the ABL binary? Have a developer Portal? Please share. The community's most urgent needs:

1. **ABL partition dump** (`abl_a` or `abl_b`, 1MB) from ANY Portal 10" Gen 1 — this is the critical blocker
2. A firehose .mbn for APQ8098 + Facebook OEM key (PK_HASH: `7291ef5c...`)
3. ARM64 RE help adapting xperable/CVE-2021-1931 exploit to Facebook's ABL
4. OTA update URLs or cached update packages that include bootloader partitions
5. Anyone with a developer unit willing to dump partitions via ADB root
