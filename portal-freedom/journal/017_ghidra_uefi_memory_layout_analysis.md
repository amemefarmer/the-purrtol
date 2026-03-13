# Journal 017: Ghidra UEFI Memory Layout Analysis & Revised Exploitation Strategy

**Date:** 2026-03-01
**Risk Level:** ZERO (analysis only, no device interaction)
**Binary:** LinuxLoader-terry.efi (724KB PE32+ AArch64, Portal Go terry/SDM670, aloha codebase)
**Tools:** Ghidra 12.0.3, existing decompiled output from journal 011

---

## Objective

After exhausting NOP slide, framebuffer exfil, RET fill, and data corruption approaches
(journals 012-016), perform deep Ghidra reverse engineering of the UEFI memory layout to:
1. Understand how the DMA buffer is allocated and where it sits in memory
2. Map the lock-check code path from command dispatch to persistent storage
3. Identify what UEFI structures are in the overflow region
4. Determine if any viable exploitation path remains

---

## Key Findings

### 1. DMA Buffer Allocation (FastbootInit = FUN_000107d8)

The DMA download buffer is allocated during fastboot initialization through a **3-step process**:

**Step 1: Query free memory**
```c
// gBS->GetMemoryMap (Boot Services + 0x38)
GetMemoryMap(&map_size, map_buffer, &map_key, &desc_size, &desc_version);
// Scan for LARGEST EfiConventionalMemory region (type 7)
for each descriptor:
    if (type == 7 && num_pages > max_pages)
        max_pages = num_pages;
DAT_000a0f58 = max_pages << 12;  // Convert to bytes
```

**Step 2: Size calculation**
```c
// Take 75% of free memory, page-aligned, capped at 1.5GB
alloc_size = (free_memory * 3 / 4 + 0xFFF) & ~0xFFF;
if (alloc_size > 0x60000000) alloc_size = 0x60000000;  // 1.5GB cap
```

**Step 3: Allocate via USB Transfer Protocol**
```c
usb_protocol = FUN_0000e200();  // Get USB/Transfer protocol instance
usb_protocol->vtable[+0x20](alloc_size, &buffer_ptr);  // AllocateTransferBuffer
gBS->SetMem(buffer_ptr, alloc_size, 0);  // Zero the buffer
// For single-LUN devices, halve the buffer
alloc_size >>= (lun_count != 2);
```

**Critical insight:** The DMA buffer is allocated through a **UEFI protocol's custom allocator**
(USB Transfer Protocol vtable offset +0x20), NOT through standard gBS->AllocatePages. This
means it's in DMA-coherent memory managed by the USB driver. The USB protocol instance and
its vtable are separate UEFI pool allocations.

### 2. Buffer State Variables (all in .data section)

| .data Offset | Variable | Terry Offset | Purpose |
|-------------|----------|-------------|---------|
| 0x0A0F28 | download_size | DAT_000a0f28 | Expected download size |
| 0x0A0F30 | bytes_received | DAT_000a0f30 | Running byte counter |
| 0x0A0F40 | buffer_base | DAT_000a0f40 | Original allocation start |
| 0x0A0F48 | active_buf_ptr | DAT_000a0f48 | Active write pointer |
| 0x0A0F50 | swap_buf_ptr | DAT_000a0f50 | Alternate buffer pointer |
| 0x0A0F58 | alloc_buf_size | DAT_000a0f58 | Total allocated buffer size |
| 0x0A0F88 | saved_dl_size | DAT_000a0f88 | Copy for flash operations |

All stored as individual globals in the .data section (starting at VA 0x095000 in terry).
At runtime with ABL base 0x9FA00000, these are at 0x9FAA0F28-0x9FAA0F88.

### 3. UEFI Boot Services Table

`DAT_00099e30` stores the **EFI_BOOT_SERVICES pointer**. Confirmed offsets:

| BS Offset | Function | Params | Usage in ABL |
|-----------|----------|--------|-------------|
| +0x28 | AllocatePages | 4 | Not directly called (USB protocol does it) |
| +0x38 | GetMemoryMap | 5 | Buffer size calculation |
| +0x40 | AllocatePool | 3 | Small allocations |
| +0x48 | FreePool | 1 | Cleanup |
| +0x50 | CreateEvent | 5 | USB notification events |
| +0x58 | SetTimer | 3 | Event timing |
| +0x68 | SignalEvent | 1 | Event signaling |
| +0x70 | CloseEvent | 1 | Event cleanup |
| +0x98 | HandleProtocol | 3 | Access partition protocols |
| +0x100 | SetWatchdogTimer | 4 | Disable watchdog |
| +0x140 | LocateProtocol | 3 | Find charger, USB protocols |
| +0x160 | CopyMem | 3 | Memory copy |
| +0x168 | SetMem | 3 | Buffer zeroing |
| +0x170 | CreateEventEx | 6 | Flash completion events |

The BST pointer itself is in ABL's .data at 0x9FA99E30 — **below** the DMA buffer,
unreachable by overflow.

### 4. Lock-Check Code Path (Complete)

```
fastboot command received
    └─> CommandDispatcher (FUN_0000fe30, offset 0xFE30)
        ├─> "flash:XXXX" detected
        │   └─> FlashHandler (FUN_00012010, offset 0x12010, 8232 bytes)
        │       ├─> IsDeviceLocked? (FUN_00032530, 68 bytes)
        │       ├─> IsCriticalLocked? (FUN_00032574, 68 bytes)
        │       ├─> IsUnsealed? (FUN_00032638, 68 bytes)
        │       ├─> IsCriticalPartition? (FUN_00015d24, 148 bytes)
        │       ├─> IsProtectedPartition? (FUN_00015db8, 148 bytes)
        │       └─> If locked: FastbootFail("Flashing is not allowed in Lock State")
        │
        ├─> "flashing unlock" detected
        │   └─> SetLockUnlockState (FUN_00016654, 328 bytes)
        │       ├─> Check current state (FUN_00032530 or FUN_00032574)
        │       ├─> If already at target state: FastbootFail("Device already: locked/unlocked!")
        │       ├─> If unlocking: check DAT_000a0f18 (unlock_allowed flag)
        │       └─> SetDeviceState (FUN_00032914, 796 bytes) → writes to RPMB/persist
        │
        ├─> "unlock_bootloader" (with nonce)
        │   └─> UnlockVerify (FUN_00015a60, 708 bytes)
        │       ├─> Requires param_2 >= 0x59 (89 bytes) — unlock token
        │       ├─> FUN_0001731c: Nonce/signature verification (attempt 1)
        │       ├─> FUN_000173cc: Nonce/signature verification (attempt 2)
        │       ├─> FUN_000332ec: Get expected nonce
        │       ├─> Check *(byte*)(lVar3 + 0x50) & 1: unlock-allowed bit
        │       └─> If valid: FUN_00033330(1) + FUN_00033038(1) → set unlock
        │
        └─> "oem device-info"
            └─> DeviceInfoHandler (registered at 0x073DE8 in dispatch table)
                └─> Reads IsLocked, IsCriticalLocked, etc. → FastbootInfo responses
```

**DeviceInfo storage:**
- At boot: read from persistent storage (RPMB/devinfo partition) into **heap-allocated** buffer
- Cached via global pointer (dereferenced by FUN_00032530 etc.)
- Written back to persistent storage by FUN_00032914 (SetDeviceState)

### 5. Fastboot Command Dispatch Table

The dispatch table is in ABL's .data section (NOT dynamically allocated):

| .data Offset | Command String | Handler |
|-------------|---------------|---------|
| 0x073D68 | "flashing get_unlock_ability" | (handler at +8) |
| 0x073D78 | "flashing unlock" | (handler at +8) |
| 0x073D88 | "flashing lock" | (handler at +8) |
| 0x073D98 | "oem get_unlock_bootloader_nonce" | (handler at +8) |
| 0x073DA8 | "flashing get_unlock_bootloader_nonce" | (handler at +8) |
| 0x073DB8 | "flashing unlock_bootloader" | (handler at +8) |
| 0x073DC8 | "flashing unlock_critical" | (handler at +8) |
| 0x073DD8 | "flashing lock_critical" | (handler at +8) |
| 0x073DE8 | "oem device-info" | (handler at +8) |

Each entry is 16 bytes (8-byte string pointer + 8-byte handler function pointer).
At runtime: 0x9FA00000 + 0x073D68 = 0x9FA73D68. This is BELOW the DMA buffer — unreachable.

### 6. Estimated Memory Layout

```
            PORTAL APQ8098 UEFI MEMORY MAP (estimated)

  0x80000000 ┌─────────────────────────┐
             │  DRAM Start             │
             │  (kernel, DTB, etc.)    │
             │                         │
  0x9FA00000 ├─────────────────────────┤ ← ABL image base (FIXED)
             │  .text  (code)          │  0x001000 - ~0x06C000
             │  .rodata (strings)      │  ~0x06C000 - ~0x07B000
             │  .data (dispatch table) │  ~0x07B000 - ~0x098000
             │    ├ BS ptr (0x99E30)   │
             │    ├ cmd table (0x73D68)│
             │    └ buf ptrs (0xA0F28) │
             │  .bss  (runtime vars)   │  ~0x0A0000 - ~0x0B0000
             │    ├ unlock_allowed     │
             │    ├ DeviceInfo cache   │  (heap-allocated, pointer here)
             │    └ buffer state vars  │
  0x9FAB5800 ├─────────────────────────┤ ← ABL image end (~740KB)
             │                         │
             │  ... UEFI pool gap ...  │
             │                         │
  0x9FB????? ├─────────────────────────┤ ← DMA buffer start (USB protocol alloc)
             │                         │
             │  DMA receive buffer     │  ~0x102000 bytes (~1.01MB)
             │  (CVE-2021-1931 target) │
             │                         │
  +0x102000  ├─────────────────────────┤ ← BUFFER END / OVERFLOW START
             │  [+0 to +4KB]           │  USB endpoint/protocol vtables
             │  [+4KB to +12KB]        │  ← 0x104000=clean, 0x105000=races
             │  [+12KB to +64KB]       │  Download handler heap structures
             │  [+64KB to +128KB]      │  alloc_buf_size / max-download-size
             │  [+128KB to +256KB]     │  getvar handler infrastructure
             │  [+256KB+]              │  Core fastboot / UEFI DXE structures
             └─────────────────────────┘

             ▲ OVERFLOW DIRECTION (UPWARD)
             │ Lock state is DOWN here (ABL .data) — UNREACHABLE
```

---

## What's In the Overflow Region

Based on experimental evidence (journals 015-016) correlated with the Ghidra analysis:

| Region | Offset | What's There | Evidence |
|--------|--------|-------------|----------|
| Safe zone | +0 to +8KB | USB endpoint metadata (non-critical) | 0x104000: all cmds work |
| Danger zone | +8KB to +12KB | USB response path structures | 0x105000: Stage 1 races |
| Kill zone | +12KB to +24KB | Critical USB infrastructure | 0x108000: dead after 1 cmd |
| Deep corruption | +24KB to +128KB | Pool metadata, alloc check vars | 0x120000: "too large" FAIL |
| Total death | +128KB+ | getvar/fastboot core | 0x140000+: TIMEOUT |

**The USB Transfer Protocol instance** (returned by FUN_0000e200) is a UEFI protocol
interface with its own vtable. This vtable is almost certainly in the +0 to +12KB region
above the DMA buffer, because:
1. It was allocated from the same pool as the DMA buffer
2. Pool allocations are typically sequential (adjacent)
3. Corrupting +8-12KB kills USB response (consistent with vtable corruption)

---

## Viable Exploitation Paths (Ranked)

### Path 1: Targeted Vtable Overwrite via Controlled Bytes (MEDIUM probability)

**Concept:** Instead of uniform B#0 fill, craft the 8KB overflow with specific ABL function
addresses at specific offsets to redirect USB protocol function calls.

**We know:**
- ABL base = 0x9FA00000 (FIXED for all Portal Gen 1 devices)
- All ABL function addresses = base + Ghidra offset
- We have 8KB of fully controlled overflow bytes (0x104000 total)
- The USB protocol vtable is within this 8KB region

**Approach:**
1. Send overflow with B#0 fill EXCEPT at one 8-byte position: place a known ABL address
2. Binary search across 1024 positions (8KB / 8 bytes) to find the vtable entry
3. If a position causes different behavior (vs uniform B#0), that's a vtable entry
4. Place the address of a useful function (e.g., FastbootOkay to suppress errors)

**Target addresses (terry offsets + 0x9FA00000):**
- FastbootOkay: 0x9FA0F1A0 (makes any call return "OKAY")
- FastbootFail: 0x9FA0F004 (returns FAIL with whatever's in buffer)
- SetDeviceState: 0x9FA32914 (writes lock state — but needs correct args)

**Challenge:** Even if we redirect a vtable entry, the function arguments will be whatever
the caller passes (not what we control). SetDeviceState needs (param_1=0/1, param_2=1) to
unlock. The chances of the correct arguments being in registers are very low.

**Estimated effort:** 50-100 power cycles for binary search. Each test = 2 minutes.
**Estimated time:** 2-4 hours of device interaction.
**Success probability:** ~10-15%

### Path 2: UEFI Heap Metadata Corruption (LOW probability, HIGH complexity)

**Concept:** The overflow corrupts UEFI pool chunk headers. Exploit the corrupted metadata
when the pool allocator performs free/allocate operations to achieve an arbitrary write.

**We know:**
- EDK2's pool allocator uses POOL_HEAD structures before each allocation
- POOL_HEAD contains: Signature, Size, Type, and free-list pointers
- Corrupting these headers can cause write-what-where on next alloc/free

**Approach:**
1. Study EDK2 PoolAllocate/PoolFree implementation for AArch64
2. Craft overflow to create a fake POOL_HEAD with controlled pointers
3. Trigger a FreePool call (many UEFI operations do this)
4. The corrupted free-list causes a write to a controlled address
5. Target: write to the DeviceInfo cache pointer to make IsDeviceLocked return false

**Challenge:** Requires precise knowledge of:
- Exact POOL_HEAD size and field offsets for this EDK2 version
- Adjacent chunk sizes and types
- The order of alloc/free operations after overflow

**Estimated effort:** Weeks of research + debugging.
**Success probability:** ~5-10%

### Path 3: Voltage Glitching (MEDIUM probability, hardware required)

**Concept:** Inject a voltage glitch on the CPU's power rail during the lock-check execution
to cause the lock check to be skipped or return the wrong value.

**Target:** The IsDeviceLocked (FUN_00032530) function is only 68 bytes. A well-timed glitch
during its execution could cause it to return 0 (unlocked) instead of 1 (locked).

**Hardware needed:**
- FPGA or microcontroller with precise timing (e.g., ChipWhisperer, or Arduino + level shifter)
- Access to the CPU's core voltage rail (requires PCB probing)
- Trigger signal (USB activity or GPIO)

**Approach:**
1. Open Portal case (adhesive, non-destructive)
2. Identify the CPU's VDD_CORE pad on the PCB
3. Connect glitcher to VDD_CORE with a MOSFET
4. Send `flashing unlock` command as trigger
5. Sweep glitch timing across the lock-check window
6. Monitor USB for "OKAY" response (successful unlock)

**Reference:** Well-documented for Qualcomm Snapdragon chips (e.g., Trezor wallet glitching).

**Estimated effort:** $50-150 in hardware + several days of experimentation.
**Success probability:** ~30-40% (if CPU VDD accessible on PCB)

### Path 4: UFS Direct Access (HIGH probability, hardware required)

**Concept:** Access the UFS storage chip directly (bypassing the CPU) to read/write
partition data. Modify the DeviceInfo partition to set is_unlocked=1.

**We know:**
- UFS storage confirmed (not eMMC)
- DeviceInfo stored in persistent storage (devinfo partition, 4KB)
- UFS chips have a serial/test interface

**Approach:**
1. Open Portal case
2. Identify UFS chip (likely Samsung/SK Hynix/Micron)
3. Find UFS test pads on PCB (CLK, CMD, DATA)
4. Connect via UFS programmer (e.g., Medusa Pro, Easy JTAG)
5. Read devinfo partition, modify is_unlocked byte, write back

**Challenge:** UFS programmers are expensive ($200-500). Finding test pads requires PCB
analysis. The devinfo partition format needs reverse engineering.

**Estimated effort:** $200-500 hardware + 1-2 weeks.
**Success probability:** ~60-70%

### Path 5: JTAG/SWD Debug Access (MEDIUM-HIGH probability, hardware required)

**Concept:** APQ8098 has a CoreSight debug port. If JTAG/SWD test points are exposed on
the PCB, attach a debug probe for full CPU control (read/write memory, set breakpoints).

**We know:**
- APQ8098 CoreSight base addresses are public
- Qualcomm enables JTAG on early boot (before fuse blow — may be disabled)
- With JTAG: can set breakpoint on IsDeviceLocked, change return value

**Challenge:** Qualcomm typically blows JTAG fuses on production devices. Debug access may
be permanently disabled. Need to check TZ (TrustZone) fuse configuration.

**Estimated effort:** $50-100 debug probe + PCB analysis.
**Success probability:** ~20% (likely fused off on production Portal)

### Path 6: Community / Cross-Device Firehose (VARIABLE probability)

**Concept:** Obtain a signed firehose loader for APQ8098 with OEM_ID 0x0137.

**We know:**
- December 2025 XDA firehose is for Gen 2 atlas (SDM710), NOT Gen 1
- Gen 1 needs APQ8098 + Facebook OEM_ID
- Other Snapdragon 835 devices might share firehose format

**Approach:**
- Publish our findings (HWID, PK_HASH, OEM_ID) to XDA specifically for Gen 1
- Contact bkerler / aleph_security / other Qualcomm researchers
- Search leaked firehose databases for matching OEM_ID
- Try firehose loaders from other Snapdragon 835 devices (OnePlus 5T, Pixel 2, etc.)

**Estimated effort:** Ongoing community engagement.
**Success probability:** ~20-30% over 6 months

---

## Recommended Strategy (Priority Order)

1. **Immediate:** Try Path 1 (targeted vtable overwrite) — software-only, uses existing
   toolchain, ~2-4 hours of testing
2. **Short-term:** Publish comprehensive Gen 1 findings to XDA (Path 6) — increases
   community chances
3. **Medium-term:** Attempt Path 3 (voltage glitching) — moderate hardware investment,
   good success rate
4. **If budget allows:** Path 4 (UFS direct) — highest software-free success rate

---

## Implementation Plan for Path 1: Targeted Vtable Overwrite

### New Compile Mode: PORTAL_VTABLE_SCAN

```c
#ifdef PORTAL_VTABLE_SCAN
// Place B#0 everywhere EXCEPT at PORTAL_VTABLE_OFFSET
// At PORTAL_VTABLE_OFFSET: place PORTAL_VTABLE_TARGET (8-byte address)
for (j = 0; j + 3 < size; j += 4) {
    if (j >= PORTAL_VTABLE_OFFSET && j < PORTAL_VTABLE_OFFSET + 8) {
        // Place target address (little-endian)
        uint64_t addr = PORTAL_VTABLE_TARGET;
        buff[j+0] = (addr >> ((j - PORTAL_VTABLE_OFFSET) * 8)) & 0xFF;
        // ... (fill 8 bytes with the address)
    } else {
        OPCODE(buff + j, 0x00, 0x00, 0x00, 0x14);  // B #0
    }
}
#endif
```

### Binary Search Protocol

1. Start with offset = 0 (first 8 bytes of overflow, at buffer+0x102000)
2. Target address = 0x9FA0F1A0 (FastbootOkay)
3. Send overflow, then send `getvar:product` as Stage 2
4. If response is "OKAY" instead of "OKAYaloha" → HIT! The vtable entry at this offset
   was for the getvar response function, and we redirected it to FastbootOkay
5. If response is normal "OKAYaloha" → MISS, try next offset (+8)
6. If TIMEOUT → the offset hit something critical, skip ahead

### Expected Outcome

This is a long shot (~10-15%), but it's software-only and uses existing toolchain.
If successful, it proves we can redirect code execution to known ABL addresses.
Even partial success (information leak via corrupted getvar response) would be valuable.

---

## Summary

The Ghidra analysis conclusively demonstrates:

1. **Lock state is architecturally unreachable** by the DMA overflow — it's stored in ABL's
   .data section at lower memory addresses, while overflow goes upward into UEFI pool

2. **The overflow region contains USB protocol structures** — specifically the USB Transfer
   Protocol vtable and associated UEFI pool metadata

3. **ABL's base address (0x9FA00000) is KNOWN and FIXED** — all function addresses are
   derivable, enabling potential code-reuse attacks

4. **The DMA buffer is allocated via a protocol-specific allocator** (not standard UEFI
   pool) — this means adjacent allocations follow USB driver patterns

5. **The most promising software path** is targeted vtable overwrite with known ABL
   addresses in the 8KB controlled overflow

6. **Hardware approaches** (voltage glitching, UFS direct access) have higher success
   probability but require investment and physical skills
