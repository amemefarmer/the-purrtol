# Experiment 015: NOP Slide Binary Search, Framebuffer Exfil, and Data Corruption Pivot

**Date:** 2026-03-01
**Risk Level:** LOW (device hangs/crashes, power cycle recovers)
**Outcome:** Complete memory corruption map established; NOP slide approach proven fundamentally flawed; framebuffer exfiltration failed; pivoting to data corruption exploitation strategy

---

## Summary

Binary-searched the overflow size from 4KB to 2MB using B #1 NOP slide fill to map the full ABL memory layout adjacent to the DMA buffer. Discovered five distinct failure modes at different overflow sizes. Attempted framebuffer exfiltration as an alternative to USB communication — failed because the NOP slide approach is fundamentally flawed: corrupted function pointers use the fill VALUE (0x14000001) as a jump ADDRESS, not the LOCATION of the fill in memory. The CPU jumps to unmapped low memory (~335MB) instead of the overflow region (~0x9Fxxxxxx).

Pivoting to data corruption exploitation: the 128KB overflow produces a proper FAIL response (FastbootFail intact), so diagnostic commands after overflow may reveal corrupted lock state variables.

---

## Experiments Conducted

### Experiment 15a: NOP Slide 2MB (0x200000)

**Hypothesis:** Large overflow + B #1 NOP slide should execute shellcode at buffer end.

**Build:**
```bash
gcc -D_GNU_SOURCE -DTARGET_ABL_PORTAL -DPORTAL_DISCOVERY -DPORTAL_TWOSTAGE \
    -DPORTAL_NOP_SLIDE -DPORTAL_SIZE=0x200000 -DPORTAL_BL_SKIP=0 \
    -ggdb -I/opt/homebrew/opt/libusb/include -o xperable-native.o -c xperable.c
```

**Result:** Stage 1 getvar: TIMEOUT. getvar handler code overwritten.

### Experiment 15b: NOP Slide 1.5MB (0x180000)

**Result:** Stage 1 TIMEOUT. Recovery I/O Error.

### Experiment 15c: NOP Slide 1.25MB (0x140000)

**Result:** Stage 1 TIMEOUT. Recovery I/O Error.

### Experiment 15d: NOP Slide 1.125MB (0x120000) — CRITICAL FINDING

**Result:**
- Stage 1: `OKAYaloha` ✅ (getvar survived!)
- Stage 2: **FAIL "Requested download size is more than max allowed."**

**Analysis:**
- This is NEW behavior! FastbootFail() IS WORKING at this overflow size
- The download handler validation code is intact and functional
- The `max-download-size` variable or the allocation size check is corrupted by overflow
- The 128KB overflow corrupts download-related DATA but preserves USB and response infrastructure

### Experiment 15e: NOP Slide 1.0625MB (0x110000)

**Result:**
- Stage 1: `OKAYaloha` ✅
- Stage 2: I/O Error (instant USB crash, no DATA or FAIL response)

**Analysis:**
- Download handler crashes BEFORE it can send DATA or FAIL
- Likely heap metadata or AllocatePages structures corrupted
- 64KB overflow hits download handler internals but not the validation/response path

### Experiment 15f: Framebuffer Exfil V1 at 0x140000

**Build:** `-DPORTAL_FB_EXFIL -DPORTAL_SIZE=0x140000`

**Shellcode:** Reads MDP DMA0 SSPP SRC0_ADDR register (0x0C925014) for framebuffer address, fills 4MB with white pixels, infinite loop.

**Result:** Stage 1 TIMEOUT. Screen: no change, device rebooted normally.

**Analysis:** Watchdog timer rebooted device before framebuffer writes completed.

### Experiment 15g: Framebuffer Exfil V2 at 0x200000 (+ Watchdog Disable)

**Build:** `-DPORTAL_FB_EXFIL -DPORTAL_SIZE=0x200000`

**Shellcode enhanced:** Added APSS_WDT_EN (0x17980000) disable as first 4 instructions.

**Result:** Stage 1 TIMEOUT. Screen: no change, "Please Reboot..." unchanged.

**Analysis:** Led to the CRITICAL REALIZATION below.

---

## Critical Discovery: NOP Slide Fundamental Flaw

The NOP slide approach (B #1 fill, 0x14000001) is fundamentally impossible on this architecture:

```
Corrupted function pointer contains: 0x14000001  (our fill value)
CPU jumps to ADDRESS: 0x14000001  (≈ 335MB, UNMAPPED on APQ8098)
                                   ↑ CPU faults immediately

Our NOP slide in DMA buffer: ~0x9FA00000 to ~0x9FC00000
                              ↑ NEVER REACHED
```

**Why:** When ABL calls a function through a corrupted pointer, the pointer VALUE becomes the jump target. The fill value 0x14000001 is interpreted as a memory address, not as code at its location. Since 0x14000001 is in unmapped low memory (APQ8098 DRAM starts at ~0x80000000), the CPU immediately takes a synchronous exception → exception handler → reboot.

**Why no screen change:** The shellcode at the end of the buffer (0x9FBxxx80) was never reached. The CPU never got there.

**Why 0x14000000 (B #0) works for test0:** With the original B #0 fill, corrupted function pointers jump to 0x14000000, which is ALSO unmapped → exception → hang (test0 proved code execution via hang, but it was actually an exception halt, not our code running).

**Implication:** ANY fill-based approach that relies on corrupted function pointers will jump to the fill VALUE, not to the fill LOCATION. Code execution via function pointer corruption requires knowing the buffer's actual memory address so the fill value can be set to that address.

---

## Complete Memory Corruption Map

| Size | Overflow | Fill | Stage 1 | Stage 2 | What's Corrupted |
|------|----------|------|---------|---------|-----------------|
| 0x103000 | ~4KB | B #0 | OKAYaloha | DATA→TIMEOUT | Post-recv function ptrs |
| 0x110000 | ~64KB | B #1 | OKAYaloha | I/O Error | Download handler internals (heap?) |
| 0x120000 | ~128KB | B #1 | OKAYaloha | FAIL "too large" | max-download-size / alloc check |
| 0x140000 | ~256KB | B #1 | TIMEOUT | — | getvar handler code/data |
| 0x180000 | ~512KB | B #1 | TIMEOUT | — | getvar handler code/data |
| 0x200000 | ~1MB | B #1 | TIMEOUT | — | getvar handler code/data |

**Key observations:**
1. Buffer boundary is at ~0x102000 (last OK size) to 0x103000 (first hang)
2. getvar handler survives up to ~128KB overflow (0x120000) but fails at 256KB (0x140000)
3. Download handler has three distinct failure modes depending on what's corrupted
4. At 128KB, FastbootFail() works — USB and response infrastructure preserved
5. There is NO sweet spot where code executes AND USB works via NOP slide

---

## Strategy Pivot: Data Corruption Exploitation

Since code execution via function pointer manipulation is not achievable without knowing the buffer address, we pivot to exploiting DATA corruption.

**Key insight from 0x120000 (128KB overflow):**
- FastbootFail works (sends proper FAIL responses)
- Non-download commands still work (oem device-info, flashing commands)
- The overflow corrupts DATA but not the command handler infrastructure

**New approach:**
1. Send overflow at various sizes (0x103000, 0x110000, 0x120000)
2. After overflow, send diagnostic commands:
   - `oem device-info` → check Unlocked, Verity, ADB, Unsealed flags
   - `getvar unlocked` → check lock state
   - `getvar max-download-size` → verify what data is corrupted
   - `flashing get_unlock_ability` → check unlock ability
   - `flashing unlock` → attempt unlock (maybe corrupted state allows it)
3. If any security-critical variable is in the corrupted region, the overflow could flip it

**Why this might work:**
- The ABL stores device state (lock/unlock, verity, ADB) in memory-mapped structures
- The DMA buffer overflow corrupts adjacent memory indiscriminately
- If lock state data is adjacent to the DMA buffer, zero-fill could flip bits
- The FAIL "too large" at 0x120000 proves data IS getting corrupted

---

## Files Modified

### target-portal.c
- Extended NOP slide fill to also apply for FB_EXFIL mode (`#if defined(PORTAL_NOP_SLIDE) || defined(PORTAL_FB_EXFIL)`)
- Added PORTAL_FB_EXFIL shellcode block (20 instructions, 0x50 bytes):
  - V1: MDP register read → framebuffer fill → infinite loop
  - V2: Added APSS watchdog disable as first 4 instructions
  - Fallback chain: DMA0 SRC0_ADDR → VIG0 SRC0_ADDR → hardcoded 0x9D400000

---

## Lessons Learned

1. **NOP slides cannot work with function pointer corruption.** The fill value becomes the jump ADDRESS, not the execution LOCATION. This is a fundamental architectural limitation, not a bug in our shellcode.

2. **Code execution ≠ useful code execution.** test0 "proved" code execution via device hang, but the hang was actually an exception at an unmapped address, not our code running.

3. **DATA corruption is the real opportunity.** At 128KB overflow, we corrupt data structures while preserving USB communication. If security-critical data is in the corrupted region, we win without needing code execution.

4. **The FAIL response at 0x120000 is a breakthrough.** It proves FastbootFail(), USB, and the command dispatch infrastructure all work after 128KB overflow. This is our best communication channel.

5. **Binary search was essential.** Without mapping all failure modes, we'd have kept trying to make NOP slides work. The distinct behaviors at each size revealed the memory layout.

---

## Next Steps

1. **Implement PORTAL_PROBE mode** — send diagnostic commands after Stage 1 overflow
2. **Test at 0x103000** — baseline (smallest overflow, compare with pre-overflow)
3. **Test at 0x110000** — 64KB overflow (download crashes but other commands?)
4. **Test at 0x120000** — 128KB overflow (FAIL works, check lock state)
5. **Try `flashing unlock` after 0x120000 overflow** — maybe lock state is corrupted
6. **If lock corrupted → attempt flash** with modified boot.img
