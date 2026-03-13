# Blind Memory Dump Shellcode Design

**Purpose:** Extract the decrypted ABL from Portal's live RAM via CVE-2021-1931
**Risk Level:** MEDIUM (requires fastboot USB connection, device may need reboot)
**Prerequisites:** test0 confirms code execution, test2/test3 confirms distance

---

## Overview

The ABL (Android Bootloader / LinuxLoader) is encrypted on disk but runs **decrypted in RAM**. The CVE-2021-1931 DMA buffer overflow overwrites live ABL code pages. By crafting position-independent shellcode, we can:

1. Discover our position in memory
2. Read the decrypted ABL code from surrounding memory
3. Return chunks of data via the fastboot FAIL response string

This approach was formulated because:
- ABL partitions are encrypted (entropy ~8.0 bits/byte)
- Only the SoC's PBL (in ROM) can decrypt them
- The ABL runs decrypted in RAM at runtime
- CVE-2021-1931 gives us code execution in that RAM space

---

## Architecture

### Phase 1: Confirm Execution (test0)

Based on xperable test0. Fill the DMA overflow buffer with infinite-loop opcodes:

```
B #0x00     ; 00 00 00 14 — branch to self (infinite loop)
```

Fill the entire 15MB+ buffer with this 4-byte pattern. After `fastboot stage <size>`, the device should **hang** (no response, no reboot) if code execution was achieved. The hang confirms the overflow reached executable code pages.

### Phase 2: Distance Probe (test2-style PIC shellcode)

Based on xperable test2. Position-independent shellcode that:
1. Discovers its own address using BL/ADR trick
2. Scans backwards through memory for a known code pattern
3. Reports the distance via FAIL response

```asm
; === PIC Distance Probe (0x80-byte repeating block) ===
; This shellcode finds the distance from the DMA buffer landing zone
; to the FastbootFail function, which tells us the LinuxLoader base.

; Step 1: Get our own address
    BL   #4             ; BL to next instruction, sets LR = PC+4
    ADR  x2, #-4        ; x2 = address of the BL instruction
    SUB  x2, LR, x2     ; x2 = offset (should be 4, confirms PIC works)
    B    #8              ; skip to next block

; Step 2: Scan backwards for a known pattern
; We search for a BL instruction that calls FastbootFail
; The pattern we look for is: any BL opcode (94xxxxxx) where the
; target address is a commonly-called function
    BL   #-0xC           ; set LR again for position reference
    ADRP x1, #-0x1000    ; page before our code
    LDR  w1, [x1], #4    ; load first word
    B    #8

; Step 3: Linear scan comparing against known patterns
; In the actual implementation, this scans page-by-page backwards
; looking for the function prologue pattern of FastbootFail:
; STP X29, X30, [SP, #-N]! followed by specific register setup

; Step 4: Report distance
; Once found, compute distance and return via FAIL response string
; The string "vxyzNNNNNN-" format from xperable encodes the offset
```

The key insight from the terry analysis: **FastbootFail at 0x00F004** is called by BL from many locations. The specific BL opcode encodes the distance from caller to 0x00F004. By finding any of these BL opcodes in live RAM, we can compute the LinuxLoader base address.

### Phase 3: Memory Dump Shellcode (NEW — custom for Portal)

This is the novel part. After test2 gives us the distance:

```asm
; === Memory Dump Shellcode ===
; Reads N bytes from a specified offset and returns them
; as hex characters in the FAIL response string
;
; Strategy:
;   1. Use BL trick to find our own position
;   2. Calculate the FastbootFail function address using known distance
;   3. Read bytes from target memory region
;   4. Format them as hex ASCII
;   5. Call FastbootFail with our hex string → visible in fastboot output
;
; Each invocation dumps a chunk (e.g., 24 bytes = 48 hex chars + prefix)
; Maximum FAIL string is ~64 bytes, so ~28 data bytes per invocation
; Full ABL code section (~600KB) requires ~25,000 invocations
; At ~1 second per fastboot exchange, that's ~7 hours
;
; Optimization: Use the "erase:" command trick from xperable to set up
; download-mode upload, then dump entire regions at once via USB bulk

; Block layout (repeated every 0x80 bytes for alignment tolerance):

.equ CHUNK_SIZE, 24        ; bytes to dump per invocation
.equ HEX_OFFSET, 0x44      ; offset within block for hex output buffer

block_start:
    ; Step 1: Position discovery
    BL      .+4                 ; LR = current_addr + 4
    SUB     x10, LR, #4        ; x10 = address of this BL instruction

    ; Step 2: Load parameters from end of block
    LDR     w11, [x10, #0x78]  ; w11 = FastbootFail distance (set by host)
    LDR     w12, [x10, #0x7C]  ; w12 = target read offset (set by host)

    ; Step 3: Calculate FastbootFail address
    SUB     x13, x10, x11      ; x13 = FastbootFail function address

    ; Step 4: Calculate read source address
    SUB     x14, x10, x12      ; x14 = source address to read from

    ; Step 5: Set up output buffer
    ADR     x0, hex_buffer      ; x0 = pointer to our output string

    ; Step 6: Read and convert to hex
    MOV     w15, #CHUNK_SIZE    ; byte counter
    MOV     x16, x14            ; read pointer
hex_loop:
    LDRB    w17, [x16], #1     ; read one byte
    LSR     w18, w17, #4       ; high nibble
    AND     w19, w17, #0xF     ; low nibble

    ; Convert to ASCII hex
    CMP     w18, #10
    ADD     w18, w18, #0x30    ; '0' + nibble
    CSEL    w18, w18, w18, LT  ; if < 10, use as-is
    ; (simplified — full version handles A-F)

    STRB    w18, [x0], #1      ; store high nibble
    STRB    w19, [x0], #1      ; store low nibble

    SUBS    w15, w15, #1
    B.NE    hex_loop

    STRB    wzr, [x0]           ; null terminate

    ; Step 7: Call FastbootFail with our hex string
    ADR     x0, hex_buffer
    BR      x13                 ; jump to FastbootFail

hex_buffer:
    .space  64                  ; output buffer

    ; Parameters (set by host before sending):
    .word   0                   ; [+0x78] FastbootFail distance
    .word   0                   ; [+0x7C] target read offset
```

### Phase 4: Optimized Bulk Dump (via Upload Mode)

If the basic dump is too slow, we can use the xperable "erase:" trick:

1. After achieving initial code execution, patch the ABL in RAM to:
   - Enable the "erase:" → set download buffer address
   - Enable upload mode (ENDPOINT_OUT instead of ENDPOINT_IN)
2. Use `erase:0XADDRESS` to set the read pointer to ABL code region
3. Use `download:SIZE` to trigger upload of that memory region
4. Receive the entire ABL code section in one USB bulk transfer

This requires patching the live ABL (post-exploit), but uses the same patterns documented in xperable's `p114_patch_abl()`.

---

## Implementation Plan

### Step 1: Prepare test0 payload
```bash
# Fill 15MB buffer with B #0x00 (infinite loop)
python3 -c "
import sys
pattern = bytes([0x00, 0x00, 0x00, 0x14])  # B #0x00
size = 15 * 1024 * 1024  # 15MB
sys.stdout.buffer.write(pattern * (size // 4))
" > /tmp/test0_payload.bin
```

### Step 2: Send test0 via modified xperable
```bash
# Option A: Use xperable directly (needs target-portal.c for test0)
# Option B: Use raw fastboot stage command
fastboot stage /tmp/test0_payload.bin
# If device hangs → code execution confirmed!
# If device responds → overflow not reaching code pages
```

### Step 3: Calibrate overflow size
If test0 fails, adjust buffer size. The Portal's DMA buffer is likely ~1MB (ABL partition size is 0x100000). The overflow starts at the buffer base and extends upward. The LinuxLoader code may be mapped above or below the buffer.

Key variable: `fastboot stage` sends data as a raw USB bulk transfer. The device-side buffer is whatever was allocated during fastboot init. If max-download-size is 512MB (0x20000000), the buffer should be that size, but the actual allocation may be smaller.

From the terry analysis:
- "Fastboot Buffer Size allocated: %ld" at 0x010BE4
- "Not enough memory to Allocate Fastboot Buffer" at 0x010B98
- "ERROR: Allocation fail for minimum buffer for fastboot" at 0x010B34

The buffer may be dynamically sized based on available RAM.

### Step 4: Run test2 with terry-informed shellcode
Use the PIC probing technique from xperable test2, but informed by our knowledge of the terry LinuxLoader structure. The shellcode searches for:
- BL instructions targeting low addresses (FastbootFail at 0x00F004 in terry)
- STP X29, X30 function prologues
- Known string patterns in the code section

### Step 5: Execute memory dump
With the distance known, craft dump shellcode and iterate:
```bash
for offset in $(seq 0 24 614400); do
    # Modify payload with current dump offset
    # Send via fastboot
    # Capture FAIL response with hex data
    # Append to output file
done
```

### Step 6: Reconstruct ABL binary
```bash
# Convert hex dump to binary
python3 reconstruct_abl.py dump_chunks/ > aloha_abl_decrypted.bin

# Load in Ghidra → find all exploit offsets
# Create target-portal.c
```

---

## Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|------------|
| test0 | LOW — device hangs, power cycle recovers | Hold power 15s to force reboot |
| test2 | LOW — device may reboot on bad shellcode | Automated retry in xperable |
| Memory dump | MEDIUM — many sequential overflows | Device may enter crash loop; power cycle between attempts |
| ABL patching | HIGH — incorrect patches could soft-brick | Have full partition backup first; use A/B slot switching |

**Critical safety note:** All overflow operations target the live RAM copy of the ABL, not the flash storage. A power cycle always restores the device to its original state. The device cannot be bricked by these operations — only by writing incorrect data to flash (which requires successful unlock first).

---

## Dependencies (UPDATED 2026-02-28)

- [x] Capture Portal fastboot USB VID/PID → **0x2EC6:0x1800** (confirmed)
- [x] Modify xperable to match on `product: aloha` instead of `version-bootloader` → DONE
- [x] Build target-portal.c with test0/test2/test3 support → DONE (discovery + two-stage)
- [x] Physical access to Portal in fastboot mode → AVAILABLE
- [x] USB-C data cable connected → WORKING

---

## Experiment Results & Lessons Learned (2026-02-27 to 2026-02-28)

### What Works
1. **test0 (code execution):** CONFIRMED — 15MB (0xF3F880) and 0x104000 both reliably crash device
2. **Buffer boundary:** ~0x102800 (between 0x102000 OK and 0x103000 HANG)
3. **Two-stage overflow delivery:** Stage 1 (getvar:product + overflow) → `OKAYaloha` reliably
4. **Overflow persists for Stage 2:** Non-download commands (oem, flash, flashing) all work normally after overflow — only download handler's post-data path touches corrupted region
5. **Discovery shellcode:** PIC backward-BL scanner with trampoline filter compiles and deploys

### What Doesn't Work (and Why)

#### Problem: USB State Corruption
The ~6KB overflow region (0x102800 to 0x104000) contains BOTH executable code AND data structures:
- USB endpoint state / DWC3 controller config
- Function pointers in linked lists
- Download handler support data

**Zero-filling** these data structures causes the USB subsystem to crash when ANY function tries to send a response. The device doesn't just stall — it completely disappears from USB (LIBUSB_ERROR_NOT_FOUND).

**RET-filling** (0xD65F03C0) is worse — corrupts data structures with non-zero values AND makes functions return immediately without doing their job (causes TIMEOUT even on getvar).

#### Evidence: BL_SKIP=0 and BL_SKIP=1 produce identical crashes
This proves the crash is NOT about which function our shellcode jumps to. Even if we perfectly find FastbootFail, it can't send a FAIL response because the USB TX path is broken by our overflow.

#### Evidence: Pure RET causes TIMEOUT (not I/O Error)
Essential download functions in the overflow region return via RET without executing → download handler deadlocks waiting for DATA to be sent. Proves the corrupted region contains functions NEEDED by the download handler.

### Revised Architecture Decision (2026-03-01) — Session 1

**CRITICAL UPDATE:** The NOP slide approach is FUNDAMENTALLY FLAWED.

The fill value (0x14000001 = B #1) is interpreted as a jump ADDRESS by corrupted function pointers, not as code at its LOCATION. The CPU jumps to address 0x14000001 (unmapped ~335MB), NOT to the overflow region (~0x9Fxxxxxx). This means:
- NOP slide shellcode is NEVER REACHED
- Framebuffer exfiltration shellcode is NEVER REACHED
- ANY fill-based approach fails without knowing the buffer's actual memory address
- test0 "code execution" was actually an exception halt at an unmapped address

**Approaches PROVEN NOT to work:**
- NOP slide (B #1) at any size — CPU faults at fill VALUE address
- Framebuffer exfil with/without watchdog disable — shellcode never reached
- Shellcode blocks at 0x80 intervals — corrupt data structures → USB crash
- DWC3 direct register access — requires code execution (which we don't have)

---

### Session 2 Results: RET Fill and Fine-Grained Binary Search (2026-03-01)

#### RET Fill — PROVEN INCOMPATIBLE

Tested RET (0xD65F03C0) as an alternative to B#0 fill to see if immediate function returns could preserve USB while corrupting data. Results are uniformly catastrophic:

| Configuration | Size | Result |
|--------------|------|--------|
| Pure RET | 0x120000 (128KB) | I/O Error (x2) — USB crash |
| Hybrid B#0+RET, split at 0x104000 | 0x120000 | I/O Error — USB crash |
| Hybrid B#0+RET, split at 0x118000 (only last 32KB RET) | 0x120000 | I/O Error — USB crash |

**Why RET is worse than B#0:** Functions in the overflow region that are overwritten with RET return immediately to their callers with garbage register contents. Callers interpret these garbage values as valid results and continue executing, cascading corrupted state through the USB response path. B#0 (branch-to-self) at least HALTS execution at the point of corruption, limiting the blast radius. RET fill cannot be made safe at ANY overflow size or split point.

#### Fine-Grained Reliability Map (B#0 fill)

| Size | Overflow | B#0 Stage 1 | Full Probe Result |
|------|----------|-------------|-------------------|
| 0x103000 | 4KB | Reliable | All OK, flash:boot FAIL locked |
| 0x104000 | 8KB | Reliable | All OK, flash:boot FAIL locked |
| 0x105000 | 12KB | RACED | — |
| 0x106000 | 16KB | RACED (x2) | — |
| 0x108000 | 24KB | ~50% | 1 getvar then dead |
| 0x110000 | 64KB | RACED (x2) | — |
| 0x120000 | 128KB | ~50% | getvar OK, flash:boot HANG |

At 0x104000 (8KB overflow), ALL commands return normal locked-state responses: `unlocked: no`, `Unlocked:false`, `Verity:true`, `ADB:false`. The lock state is NOT in the overflow region.

#### Critical Architectural Discovery: Overflow Direction

```
Lower addresses
    +-------------------------+
    |  ABL .text (code)       |
    |  ABL .data (DeviceInfo  | <-- is_unlocked, is_verified, etc.
    |    lock state, config)  |     UNREACHABLE by overflow
    |  ABL .bss               |
    +-------------------------+
    |  ABL heap               |
    +-------------------------+
    |  DMA buffer (~1.01MB)   | <-- fastboot download buffer
    |  [0x102000 boundary]    |
    +-------------------------+
    |  UEFI memory pool       | <-- protocol tables, DXE driver data
    |  (corrupted by overflow)|     REACHABLE by overflow
    +-------------------------+
Higher addresses
```

**The overflow goes UPWARD** from the DMA buffer into the UEFI memory pool. ABL's `.data` section (containing `DeviceInfo.is_unlocked`) resides at LOWER addresses — completely unreachable.

**Evidence:**
- 8KB overflow: all commands work, lock state unchanged → first 8KB above buffer is benign UEFI pool metadata
- 128KB overflow: `getvar` works (reads ABL's in-memory linked list at lower addresses) but `flash:boot` and `oem device-info` HANG (they call UEFI protocols via dispatch tables at higher addresses, now corrupted)
- `flash:boot` at 0x104000 returns "Flashing is not allowed in Lock State" — lock check reads from ABL .data (intact), BEFORE calling any UEFI protocols

#### Data Corruption of Lock State — RULED OUT

1. Lock state is in ABL .data (BELOW DMA buffer)
2. Overflow goes UPWARD into UEFI pool (ABOVE DMA buffer)
3. No overflow size helps — larger overflows only destroy more UEFI infrastructure
4. Confirmed empirically at both 8KB (everything works, still locked) and 128KB (massive corruption, still locked)

---

### All Exhausted Strategies (as of Session 2)

1. **NOP slide / fill-based code execution** — fill value = jump target, not code location
2. **Code execution via function pointer corruption** — requires knowing buffer address (chicken-and-egg)
3. **Data corruption of lock state** — lock state below DMA buffer, overflow goes upward
4. **RET fill** — cascading garbage returns crash USB controller at every tested configuration
5. **Framebuffer exfiltration** — shellcode never reached (same root cause as #1)
6. **DWC3 direct register writes** — requires code execution (which we don't have)

---

### CURRENT STRATEGY: Ghidra UEFI Memory Layout Analysis

The overflow CAN corrupt UEFI protocol dispatch tables (proven at 128KB). If a protocol handler pointer can be redirected to a known ABL function (e.g., `SetLockUnlockState` at terry offset 0x16654), a single corrupted pointer could unlock the device without arbitrary code execution. This requires:

1. **Map the UEFI memory pool layout** — Ghidra analysis of terry LinuxLoader's UEFI buffer allocation and protocol table structures
2. **Identify exploitable protocol pointers** — find protocol handler entries in the overflow region that are called by `flash:boot` or `oem device-info`
3. **Craft surgical byte patterns** — instead of uniform B#0 fill, place specific values at protocol pointer offsets to redirect execution to `SetLockUnlockState(unlock=1)`
4. **Alternative paths if UEFI analysis fails:**
   - Hardware: JTAG debug port, direct UFS chip access, voltage glitching
   - Software: fuzz `oem get_unlock_bootloader_nonce` for other bugs
   - Cross-device: acquire APQ8098 firehose programmer (Facebook OEM_ID 0x0137)
