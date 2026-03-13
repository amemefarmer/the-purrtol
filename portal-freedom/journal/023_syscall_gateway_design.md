# Journal 023: Syscall Gateway Design — From 16-Byte Shellcode to Full Kernel Exploit

**Date:** 2026-03-05
**Status:** Phase 1 — testing arbwrite count tolerance

---

## Problem Statement

We have confirmed renderer RCE via CVE-2020-16040 on Chrome 86 ARM32. We can execute arbitrary 16-byte (4 ARM32 instructions) shellcode on the WASM RWX page. All three gates for CVE-2019-2215 are clear:

| Gate | Status | Evidence |
|------|--------|---------|
| SECCOMP | ✅ ioctl fully allowed | Chrome 86 `baseline_policy_android.cc`: `__NR_ioctl` → `override_and_allow = true`. Android policy is LOOSER than desktop — no `RestrictIoctl()` command filtering. |
| SELinux | ✅ /dev/binder allowed | `base_typeattr_66 = (appdomain ∪ coredomain ∪ binder_in_vendor_violators) - hwservicemanager`. CIL bare-list = UNION. isolated_app ∈ appdomain → covered. No neverallow on binder_device for isolated_app. |
| Binder fd | ✅ Openable or inherited | openat is SECCOMP-allowed on Android ("filesystem access cannot be restricted with seccomp-bpf"). Zygote opens /dev/binder before forking; renderer may inherit fd. |

**The challenge:** CVE-2019-2215 requires hundreds of instructions (open binder, set up epoll, trigger UAF, spray iovec, corrupt task_struct, patch credentials). We can only write **16 bytes** to the RWX page without breaking the exploit's V8 heap layout sensitivity.

---

## Root Constraint: BytecodeArray Size Sensitivity

The exploit's reliability depends on `cor[3]` reading the correct `float_array_map` value from adjacent memory. What `cor[3]` reads depends on V8's new-space bump allocator position, which is determined by the total bytes allocated before `cor`'s FixedDoubleArray.

`exploit()` is compiled to a BytecodeArray (a heap-allocated object). Its size depends on:
- Number of bytecode instructions (each arbwrite call ≈ 30-40 bytecodes)
- Constant pool entries (each unique Number literal = 1 entry)
- Function declarations (closures allocated at function entry)

**v11** works with:
- 3 arbwrite calls (2 shellcode + 1 trampoline) → ~100 bytecodes for arbwrite section
- 4 unique shellcode constants → 4 constant pool HeapNumber entries
- ~70 LOC total in exploit()

**v10b-v10f** all crashed because of larger exploit() bodies (more arbwrites, more helpers, more constants).

---

## Solution Architecture: Mprotect Stager + WASM Memory

### Overview

```
┌─────────────────────────────────────────────────────────┐
│  JavaScript (exploit() function)                        │
│                                                         │
│  1. Fill WASM memory with CVE-2019-2215 shellcode       │
│     (global scope, before exploit() — no bytecode cost) │
│                                                         │
│  2. Trigger CVE-2020-16040 → OOB → arbread/arbwrite     │
│                                                         │
│  3. Find WASM memory address via arbread                 │
│                                                         │
│  4. Write 32-byte mprotect stager to RWX+0x400          │
│     (4 arbwrites for stager + 1 for trampoline = 5)     │
│                                                         │
│  5. Call wasm_func() → trampoline → stager              │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  ARM32 Mprotect Stager (32 bytes at RWX+0x400)          │
│                                                         │
│  LDR  R4, [PC, #20]    ; R4 = wasm_mem_addr            │
│  MOV  R0, R4            ; mprotect addr                 │
│  MOV  R1, #0x10000      ; len = 64KB                    │
│  MOV  R2, #7            ; PROT_RWX                      │
│  MOV  R7, #125          ; __NR_mprotect                 │
│  SVC  #0                ; mprotect()                    │
│  BX   R4                ; jump to WASM memory           │
│  .word wasm_mem_addr    ; embedded data                 │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  WASM Linear Memory (64KB, now RWX after mprotect)      │
│                                                         │
│  Full CVE-2019-2215 Binder UAF Exploit                  │
│  - Open /dev/binder (openat or use inherited fd)        │
│  - Set max threads (ioctl BINDER_SET_MAX_THREADS)       │
│  - Create epoll (epoll_create1)                         │
│  - Register binder fd with epoll (epoll_ctl)            │
│  - Trigger UAF (ioctl BINDER_THREAD_EXIT + close)       │
│  - Spray iovec (writev on pipe with 32 iovecs)          │
│  - Leak task_struct from corrupted iovec                │
│  - Second UAF → overwrite addr_limit → kernel R/W       │
│  - Patch cred (UID/GID=0, caps=0x3ffffffffful)         │
│  - Disable SELinux (write 0 to selinux_enforcing)       │
│  - Clear SECCOMP filter                                 │
│  - Enable ADB (write to system properties)              │
│  - Return result code to JavaScript                     │
└─────────────────────────────────────────────────────────┘
```

### Why WASM Memory?

WASM linear memory is ideal as a payload staging area because:
1. **Pre-filled from JavaScript** — `new Uint8Array(wasm_instance.exports.memory.buffer)` gives direct access. Writing shellcode happens in global scope, before exploit(), with ZERO impact on exploit()'s bytecode.
2. **Contiguous and large** — 64KB (1 WASM page), more than enough for the kernel exploit (~2-4KB).
3. **Page-aligned** — mprotect requires page-aligned addresses. WASM memory is allocated via mmap and is naturally page-aligned.
4. **Known address** — findable via arbread on the WasmInstanceObject or the ArrayBuffer backing store.

### Why Not Alternatives?

| Alternative | Why not |
|-------------|---------|
| More arbwrite calls | Each call adds ~35 bytecodes to exploit(). Writing 2KB of shellcode = 250 arbwrites = ~8750 extra bytecodes. Would definitely break heap layout. |
| eval() inside exploit() | eval() triggers string parsing → heap allocation → potential GC → arr2 moves → arbwrite breaks. |
| Parameterized WASM + JS-driven syscalls | Each wasm_func(args) call changes bytecode. 20+ calls for CVE-2019-2215 = massive bytecode change. |
| Global arrays with shellcode | Global scope arrays shift V8 new-space allocator → cor[3] reads wrong map (proven in v10b, v10d). |
| Write shellcode to file, exec | Requires openat+write+execve, all multi-instruction. Can't bootstrap from 16 bytes. |

---

## Phased Implementation

### Phase 1: Arbwrite Count Tolerance (CURRENT)

**Goal:** Determine if adding 2 extra arbwrites (5 total, up from 3) breaks the exploit.

**Method:**
- Keep getpid shellcode at RWX+0x400 (proven to work)
- Add 2 extra arbwrites at RWX+0x410 and RWX+0x418 writing harmless bytes
- Extra arbwrites reuse the SAME 4 constants as lines 145-146 (no new constant pool entries)
- The extra bytes at +0x410-+0x41F are never executed (POP at +0x40C returns first)

**Rationale for reusing constants:**
V8's constant pool (FixedArray) allocates one slot per UNIQUE constant. If the extra arbwrites use the same 4 hex values as the existing ones (just in different order), the constant pool stays at 4 entries → same FixedArray allocation → same heap layout contribution from the constant pool.

The BytecodeArray still grows (~70 bytes for 2 extra arbwrite calls), but this is a smaller change than adding new constants.

**Expected result:** getpid returns a PID → 5 arbwrites work.

**If it crashes:** Reduce to 4 arbwrites (1 extra) and retry. If 4 also crashes, the BytecodeArray size is the binding constraint and we need eval() or a completely different approach.

### Phase 2: Mprotect Stager

**Prerequisites:** Phase 1 confirms 5 arbwrites work.

**Implementation:**
1. Fill WASM memory with CVE-2019-2215 shellcode (from global scope)
2. In exploit(), find WASM memory address via arbread:
   - `addrof(wasm_instance.exports.memory.buffer)` → ArrayBuffer addr
   - `arbread(ab_addr + backing_store_offset)` → backing store ptr
3. Write 32-byte mprotect stager to RWX+0x400 (4 arbwrites)
4. Embed WASM memory address at RWX+0x41C (part of 4th arbwrite)
5. Trampoline redirect (5th arbwrite)
6. Call wasm_func() → mprotect → jump

**Stager encoding (ARM32):**
```
+0x400: 0xE59F4014  LDR  R4, [PC, #20]    ; R4 = wasm_mem_addr (from +0x41C)
+0x404: 0xE1A00004  MOV  R0, R4            ; R0 = addr for mprotect
+0x408: 0xE3A01801  MOV  R1, #0x10000      ; len = 64KB
+0x40C: 0xE3A02007  MOV  R2, #7            ; PROT_READ|PROT_WRITE|PROT_EXEC
+0x410: 0xE3A0707D  MOV  R7, #125          ; __NR_mprotect
+0x414: 0xEF000000  SVC  #0                ; mprotect(wasm_mem, 0x10000, 7)
+0x418: 0xE12FFF14  BX   R4                ; jump to wasm_mem
+0x41C: <addr>      .word wasm_mem_addr    ; embedded data (computed at runtime)
```

**Constant pool strategy:** The stager introduces 7 new ARM encoding constants. To minimize constant pool growth, these can be computed at runtime from SMI-range components:
```javascript
var c = (0xE59F << 16) + 0x4014; // LDR R4,[PC,#20] = 0xE59F4014
```
SMI values (< 65536) use LdaSmi bytecodes without constant pool entries. The result (> 2^30) becomes a HeapNumber at RUNTIME, not in the constant pool.

### Phase 3: CVE-2019-2215 Shellcode

The full Binder UAF exploit as ARM32 shellcode in WASM memory. Key components:
- String constants ("/dev/binder", etc.) embedded in the shellcode
- Stack frame setup for local variables
- Kernel offset constants (WAITQUEUE_OFFSET=0xA0, OFFSET_CRED=0x7B8, etc.)
- KASLR handling via task_struct leak

**Estimated size:** ~2-4KB of ARM32 code.

### Phase 4: Post-Exploitation

After kernel exploit succeeds (root + SELinux disabled + SECCOMP cleared):
- Enable ADB via system properties
- Connect ADB over WiFi
- Persist root access

---

## Risks and Mitigations

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| 5 arbwrites breaks heap layout | Medium | Test incrementally (4, then 5). Fall back to eval() approach. |
| mprotect on WASM memory fails | Low | WASM memory is mmap'd RW. mprotect to RWX should work (no SECCOMP block on mprotect, no SELinux restriction on mprotect). |
| WASM memory address finding fails | Low | Multiple offset candidates. Can scan WasmInstanceObject fields empirically. |
| CVE-2019-2215 kernel exploit fails | Medium | KASLR adds complexity. Need info leak to find kernel slide. Task_struct iovec leak provides this. |
| KASLR slide brute-force needed | Medium | iovec leak from first UAF gives task_struct address. Compute KASLR slide from known pre-KASLR symbols. |

---

## Files

- `captive-portal/www/exploit/rce_chrome86.html` — main exploit (Phase 1 test current)
- `journal/023_syscall_gateway_design.md` — this document
- `journal/022_meta_token_cost_cil_misinterpretation.md` — CIL analysis failure post-mortem

---

## Key References

- Chrome 86 SECCOMP: `baseline_policy_android.cc` — ioctl plainly allowed on Android
- SELinux CIL: `plat_sepolicy.cil` line 17434 — base_typeattr_66 is a UNION (bare list), not intersection
- CVE-2019-2215: Maddie Stone / Project Zero analysis — ITW exploit used binder from Chrome renderer
- V8 8.6 heap layout: BytecodeArray + ConstantPool determine new-space allocator position
