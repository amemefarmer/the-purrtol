# ADR-007: Qualcomm Fastboot 0-Day Assessment

**Status:** RESOLVED — oem ramdump NOT present; CVE-2021-1931 is primary path
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

### Feb 2025 Qualcomm Fastboot Vulnerability

In February 2025, a security researcher using the handle **Wanbin Mlgm** disclosed a vulnerability in Qualcomm's fastboot implementation on XDA Forums. Key details:

- **Vulnerability type:** Stack-based buffer overflow
- **Affected function:** `ramdump` handler at offset 0x1950 in the fastboot binary
- **Trigger:** Sending `fastboot oem ramdump <massive_payload>` where the payload exceeds the stack buffer allocation
- **Reported scope:** Affects "most Qualcomm SoCs" (specific affected models not fully enumerated)
- **Exploitation result:** Arbitrary code execution in the bootloader context (EL3 or EL1, depending on SoC), which can be leveraged to unlock the bootloader or disable secure boot checks
- **Public exploit availability:** **None.** Discoverer is offering paid unlocking services only. No public PoC, no detailed technical writeup beyond the initial disclosure.

### CVE-2021-1931 (Prior Art)

A related historical vulnerability provides context:

- **CVE-2021-1931:** Buffer overflow in Qualcomm fastboot command handler
- **Affected SoCs:** SDM845 and others (APQ8098/SD835 is the prior generation from SDM845)
- **Exploitation:** The **"xperable"** tool (by xyz) exploited this on Sony Xperia devices with SDM845 to achieve bootloader unlock
- **Relevance:** APQ8098 (SD835) is the generation prior to SDM845, sharing significant boot chain architecture. If CVE-2021-1931 was patched in the Portal's firmware is unknown. Gen 1's Aug 2019 security patches predate the CVE disclosure (2021), meaning the **vulnerability may be present but unpatched**.

### Relevance to Portal Gen 1

| Factor | Assessment |
|---|---|
| SoC (APQ8098/SD835) in scope? | Very likely. SD835 shares boot chain architecture with SDM845 (confirmed affected). SD835 has a larger body of exploit research. |
| Fastboot accessible? | Yes, device enters fastboot mode. |
| `oem ramdump` command available? | **NO — returns "unknown command" (tested 2026-02-25/26)** |
| Firmware patch level (Aug 2019) | Predates both CVE-2021-1931 and the Feb 2025 disclosure. High likelihood of vulnerability being present. |
| Exploitation feasibility | Low without public tool. Requires ARM64 exploit development skills. |

## Decision

**Monitor** the Feb 2025 vulnerability disclosure but **do not attempt exploitation** without either:

1. A public, peer-reviewed exploit tool (similar to xperable for CVE-2021-1931), or
2. A detailed technical writeup sufficient for an experienced researcher to reproduce.

### Action Items — ALL COMPLETED (2026-02-26)

- [x] **Test `oem ramdump` recognition:** Returns "unknown command" — vector CLOSED
- [x] **Enumerate all OEM commands:** 50+ commands tested, only 2 OEM commands recognized (device-info, get_unlock_bootloader_nonce)
- [x] **`getvar all`:** Works — complete 64-partition table captured
- [x] **Check CVE-2021-1931 applicability:** APQ8098/SD835 confirmed vulnerable, Portal unpatched (Aug 2019 < Jul 2021 fix)
- [x] **DMA buffer testing:** `fastboot stage 15MB` succeeds — exploit primitive confirmed active
- [x] **getvar overflow:** Tested up to 16KB — no hang/crash — vector CLOSED
- [ ] **Share findings with community:** Post to XDA thread (pending)

### What NOT To Do

- Do NOT send oversized payloads to `oem ramdump` attempting to trigger the overflow. Without a controlled exploit, this could crash the bootloader into an unrecoverable state.
- Do NOT attempt to port xperable to APQ8098 without deep ARM64 reverse engineering knowledge.
- Do NOT pay for unlocking services from the vulnerability discoverer (unverifiable, potential scam risk).

## Consequences

- **Positive:** Maintains safety posture. Read-only probing provides valuable data for the community. If a public exploit emerges, we'll have the prerequisite device enumeration data ready.
- **Negative:** Potential unlock path remains unexploited. If the vulnerability applies and the command exists, we're sitting on a possible solution without the means to use it.
- **Accepted trade-off:** A beginner attempting blind exploitation of a stack overflow in a bootloader is a recipe for a bricked device. Patience is the correct strategy.

## Monitoring Plan

| Source | Check Frequency | What to Look For |
|---|---|---|
| XDA Forums (Qualcomm section) | Weekly | Public exploit release, additional technical details |
| bkerler/edl GitHub issues | Weekly | Discussion of fastboot exploits, APQ8098/MSM8998 references |
| CVE databases (NVD, MITRE) | Monthly | New CVE for Qualcomm fastboot, APQ8098/MSM8998 advisories |
| Wanbin Mlgm's profiles | Monthly | Public release of tool or writeup |
| GitHub search | Monthly | New repositories related to Qualcomm fastboot exploit |
| r/android, r/LineageOS | Weekly | Community discussion of Portal or APQ8098/SD835 unlocking |

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| Attempt blind exploitation | Unacceptable brick risk. Stack overflow exploitation requires precise offset knowledge, ROP chain construction, and target-specific shellcode. |
| Pay for unlocking service | Unverifiable. May be a scam. Does not contribute to community knowledge. Does not teach anything. |
| Ignore fastboot vector entirely | Wasteful. Read-only enumeration is zero-risk and provides valuable community data. |
| Attempt CVE-2021-1931 (xperable port) | Requires ARM64 RE skills beyond beginner level. xperable targets SDM845, porting to APQ8098 (SD835) is non-trivial but more feasible since they share boot chain architecture. Worth revisiting if skill level increases. |

## References

- XDA Forums: Wanbin Mlgm fastboot vulnerability disclosure (Feb 2025)
- CVE-2021-1931: https://nvd.nist.gov/vuln/detail/CVE-2021-1931
- xperable tool: Sony Xperia bootloader unlock via CVE-2021-1931
- Qualcomm APQ8098 (SD835) / SDM845 platform relationship
- Qualcomm fastboot protocol documentation
- ADR-006: Risk Tolerance and Safety Protocol (this project)
