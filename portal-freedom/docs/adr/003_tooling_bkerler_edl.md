# ADR-003: Tooling Choice -- bkerler/edl over QPST/QFIL

**Status:** Accepted
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

Communicating with a Qualcomm device in EDL (Emergency Download Mode) requires software that implements the Sahara and Firehose protocols. The main options are:

### Qualcomm QPST / QFIL (Official)
- **QPST (Qualcomm Product Support Tools)** and **QFIL (Qualcomm Flash Image Loader)** are Qualcomm's official diagnostic and flashing tools.
- Windows-only. No macOS or Linux builds exist.
- Closed-source, proprietary. Leaked/redistributed copies of varying vintage circulate online.
- Well-documented in Qualcomm's internal training materials but not publicly.
- Requires Qualcomm HS-USB QDLoader 9008 drivers (Windows).

### bkerler/edl (Open Source)
- Open-source Python tool (GPLv3) by security researcher bkerler.
- Implements Sahara handshake, Firehose XML commands, and Streaming protocol.
- Cross-platform: runs on macOS, Linux, and Windows.
- Built-in loader database with known firehose programmers.
- Actively maintained on GitHub with community contributions.
- Supports advanced operations: partition read/write/erase, GPT manipulation, peek/poke memory.

### The USB Passthrough Problem
Running QPST/QFIL on macOS requires a Windows VM (Parallels, VMware Fusion, UTM). The Qualcomm HS-USB QDLoader 9008 device must be passed through from macOS to the VM. This USB passthrough is **notoriously unreliable** for EDL devices because:
- The device enumerates briefly during the Sahara handshake window (often <2 seconds).
- VM USB passthrough adds latency that can miss the enumeration window.
- macOS may claim the device before the VM can grab it.
- Apple Silicon Macs add an additional virtualization layer (Hypervisor.framework) that complicates USB passthrough further.

## Decision

Use **bkerler/edl** as the primary EDL communication tool.

Installation path on macOS:
```
pip3 install edl
# or
git clone https://github.com/bkerler/edl && cd edl && pip3 install .
```

Dependencies (via Homebrew):
```
brew install python libusb
```

## Consequences

- **Positive:** Native macOS execution eliminates USB passthrough issues entirely. Open-source means we can inspect protocol behavior, add debug logging, and contribute fixes. Built-in loader DB may contain useful firehose references. Python codebase is readable and modifiable for a beginner.
- **Negative:** Less documentation than QPST/QFIL for basic operations. Some advanced Qualcomm-specific features (DIAG mode, NV item editing) are only available in QPST. Community support is smaller than the QPST user base.
- **Neutral:** If a Windows-only operation is ever required, QPST can still be used as a fallback via VM. The decision is about the primary tool, not exclusivity.

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| QPST/QFIL via Windows VM | USB passthrough for QDLoader 9008 is unreliable, especially on Apple Silicon. Adds unnecessary complexity. |
| QPST via Boot Camp | Requires an Intel Mac. User is on Apple Silicon (Darwin 25.2.0). Boot Camp is not available. |
| AXIOMIflash | Windows-only, closed-source, similar USB passthrough issues as QPST. |
| Heimdall | Samsung-specific tool. Not applicable to Qualcomm devices. |
| Custom Python Sahara/Firehose implementation | Reinventing the wheel. bkerler/edl already does this well. |

## References

- bkerler/edl: https://github.com/bkerler/edl
- Qualcomm Sahara protocol: Aleph Research documentation
- Qualcomm Firehose protocol: Aleph Research documentation
- QPST/QFIL: Qualcomm Product Support Tools (official, restricted distribution)
- libusb: https://libusb.info
