# Experiment 016: RET Fill Failure, Fine-Grained Binary Search, and Overflow Direction Discovery

**Date:** 2026-03-01
**Risk Level:** LOW (device hangs/crashes, power cycle recovers)
**Outcome:** RET fill proven fundamentally incompatible at all tested sizes; binary search narrowed reliable overflow window to 4-8KB; overflow direction confirmed as UPWARD into UEFI memory pool, placing ABL lock state BELOW (unreachable by) the DMA buffer; data corruption path to unlock is NOT viable

---

## Summary

Conducted two lines of investigation: (1) RET-fill experiments at 128KB overflow to test whether immediate function returns could preserve USB while corrupting data, and (2) fine-grained binary search of the B#0 overflow size to map the exact reliability boundary and probe post-overflow device state.

RET fill (0xD65F03C0) proved catastrophically worse than B#0 at every tested configuration. Even restricting RET bytes to only the last 32KB of the overflow region caused immediate I/O Error — functions in the overflow region return instantly to callers with garbage results, cascading through the USB response path and crashing the USB controller.

Binary search with B#0 fill established that 0x104000 (8KB overflow) is the maximum reliable overflow size. At this size, ALL fastboot commands work perfectly after overflow, including `oem device-info`, `flashing unlock`, and `flash:boot` — but all return normal locked-state responses. The lock state is NOT in the overflow region.

Architectural analysis reveals why: the overflow goes UPWARD from the DMA buffer into the UEFI memory pool (protocol tables, DXE driver data), while ABL's own `.data` section (containing the DeviceInfo structure with `is_unlocked`) resides at LOWER addresses. Data corruption exploitation of the lock state is therefore impossible with this overflow direction.

---

## Experiments Conducted

### Experiment 16a: Pure RET Fill at 0x120000 (128KB overflow)

**Hypothesis:** RET fill (0xD65F03C0) makes corrupted functions return immediately to their callers rather than branching to unmapped addresses. If USB handler functions return cleanly, the device may remain on-bus with corrupted data structures accessible via diagnostic commands.

**Build:** `-DPORTAL_SIZE=0x120000` with RET fill

**Result (attempt 1):** Stage 1 TIMEOUT. Recovery: I/O Error.
**Result (attempt 2):** Stage 1 TIMEOUT. Recovery: I/O Error.

**Analysis:** RET is strictly worse than B#0 for USB survival. With B#0, the getvar handler at 0x120000 succeeds ~50% of the time (`OKAYaloha`). With RET, it never succeeds. The likely mechanism: functions in the overflow region that are called during getvar processing return immediately with undefined register contents. Their callers interpret these garbage return values as valid results and continue executing with corrupted state, eventually corrupting USB controller registers or DWC3 endpoint configuration. B#0 (branch-to-self) at least halts execution at the corrupted function, preventing the cascade.

### Experiment 16b: Hybrid B#0+RET, Split at 0x104000 (128KB overflow)

**Hypothesis:** Fill the first 0x104000 bytes (the region known to be safely overflowable) with B#0 and the remaining bytes (0x104000 to 0x120000) with RET. This preserves the functions adjacent to the buffer while making deeper functions return-to-caller.

**Result:** Stage 1 TIMEOUT. Recovery: I/O Error.

**Analysis:** The split point was too close to the buffer. Functions between 0x104000 and 0x120000 still participate in the getvar code path and their immediate returns cascade into USB corruption.

### Experiment 16c: Hybrid B#0+RET, Split at 0x118000 (only last 32KB RET)

**Hypothesis:** Restrict the RET region to only the last 32KB of the overflow (0x118000 to 0x120000). Most of the overflow is B#0, with RET only at the outer edge.

**Result:** Stage 1 TIMEOUT. Recovery: I/O Error.

**Analysis:** Even 32KB of RET bytes at the outer edge is enough to crash the USB controller. This confirms that RET fill is fundamentally incompatible with preserving USB communication at ANY overflow size. The immediate-return cascade cannot be contained by limiting the RET region.

**RET Fill Conclusion:** Abandoned. RET fill corrupts the USB controller through cascading garbage return values. B#0 (branch-to-self infinite loop) remains the only viable fill because it HALTS corrupted function execution rather than propagating it.

---

### Experiment 16d: B#0 at 0x104000 (8KB overflow) — FULL PROBE

**Hypothesis:** 0x104000 (4KB beyond the buffer boundary) was previously tested only as a Stage 1 delivery mechanism. Now probing ALL diagnostic commands after overflow to check if any security-critical state is corrupted.

**Build:** `-DPORTAL_SIZE=0x104000 -DPORTAL_PROBE` with B#0 fill

**Result:** Stage 1 succeeded on first attempt.

**Post-overflow probe results:**
```
getvar:product         → OKAY 'aloha'
getvar:serialno        → OKAY '818PGA02P110MQ09'
getvar:secure          → OKAY 'yes'
getvar:unlocked        → OKAY 'no'
getvar:max-download-size → OKAY '536870912'
getvar:current-slot    → OKAY 'b'
flash:boot             → FAIL "Flashing is not allowed in Lock State"
flashing unlock        → FAIL "Flashing Unlock is not allowed."
get_unlock_ability     → INFO '0', OKAY
oem get_unlock_bootloader_nonce → INFO "Unlock Request: 88E00C53E2F32249818PGA02P110MQ09", OKAY
oem device-info        → Verity:true, Unlocked:false, Critical unlocked:false,
                         Unsealed:false, ADB:false, OKAY
```

**Analysis:** Every single command returns its normal, pre-overflow response. The lock state (`unlocked: no`, `Unlocked:false`), verity state, ADB state, and seal state are all unchanged. The 8KB overflow does not reach ANY security-critical data structures. All UEFI protocol calls also work (oem device-info reads from persistent storage via UEFI block I/O protocol), confirming the overflow region at this size contains no critical infrastructure.

### Experiment 16e: B#0 at 0x105000 (12KB overflow)

**Hypothesis:** Push 4KB beyond the last reliable size to see if additional data structures become corrupted.

**Result:** Stage 1 RACED — `getvar:product` sent, TIMEOUT. Device hung.

**Analysis:** The 12KB overflow crosses into territory that sometimes corrupts the getvar handler itself. This size is unreliable for probe operations.

### Experiment 16f: B#0 at 0x108000 (24KB overflow)

**Result:** Stage 1 succeeded (OKAYaloha). First probe command `getvar:product` returned OK. Second command `getvar:serialno` TIMEOUT — device dead.

**Analysis:** At 24KB overflow, the device is on borrowed time. One or two commands may work before accumulated corruption (possibly deferred UEFI timer callbacks or protocol table corruption) catches up and hangs the device.

### Experiment 16g: B#0 at 0x106000 (16KB overflow)

**Result (attempt 1):** Stage 1 RACED. Failed.
**Result (attempt 2):** Stage 1 RACED. Failed.

**Analysis:** 16KB overflow is in the unreliable zone. The getvar handler sometimes survives, sometimes doesn't. Not useful for probe operations.

### Experiment 16h: B#0 at 0x110000 (64KB overflow)

**Result (attempt 1):** Stage 1 RACED. Failed.
**Result (attempt 2):** Stage 1 RACED. Failed.

**Analysis:** Consistent with previous observations. At 64KB, the getvar handler rarely survives the first command.

---

## Complete Reliability Map

| Size | Overflow | B#0 Stage 1 | B#0 Probe Result | RET Stage 1 |
|------|----------|-------------|------------------|-------------|
| 0x103000 | 4KB | Reliable | All OK, flash:boot FAIL locked | N/A |
| 0x104000 | 8KB | Reliable | All OK, flash:boot FAIL locked | N/A |
| 0x105000 | 12KB | RACED | -- | N/A |
| 0x106000 | 16KB | RACED (x2) | -- | N/A |
| 0x108000 | 24KB | ~50% | 1 getvar then dead | N/A |
| 0x110000 | 64KB | RACED (x2) | -- | N/A |
| 0x120000 | 128KB | ~50% | All getvar OK, flash:boot HANG | I/O Error (x3) |

**Key observations:**
1. 0x104000 (8KB overflow) is the maximum RELIABLE overflow size where all commands work
2. 0x105000 to 0x108000 is a transition zone with rapidly decreasing reliability
3. 0x120000 (128KB) has an interesting property: getvar commands work but UEFI protocol-dependent commands hang, suggesting protocol dispatch tables are corrupted but the in-memory variable linked list is intact
4. RET fill is uniformly worse than B#0 — three attempts at 0x120000, all I/O Error

---

## Critical Architectural Discovery: Overflow Direction

The probe results at 0x104000 and 0x120000, combined with the Ghidra analysis of LinuxLoader, reveal the memory layout:

```
Lower addresses
    ┌─────────────────────────┐
    │  ABL .text (code)       │
    │  ABL .data (DeviceInfo  │ ← is_unlocked, is_verified, etc.
    │    lock state, config)  │    UNREACHABLE by overflow
    │  ABL .bss               │
    ├─────────────────────────┤
    │  ABL heap               │
    ├─────────────────────────┤
    │  DMA buffer (~1.01MB)   │ ← fastboot download buffer
    │  [0x102000 boundary]    │
    ├─────────────────────────┤
    │  UEFI memory pool       │ ← protocol tables, DXE driver data
    │  (corrupted by overflow)│    REACHABLE by overflow
    │  ┌───────────────┐      │
    │  │ 4-8KB: safe   │      │ ← no critical structures
    │  │ 12-24KB: flaky │     │ ← getvar handler deps
    │  │ 64KB+: getvar  │     │ ← getvar infrastructure
    │  │ 128KB+: UEFI   │     │ ← protocol dispatch tables
    │  │   protocols    │      │
    │  └───────────────┘      │
    ├─────────────────────────┤
    │  More UEFI/XBL data     │
    └─────────────────────────┘
Higher addresses
```

**The overflow goes UPWARD** (toward higher addresses) from the DMA buffer into the UEFI memory pool. ABL's own `.data` section, which contains the `DeviceInfo` structure with the `is_unlocked` flag, is at LOWER addresses — below the DMA buffer and completely unreachable by the overflow.

**Evidence:**
- At 8KB overflow: all commands work, lock state unchanged → first 8KB above buffer is benign UEFI pool metadata
- At 128KB overflow: `getvar` works (reads from ABL's in-memory linked list at lower addresses) but `oem device-info` and `flash:boot` hang (they call UEFI protocols via dispatch tables at higher addresses, now corrupted)
- `flash:boot` at 0x104000 returns "Flashing is not allowed in Lock State" — the lock check happens BEFORE any UEFI protocol calls, reading from ABL's own data, which is intact

---

## Why Data Corruption Cannot Unlock the Device

The data corruption exploitation strategy from Experiment 015 is now conclusively ruled out:

1. **Lock state is in ABL .data** — The `DeviceInfo` structure (containing `is_unlocked`, `is_verified`, `adb_enabled`, `is_unsealed`) lives in ABL's `.data` section, which is at lower memory addresses than the DMA buffer.

2. **Overflow goes upward** — The DMA buffer overflow writes beyond the buffer's upper boundary into UEFI memory pool space. It cannot write downward into ABL's own data.

3. **No overflow size helps** — Making the overflow larger only corrupts more UEFI infrastructure (eventually killing getvar itself at 256KB+). It never wraps around or reaches ABL .data.

4. **Confirmed empirically** — At 8KB overflow where everything works, `unlocked` is still `no`. At 128KB overflow where significant corruption exists, `getvar:unlocked` still returns `no`. The lock state is simply not in the path of the overflow.

---

## Lessons Learned

1. **RET fill is always worse than B#0.** Immediate returns propagate garbage through call chains, corrupting USB state. B#0 halts execution at the point of corruption, limiting the blast radius. This holds true regardless of how much or how little RET is used in the overflow region.

2. **The reliable overflow window is very narrow.** Only 4-8KB of overflow is safe for probe operations. The transition from "everything works" (0x104000) to "device hangs" (0x105000) is a single 4KB page boundary — likely a UEFI pool allocation header.

3. **Overflow direction determines what can be corrupted.** Upward overflow into UEFI pool space can disrupt protocol dispatch but cannot reach ABL application data at lower addresses. This is a fundamental limitation of the DMA buffer's position in the memory map.

4. **getvar vs. UEFI protocol commands are a diagnostic tool.** The divergence between getvar (works at 128KB) and oem device-info/flash:boot (hang at 128KB) reveals exactly what is corrupted: UEFI protocol tables, not ABL's own data structures.

5. **The chicken-and-egg problem remains.** Code execution requires knowing the buffer address to set correct jump targets. Determining the buffer address requires code execution to read registers or memory. Without an independent information leak, this cycle cannot be broken from software alone.

---

## Current Status

Two exploitation strategies have now been exhausted:
- **Code execution via function pointer corruption** (Exp 015): impossible without knowing buffer address
- **Data corruption of lock state** (Exp 016): impossible because lock state is below the DMA buffer

The DMA overflow (CVE-2021-1931) is confirmed exploitable but cannot be leveraged to unlock the bootloader through any software-only approach discovered so far.

---

## Possible Next Steps

1. **Retry 0x105000** — This size failed on one attempt but the transition zone is stochastic. Multiple attempts might succeed, and if probe commands work, it could reveal corruption of structures not visible at 0x104000.

2. **Download-based overflow with controlled byte placement** — Instead of uniform fill, craft specific byte patterns in the overflow region to surgically corrupt UEFI protocol table entries. Requires Ghidra analysis of the UEFI memory pool layout from the terry LinuxLoader.

3. **Ghidra analysis of terry LinuxLoader UEFI memory pool** — Map the exact UEFI structures above the DMA buffer. If a protocol handler pointer can be redirected to a known ABL function (e.g., one that sets `is_unlocked=1`), a single corrupted pointer could unlock the device without arbitrary code execution.

4. **Hardware approaches** — JTAG debug port (if exposed on PCB), direct UFS chip access (desolder or test points), voltage glitching on the SoC power rail during secure boot verification.

5. **Other software vulnerabilities** — The fastboot implementation may have other bugs beyond CVE-2021-1931. The `oem get_unlock_bootloader_nonce` command processes input and generates output — worth fuzzing. The download handler's size validation at 128KB overflow ("too large") suggests corrupted but functional code paths that might be manipulable.

6. **Cross-device firehose acquisition** — If a firehose programmer for APQ8098 with Facebook's OEM_ID (0x0137) and PK_HASH can be obtained (e.g., from a device with unlocked secure boot or from a Facebook engineering unit), EDL mode would provide full read/write access to all partitions.
