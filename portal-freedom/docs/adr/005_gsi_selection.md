# ADR-005: GSI Selection Criteria

**Status:** Confirmed (partition layout verified from firmware dump)
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

A **Generic System Image (GSI)** is an Android system image that can boot on any Project Treble-compliant device. The Facebook Portal runs Android 9 (Pie), which includes mandatory Treble support, meaning the hardware vendor (HAL) layer is separated from the Android framework.

Key device properties relevant to GSI selection:

| Property | Value | Source |
|---|---|---|
| SoC | APQ8098 (Snapdragon 835) | Confirmed via EDL/Sahara |
| Architecture | ARM64 (aarch64) | Confirmed (`ro.product.cpu.abi=arm64-v8a`) |
| Android Version | 9 (Pie) | Confirmed (`ro.build.version.release=9`) |
| Treble Support | Yes | Confirmed (`ro.treble.enabled=true`) |
| Partition Scheme | **A/B** | **Confirmed** (`ro.build.ab_update=true`, `slotselect` in fstab) |
| System-as-root | **Yes** | **Confirmed** (`ro.build.system_root_image=true`) |
| VNDk version | **28** | **Confirmed** (`ro.vndk.version=28`) |
| Board platform | msm8998 | Confirmed (`ro.board.platform=msm8998`) |
| OEM unlock | Supported (locked) | Confirmed (`ro.oem_unlock_supported=1`) |

### Partition Scheme: A/B vs A-only

This is the **critical unknown**. Android devices use one of two partition layouts:

- **A/B (seamless updates):** Two copies of each partition (system_a/system_b, boot_a/boot_b). Updates install to the inactive slot. Higher-end devices and those with OTA updates typically use A/B.
- **A-only:** Single copy of each partition. Simpler but no seamless updates.

The Portal likely uses **A/B** (Facebook pushed OTA updates, and Qualcomm reference designs for APQ8098/SD835 default to A/B), but this must be confirmed via:
- Firmware analysis (GPT partition table from extracted OTA)
- `fastboot getvar all` output
- `adb shell cat /proc/cmdline` (if adb is accessible)

### GSI Variant Matrix

GSIs are built in variants based on:
1. **Architecture:** arm, arm64, x86, x86_64
2. **Partition scheme:** a (A-only), ab (A/B)
3. **GApps:** vanilla (no Google apps) vs gapps (with Google apps)
4. **Android version:** 11, 12, 12L, 13, 14, etc.

### Prior Art

An **Android 12L GSI** was reportedly demonstrated on a prototype Portal device. Android 12L is optimized for large-screen devices (tablets, foldables), making it particularly suitable for the Portal's 10" display.

## Decision

Target **phhusson's AOSP GSI** (TrebleDroid/lineage-phh), **arm64** variant, matching the Portal's partition scheme (expected A/B).

Selection criteria, in priority order:

1. **Architecture:** arm64 (mandatory, APQ8098 is ARM64)
2. **Partition scheme:** Must match device (confirm A/B vs A-only before flashing)
3. **Android version:** 12L preferred (large-screen optimizations, demonstrated on Portal prototype)
4. **GApps:** Vanilla (no GApps) first for stability testing; GApps variant after successful boot
5. **System-as-root:** Required (expected for Android 9+ base)
6. **Source:** phhusson's builds (most widely tested, best community support)

### Expected GSI filename pattern
```
system-roar-arm64-ab-vanilla.img.xz    # if A/B
system-roar-arm64-a-vanilla.img.xz     # if A-only
```
(where "roar" or similar is the Android 12L codename in phhusson's naming)

## Consequences

- **Positive:** phhusson's GSIs are the most broadly tested. arm64 vanilla is the most stable starting point. Android 12L's large-screen UI is ideal for a 10" display. Vanilla (no GApps) reduces variables during initial testing.
- **Negative:** Vanilla GSI lacks Google Play Store and services. Some hardware features (camera, microphone array, touch screen calibration) may not work without Portal-specific HAL tweaks. Display scaling may need manual adjustment.
- **Risks:** If the Portal's vendor partition has unusual HAL implementations, even a Treble-compliant GSI may fail to boot or have significant hardware breakage.

## Open Questions (Blocking)

- [ ] Confirm A/B vs A-only partition scheme
- [ ] Confirm system-as-root configuration
- [ ] Confirm VNDK version
- [ ] Verify super partition existence and size (dynamic partitions?)
- [ ] Test whether vendor partition from stock firmware is compatible with AOSP GSI

## Alternatives Considered

| Alternative | Why Not Primary |
|---|---|
| LineageOS device-specific build | No official LineageOS support for Portal. Would require full device tree port. |
| postmarketOS | Primarily targets Linux (not Android). Different ecosystem, less app compatibility. |
| Android 13/14 GSI | Less tested on Android 9 vendor bases. 12L has better Treble backward compatibility. |
| GApps variant first | Adds complexity. Debug vanilla first, then add GApps. |
| microG instead of GApps | Good privacy-focused option for later. Not relevant for initial boot testing. |

## References

- phhusson's TrebleDroid: https://github.com/nicene-lacmb/treble_experimentations
- Google GSI builds: https://developer.android.com/topic/generic-system-image/releases
- Project Treble documentation: https://source.android.com/docs/core/architecture/treble
- Android 12L features: https://developer.android.com/about/versions/12/12L
- Portal 12L demonstration (community reports)
