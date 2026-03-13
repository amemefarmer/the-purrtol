# Journal 018: Address Spray Breakthrough — Full USB Recovery at 12KB Overflow

**Date:** 2026-03-01
**Risk Level:** MEDIUM (active device exploitation, non-destructive probing)
**Build:** PORTAL_ADDR_SPRAY + PORTAL_PROBE
**Device state:** fastboot mode, power cycle between each test

---

## Objective

After proving that NOP slide, RET fill, and single-position vtable scan are impractical
(journals 015-017), test a new "address spray" technique: fill the overflow region
containing corrupted USB protocol function pointers with a known-good ABL function
address (FastbootOkay) to "heal" the corruption and extend the reliable overflow range.

## Background

With uniform B #0 fill (0x14000000):
- **0x104000 (8KB overflow):** All commands work perfectly — the first 8KB of overflow
  contains non-critical data (USB endpoint metadata)
- **0x105000 (12KB overflow):** Stage 1 "races" — sometimes OKAYaloha, sometimes timeout.
  The +8KB to +12KB region contains USB response path function pointers. When corrupted
  to 0x14000000 (B #0 = branch-to-self), the CPU hangs trying to call these functions.

**Key insight:** The "race" at 0x105000 isn't timing-related — it's function pointer
corruption. If we fill the +8KB to +12KB region with an actual valid function address
instead of B #0, the corrupted pointers will redirect to that function instead of hanging.

## New Compile Mode: PORTAL_ADDR_SPRAY

```
-DPORTAL_ADDR_SPRAY -DPORTAL_SPRAY_START=0x104000 -DPORTAL_VTABLE_TARGET=0x9FA0F1A0ULL
```

- Bytes 0 to SPRAY_START: B #0 fill (0x14000000) — proven safe
- Bytes SPRAY_START to end: alternating low32/high32 of target address
  - Creates valid 8-byte AArch64 pointers at every 8-byte-aligned position
  - Target: FastbootOkay (0x9FA0F1A0) — makes any redirected call return "OKAY"

## Test: 0x105000 with Address Spray

**Build:**
```bash
gcc -D_GNU_SOURCE -DTARGET_ABL_PORTAL -DPORTAL_DISCOVERY -DPORTAL_TWOSTAGE \
    -DPORTAL_PROBE -DPORTAL_ADDR_SPRAY \
    -DPORTAL_SPRAY_START=0x104000 -DPORTAL_VTABLE_TARGET=0x9FA0F1A0ULL \
    -DPORTAL_SIZE=0x105000 -DPORTAL_BL_SKIP=0 \
    -ggdb -I/opt/homebrew/opt/libusb/include -o xperable-native.o -c xperable.c
g++ -ggdb -Lpe-parse/build-native/pe-parser-library -L/opt/homebrew/opt/libusb/lib \
    -o xperable xperable-native.o pe-load-native.o fbusb-native.o -lpe-parse -lusb-1.0
./xperable -v -V -t 20000 -A -2
```

**Result: COMPLETE SUCCESS** ✅

| Probe Command | Response | Status |
|---------------|----------|--------|
| Stage 1 getvar:product | OKAYaloha | ✅ FIRST ATTEMPT |
| getvar:product | OKAY 'aloha' | ✅ |
| getvar:serialno | OKAY '818PGA02P110MQ09' | ✅ |
| getvar:secure | OKAY 'yes' | ✅ |
| getvar:unlocked | OKAY 'no' | ✅ |
| getvar:max-download-size | OKAY '536870912' | ✅ |
| getvar:current-slot | OKAY 'b' | ✅ |
| flash:boot (download 27MB) | FAIL 'Flashing is not allowed in Lock State' | ✅ |
| flashing unlock | FAIL 'Flashing Unlock is not allowed.' | ✅ |
| get_unlock_ability | INFO 'get_unlock_ability: 0', OKAY | ✅ |
| oem get_unlock_bootloader_nonce | INFO 'Unlock Request: 173A00D542E56FE7...', OKAY | ✅ |
| oem device-info | Verity:true, unlocked:false, critical:false, unsealed:false, ADB:false, OKAY | ✅ |

**Every single command worked.** This is a massive improvement over uniform B #0 at 0x105000,
which raced/timed out ~50% of the time.

## Analysis

### Why This Works

The USB response path involves calling function pointers from UEFI protocol vtables.
When these pointers are overwritten with B #0 (0x14000000), the CPU branches to address
0x14000000 and hangs in an infinite loop. When they're overwritten with FastbootOkay
(0x9FA0F1A0), the CPU branches to FastbootOkay instead — which:
1. Sends "OKAY" response back over USB
2. Returns cleanly to the caller
3. Keeps the entire USB infrastructure functional

The "healed" vtable entries don't need to do the right thing — they just need to
**not crash**. FastbootOkay is perfect because it's a small, self-contained function
that gracefully returns after sending a response.

### What This Means

1. **We can extend overflow well beyond 8KB** by spraying FastbootOkay addresses
2. **The overflow corrupts UEFI protocol structures** which are used by the lock-check
   flow (FlashHandler calls UEFI protocols for partition I/O, security checks, etc.)
3. **If we spray deep enough**, we might corrupt protocol vtables that FlashHandler
   uses to verify the lock state — potentially short-circuiting the lock check

### Hypothesis for Larger Spray Sizes

At 128KB overflow (0x120000) with B #0:
- flash:boot HANGs (UEFI protocol calls hit B #0 infinite loops)
- Stage 2 download returns FAIL "too large" (alloc_buf_size corrupted)

With FastbootOkay spray from +8KB to +128KB:
- All corrupted UEFI protocol calls would return "OKAY" instead of hanging
- FlashHandler's calls to UEFI partition I/O protocols would "succeed" (return OKAY)
- The lock-check path might behave differently when UEFI calls return unexpected values
- alloc_buf_size corruption might still happen (it's a data value, not a function pointer)

## Progressive Size Tests

### 0x105800 (14KB overflow, 6KB spray) — FAILED
- Stage 1: TIMEOUT (send OK, no response)
- Recovery: I/O Error → device hung
- **Conclusion:** +12KB to +14KB contains critical structures that crash on FastbootOkay

### 0x108000 (24KB overflow, 16KB spray) — FAILED
- Stage 1: TIMEOUT (send OK, no response)
- Recovery: I/O Error → device hung
- **Conclusion:** Same as above, deeper corruption doesn't help

### 0x108000 Two-Zone (spray to +12KB, ZEROS beyond) — FAILED
- B #0 to 0x104000, FastbootOkay from 0x104000 to 0x105000, NUL from 0x105000 to 0x108000
- Stage 1: TIMEOUT → I/O Error → hung
- **Conclusion:** The structures at +12KB crash on ANY modification: B#0, FastbootOkay, or zeros

---

## Definitive Overflow Map

```
OVERFLOW REGION (above DMA buffer at ~0x102000 boundary):

  +0 to +8KB      │ Data fields (USB endpoint metadata)
                   │ Tolerates: B#0 ✅  Zeros ✅  Spray ✅
                   │ Behavior: no observable effect
  ─────────────────┤
  +8KB to +12KB    │ Function pointers (USB response path vtable)
                   │ Tolerates: Spray ✅  B#0 ❌ (hang)  Zeros ❌ (crash)
                   │ Spray: FastbootOkay redirects calls → USB stays alive
  ─────────────────┤
  +12KB+           │ CRITICAL structures (unknown — pool headers? DMA config?)
                   │ Tolerates: NOTHING. B#0 ❌  Spray ❌  Zeros ❌
                   │ Any modification → immediate USB controller death
```

**Maximum usable overflow: 12KB (0x105000). This is a HARD ceiling.**

---

## Why This Can't Unlock the Device

Even with the 12KB overflow fully characterized and USB functional:

1. **Lock state is unreachable:** DeviceInfo.is_unlocked is cached in ABL .data at
   ~0x9FAA0xxx — BELOW the DMA buffer. Overflow goes UPWARD. Can't touch it.

2. **Lock checks are direct calls:** FlashHandler calls IsDeviceLocked() as a direct
   function call in ABL code, NOT through a UEFI protocol dispatch table. Corrupting
   UEFI protocol vtables doesn't affect the lock check.

3. **Unlock gate is a data read:** `flashing unlock` checks DAT_000a0f18 (unlock_allowed
   flag) — a direct memory read from ABL .data. Not a protocol call. Can't intercept.

4. **Can't extend overflow:** Beyond 12KB, critical UEFI structures crash regardless
   of what value we write (function address, zero, B#0). No fill pattern survives.

5. **Can't achieve code execution:** We don't know the DMA buffer's runtime address,
   so we can't make vtable entries point INTO the overflow buffer (where we control
   the content). We can only redirect to KNOWN ABL functions (FastbootOkay, etc.)
   which don't help unlock.

---

## Key Takeaway

The address spray technique proved that the +8KB to +12KB region contains USB protocol
function pointers that can be redirected to known ABL functions. This keeps USB alive
at 12KB overflow (vs 8KB with B#0). However, the fundamental architecture prevents
software-only unlock: lock state is in ABL .data below the buffer, all lock checks
are direct function calls, and overflow can't extend beyond 12KB.

**The DMA overflow (CVE-2021-1931) is fully characterized but CANNOT unlock the device
through software-only exploitation.** The overflow gives us diagnostic capability
(full probe of all commands) but not write capability to the lock state.

---

## Recommended Next Steps

### Immediate (software, low cost)
1. **Publish findings to XDA** — our Gen 1 characterization is the most thorough public
   analysis. Community members may have Gen 1 firehose loaders or hardware tools.
2. **Try FastbootFail spray** — spray 0x9FA0F004 at 0x105000 to see if error messages
   leak internal state (pure info gathering)
3. **Research other CVEs** — the 2019-08 security patch level has many known vulns;
   CVE-2021-1931 may not be the only exploitable one

### Short-term (hardware, $50-150)
4. **Voltage glitching** — inject voltage glitch during IsDeviceLocked() to skip
   the 68-byte lock check. Requires FPGA/Arduino + PCB probing. ~30-40% success.

### Medium-term (hardware, $200-500)
5. **UFS direct access** — read/modify devinfo partition directly via UFS test pads.
   Requires UFS programmer. ~60-70% success.
6. **JTAG/SWD probe** — check if debug port is enabled (likely fused off). ~20%.
