# Journal 027: Full Arbitrary Code Execution from Wasm Memory — CONFIRMED

**Date:** 2026-03-12
**Status:** MILESTONE — Stage 1 Pipeline Complete

## Summary

The mprotect+jump stager is confirmed working. The full 944-byte v20s shellcode
executes from wasm memory with 100% reliability (4/4 on first attempts).

## Critical Finding: Previous Session Summary Was WRONG

The previous session claimed fold_probe "crashed 0/4". Re-analysis of the ACTUAL
log data shows fold_probe was **4/4 SUCCESS** (PIDs 4795, 4949, 4866, 5082).
V8 constant-folds `A * 0x10000 + B` at compile time — the entire encoding width
analysis was based on a flawed model. We have full 32-bit control of all stager
constants, and w[0]-w[N] in the separate IIFE are freely changeable.

## Results Timeline

| Test | Time | Result | Implication |
|------|------|--------|-------------|
| fold_probe | 09:31-09:46 | 4/4 SUCCESS (PIDs) | V8 constant-folds, full 32-bit control |
| mprotect_probe | 10:55, 11:02 | 2/2 R0=0 | SECCOMP allows mprotect+PROT_EXEC |
| mprotect_jump | 14:09-15:04 | 4/4 0xFE20 | Full code execution from wasm memory |

## mprotect_jump Details

All 4 runs returned 0xFE20 = no_corruption, writev=31, 32 attempts.

The v20s shellcode (CVE-2019-2215 exploit) ran COMPLETELY from wasm memory:
- Opened /dev/binder (openat syscall)
- Created epoll instances (epoll_create1)
- Set BINDER_SET_MAX_THREADS (ioctl)
- Called BINDER_THREAD_EXIT (ioctl)
- Ran 32 UAF attempts with 31-entry iovec writev
- Each writev returned 31 (correct — binder UAF is patched, no corruption)
- Returned cleanly to WASM caller with result code
- ~13 seconds execution time per run

wasm_mem addresses (all page-aligned, varying due to ASLR):
- 0x33ec0000, 0x5a780000, 0x44b90000, 0xef5c0000

## Full Pipeline

```
Captive Portal WiFi → Chrome WebView → CVE-2020-16040 (V8 RCE)
  → OOB array → arb R/W primitives → read RWX page address
  → write mprotect+jump stager to RWX page
  → mprotect(wasm_mem, 64KB, PROT_RWX)
  → BX R4 → execute ARM32 shellcode from wasm memory
  → [NEXT: kernel exploit here]
  → [GOAL: root → enable ADB → repurpose device]
```

## Kernel Exploit Targets (Both Confirmed Unpatched)

1. **CVE-2021-1048** (epoll UAF) — PRIMARY
   - ep_remove_safe ABSENT from kernel
   - Race: close() vs epoll_ctl(EPOLL_CTL_ADD) on epoll-in-epoll
   - Freed object: struct epitem (~128 bytes, epi_cache or kmalloc-128)
   - Fix: November 2021 (~12 months after firmware freeze)

2. **CVE-2021-0920** (unix_gc UAF) — BACKUP
   - unlock-purge-relock pattern confirmed in binary disassembly
   - Race: close()/GC vs MSG_PEEK on Unix sockets
   - Fix: November 2021

## Key Challenge: KASLR

CONFIG_RANDOMIZE_BASE=y in kernel config, but:
- Kernel 4.4 AArch64 didn't have upstream KASLR (added in 4.6)
- May be a vendor backport, may be broken, may have low entropy
- If KASLR is active: need pointer leak before privilege escalation
- If KASLR is inactive: exploit with pre-KASLR addresses directly

## Next Steps

1. Write syscall_test shellcode: verify socketpair, sendmsg, clone from wasm_mem
2. Design CVE-2021-1048 exploit (or consider two-stage HTTP download approach)
3. Handle KASLR (test with pre-KASLR addresses first)
4. Privilege escalation: overwrite creds, disable SELinux
5. Enable ADB, disable dm-verity, flash custom boot image
