# ADR-002: Device Considerations (Gen 1 ohana vs Gen 2 atlas)

**Status:** Accepted
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

Facebook released two generations of the Portal 10" smart display. **Contrary to initial assumptions, they use different SoCs:**

> **UPDATE (2026-02-24):** EDL/Sahara confirmed Gen 1 uses APQ8098 (Snapdragon 835). Gen 2 likely uses QCS605, a completely different chip.

| Property | Gen 1 (ohana, 2018) | Gen 2 (atlas, 2020) |
|---|---|---|
| Codename | ohana | atlas |
| SoC | **APQ8098 (Snapdragon 835)** ✅ | QCS605 (unconfirmed) |
| MSM_ID | `0x000620e1` ✅ | Unknown |
| Storage | eMMC ✅ | Likely UFS |
| Android Version | Android 9 (Pie) | Android 9 (Pie) |
| Security Patches | Aug 2019 (older) | Newer |
| Known Firehose | **None** | **Yes** (Dec 2025 .mbn) |
| Signing Chain | Potentially different | Known from firehose |
| Market Price | $10-25 used | $15-30 used |

The critical difference is the **firehose programmer availability**. The .mbn file discovered in Dec 2025 targets atlas (Gen 2) specifically. Firehose programmers are signed per-device-family, meaning the atlas .mbn will almost certainly not work on ohana.

However, Gen 1's **older firmware** (Aug 2019 security patches) is actually an advantage for exploit-based approaches. Older Android bootloaders have more known vulnerabilities, and the attack surface is larger when patches are years behind.

Gen 1 uses **eMMC** storage rather than UFS. eMMC is simpler for hardware ISP (if it comes to that) and has well-understood tooling for raw reads.

## Decision

Proceed with **Gen 1 ohana** as the primary target, but maintain awareness that **Gen 2 atlas acquisition may be the pragmatic path forward** if Gen 1 proves completely blocked.

Specifically:
- Exhaust all software-based approaches on Gen 1 first (firmware analysis, EDL probing, fastboot enumeration, exploit research).
- Document all Gen 1 findings thoroughly, as they benefit the community regardless of personal outcome.
- If Gen 1 hits a hard wall (no firehose extractable, no exploits applicable, fastboot locked tight), pivot to acquiring a Gen 2 atlas unit.

## Consequences

- **Positive:** Gen 1's older firmware increases exploit viability. eMMC is simpler for low-level access. Thorough Gen 1 documentation helps the broader Portal hacking community. Gen 1 units are cheaper.
- **Negative:** No known firehose means the standard EDL flash path is blocked. May ultimately need to purchase a second device (Gen 2).
- **Mitigation:** Gen 2 atlas units are $15-30 on eBay. Total investment remains under $50 even if both devices are acquired. All tooling and knowledge transfers between generations.

## Alternatives Considered

| Alternative | Why Not Chosen |
|---|---|
| Start with Gen 2 atlas | Premature. Already own Gen 1. Gen 1 analysis provides foundational knowledge. |
| Abandon Gen 1 entirely | Wasteful. The older firmware is an advantage for certain approaches. |
| Work both in parallel | Unnecessary cost and complexity for a beginner. Sequential approach is cleaner. |

## References

- Facebook Portal hardware teardowns (iFixit)
- Qualcomm QCS605 platform documentation
- Dec 2025 atlas firehose discovery thread
- eBay/marketplace pricing data for used Portal units
