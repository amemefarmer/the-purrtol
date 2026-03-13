# ADR-001: Primary Approach Selection

**Status:** Accepted
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

Multiple approaches exist for repurposing the Facebook Portal 10" Gen 1 (2018, codename **ohana**, **APQ8098 / Snapdragon 835 SoC**) into a general-purpose Android tablet:

> **UPDATE (2026-02-24):** EDL/Sahara interrogation confirmed the SoC is APQ8098 (Snapdragon 835), not QCS605 as previously assumed. This significantly expands the available research and exploit community (Galaxy S8, Pixel 2, OnePlus 5 use the same silicon).

- **EDL + Firehose programmer:** The standard Qualcomm Emergency Download Mode approach requires a signed firehose programmer (.mbn) matched to the device. The only known firehose programmer (discovered Dec 2025) is for the **Gen 2 atlas**, not Gen 1 ohana. Without a verified Gen 1 firehose, EDL operations beyond Sahara handshake are blocked.
- **Bootloader exploit:** Gen 1 ships with older firmware (Android security patches from Aug 2019), which makes it a stronger candidate for known Qualcomm bootloader vulnerabilities. However, exploiting these requires ARM64 reverse engineering skills beyond beginner level.
- **Dev unit reverse engineering:** Acquiring a developer/prototype unit with unlocked bootloader would bypass security entirely, but availability is extremely limited.
- **Hardware ISP (In-System Programming):** Direct eMMC access via test points on the PCB. Provides full read/write but requires micro-soldering equipment and risks physical damage.
- **GSI flash via fastboot:** If the bootloader can be unlocked, a Generic System Image can be flashed directly. Requires bootloader unlock first.

## Decision

Prioritize a **zero-risk offline firmware analysis first**, then **EDL exploration**, then **fastboot probing**. Do not attempt bootloader exploits or hardware ISP without community guidance.

The phased approach is:

1. **Phase 1 (Zero Risk):** Download and analyze OTA firmware offline. Extract partition table, identify signing schemes, locate potential firehose candidates, map the partition layout.
2. **Phase 2 (Read-Only):** Connect device via USB, probe EDL mode (Sahara handshake), enumerate fastboot commands, read device info. No writes.
3. **Phase 3 (Reversible Write):** Only after full backup and community validation, attempt partition modifications using verified tools.
4. **Phase 4 (Advanced):** Bootloader exploits or hardware ISP only with explicit community guidance and detailed writeups.

## Consequences

- **Positive:** Minimizes brick risk. Builds knowledge progressively. Offline analysis may reveal a Gen 1 firehose or signing weakness. Beginner-friendly progression.
- **Negative:** Slower than jumping directly to EDL or exploit attempts. May hit a dead end if Gen 1 has no extractable firehose and no applicable exploits.
- **Neutral:** All offline analysis work transfers to Gen 2 if a pivot becomes necessary.

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| Jump straight to EDL | Risky without a verified Gen 1 firehose programmer. Could soft-brick if wrong .mbn is loaded. |
| Attempt bootloader exploit immediately | Requires ARM64 reverse engineering beyond beginner skill level. High brick risk without understanding the specific bootloader version. |
| Hardware ISP first | Requires micro-soldering equipment and skills. Physical damage risk to a device that may be unlockable via software. |
| Buy Gen 2 atlas instead | Valid fallback but premature. Gen 1 analysis may succeed and the knowledge gained applies broadly. |

## References

- bkerler/edl GitHub repository: https://github.com/bkerler/edl
- Qualcomm EDL/Sahara/Firehose protocol documentation (Aleph Research)
- XDA Forums: Facebook Portal hacking threads
- Qualcomm APQ8098 / MSM8998 (Snapdragon 835) documentation
