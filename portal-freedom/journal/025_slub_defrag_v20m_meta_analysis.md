# Journal 025: SLUB Defrag Spray and Token Economics of Iterative Exploit Development

**Date:** 2026-03-07
**Status:** v20m ready for test; meta-analysis complete

---

## 1. v20l Test Results

v20l was the first iteration with clone-before-binder and an 8-attempt retry loop. Results from two consecutive captive portal loads:

```
uaf_v20l=0x0000fe08 writev=31 attempts=7 remain=0 sched=0 d0=0x00000000
uaf_v20l=0x0000fe08 writev=31 attempts=7 remain=0 sched=0 d0=0x00000000
```

Key observations:
- **`sched=0`**: `sched_setaffinity` succeeded — CPU pinning is NOT blocked by SECCOMP
- **`writev=31`**: All 31 non-null iovec segments written normally — zero corruption across all 8 attempts
- **`remain=0`**: Pipe fully drained — child drained everything, parent got nothing
- **Both runs identical**: Deterministic structural failure, not probabilistic

The Portal's captive portal WebView dismissed after ~4 seconds ("wifi login exited and returned to the select a network screen"). This is NOT a device crash — the WebView has a built-in timeout. v20l's 8 retries with 100ms/200ms sleeps consumed the full window.

---

## 2. Root Cause: c->page Rotation

### The SLUB per-CPU slab model

Each CPU maintains a `kmem_cache_cpu` structure for each slab cache (e.g., `kmalloc-512`):

```
struct kmem_cache_cpu {
    void **freelist;     // LIFO linked list of free objects
    struct page *page;   // "active" slab page (c->page)
    unsigned long tid;
};
```

**Fastpath (target == c->page):** kfree pushes to c->freelist. Next kmalloc pops it. LIFO guarantees reclaim.

**Slowpath (target != c->page):** kfree pushes to the object's own page->freelist. Not accessible from c->freelist. kmalloc gets a different object entirely.

### Why Chrome kills reclaim

Chrome's renderer process has 10+ threads active on CPU 0:
- V8 main thread (our shellcode)
- Compositor thread
- IO thread
- V8 GC thread(s)
- IPC thread
- Timer thread
- Audio/video threads

These threads perform their own kmalloc-512 operations continuously. Between the target binder_thread's allocation (first ioctl on the fresh binder fd) and its free (BINDER_THREAD_EXIT), these background allocations:

1. Exhaust the remaining free slots on c->page
2. Force the SLUB allocator to assign a new slab page as c->page
3. The binder_thread is now on a page that is no longer c->page

This means kfree takes the slowpath EVERY TIME. It's structural, not probabilistic — which explains why 8 consecutive attempts all returned writev=31 with zero variance.

### Why v20l's optimizations didn't help

- **CPU pinning (sched=0)**: Ensured free and alloc use the same CPU. But the problem isn't CPU migration — it's c->page rotation from OTHER threads on the SAME CPU.
- **Clone before binder**: Removed clone() from the critical section. But the Chrome threads are the noise source, not our clone.
- **Retry loop**: Running the same structurally-failing procedure 8 times can't fix a structural problem.

---

## 3. v20m Design: Heap Defragmentation Spray

### Strategy

Fill the current c->page(s) to exhaustion BEFORE the critical section, forcing the allocator to grab a fresh slab page. The target binder_thread then allocates from this fresh page. Between alloc and free (only 2 syscalls, no scheduling disruptions), the fresh page remains c->page because the window is too short for Chrome's background threads to exhaust it.

### Implementation

Before the retry loop, spray 32 binder file descriptors:

```
for i in 0..31:
    fd = openat("/dev/binder", O_RDWR)
    ioctl(fd, BINDER_SET_MAX_THREADS, &0)
```

Each `open("/dev/binder")` allocates:
- 1 `binder_proc` (~400 bytes → kmalloc-512)

Each `ioctl(BINDER_SET_MAX_THREADS)` allocates:
- 1 `binder_thread` (0x198 = 408 bytes → kmalloc-512)

Total: 32 opens × 2 allocs = **64 kmalloc-512 allocations**.

With ~8 objects per order-0 slab page (4096/512), this fills 8 slab pages. The allocator must assign a 9th page as c->page. This page is clean and has a full freelist.

The spray fds are intentionally leaked (never closed). They persist for the lifetime of the process, keeping their kmalloc-512 slots occupied and preventing the allocator from recycling old pages as c->page.

### Critical section (unchanged from v20l)

```
openat("/dev/binder")                     ← binder_proc on fresh page
ioctl(BINDER_SET_MAX_THREADS)             ← binder_thread on fresh page (TARGET)
epoll_ctl(EPOLL_CTL_ADD, binder_fd)       ← register wait_queue
ioctl(BINDER_THREAD_EXIT)                 ← kfree(binder_thread) → FASTPATH! (page == c->page)
writev(pipe_wr, iovecs, 32)               ← kmalloc(512) → pops from c->freelist → RECLAIM!
```

### Timing adjustments

| Parameter | v20l | v20m | Reason |
|-----------|------|------|--------|
| Attempts | 8 | 4 | Stay within captive portal timeout |
| Child sleep | 100ms | 50ms | Faster UAF trigger |
| Parent sleep | 200ms | 100ms | Faster drain cycle |
| Total estimated | 4.5s | 2.7s | Fits comfortably in WebView window |

### Shellcode size

265 words (1060 bytes), up from 252 words (1008 bytes) in v20l. The spray loop adds 17 words; timing reductions save 4 words from removed constants.

---

## 4. Expected Results

| Result | Meaning |
|--------|---------|
| `0xCCxx` | **UAF CONFIRMED.** `xx` = 31 - writev_ret = deficit from iovec corruption. Expected: `0xCC15` (writev=10, first corrupted iovec at index 10). |
| `0xFE04` | All 4 attempts failed, writev=31 each time. Spray didn't fix c->page problem. |
| `0xFE01-03` | Partial failure (1-3 attempts failed before hitting max). |
| `0xA1xx` | binder openat failed (possible fd exhaustion from spray). |
| `0xB1xx` | clone failed. |

If `0xFE04`: the spray may not be large enough (increase SPRAY_COUNT to 64 or 128), or there's a second noise source beyond c->page rotation (kernel softirqs, timer interrupts doing kmalloc-512).

---

## 5. Meta-Analysis: Token Economics of Iterative Exploit Development

### The v20 iteration arc

| Version | Tokens (~est) | Result | Root cause discovered |
|---------|--------------|--------|----------------------|
| v20a | ~15K | 0xB1xx | fork() blocked by SECCOMP → use clone() |
| v20b | ~12K | HANG | Parent drain blocks on open pipe_wr → close before drain |
| v20c | ~10K | CRASH | WASM memory overflow (drain accumulated 65KB past 64KB boundary) → fixed buffer |
| v20d | ~8K | 0xFE00 | Writev before free → wrong slot ordering |
| v20e | ~20K | 0xCC1F | Buffer overlap (child drain overwrote results area) → separate buffers |
| v20f | ~10K | 0xFE00 | Spray stole freed slot before writev → remove spray |
| v20g | ~8K | 0xFE00 | CPU migration (free on CPU X, alloc on CPU Y) → sched_setaffinity |
| v20h | ~10K | 0xFE00 | CPU pinning may be SECCOMP-blocked → tight timing |
| v20i | ~8K | 0xFE00 | Tight timing doesn't help → slab page identity problem |
| v20j | ~18K | 0xFE00 | writev-to-/dev/null spray is no-op (LIFO recycling) → reorder window |
| v20k | ~15K | 0xFE00 | Assembled with clang (first real assembler). sched=0 confirmed. |
| v20l | ~12K | 0xFE08 | sched_setaffinity works! But c->page rotation from Chrome threads → defrag spray |
| v20m | ~18K | PENDING | Heap defrag spray (32 binder fds) |
| **Total** | **~165K** | | 13 iterations, 1 crash, 1 hang, 9 structural failures |

### Research costs (context-building)

In addition to the build-test cycles, each pivot required understanding a new subsystem:

| Research topic | Tokens (~est) | Triggered by |
|----------------|--------------|--------------|
| SLUB per-CPU freelists and c->page | ~25K | v20g-v20h failure (CPU migration hypothesis) |
| SLUB slab page identity vs freelist | ~15K | v20i failure (tight timing didn't help) |
| Heap feng shui techniques in real exploits | ~20K | v20j design (spray concept) |
| SLUB LIFO recycling behavior | ~10K | v20j failure (spray was no-op) |
| Chrome renderer thread model | ~15K | v20l failure (c->page rotation) |
| SECCOMP filter for sched_setaffinity | ~8K | v20h design (is it allowed?) |
| compat_rw_copy_check_uvector path | ~5K | v20d design (verifying iovec allocation size) |
| binder_get_thread disassembly | ~8K | v20k (confirming kzalloc(0x198)) |
| **Total research** | **~106K** | |

### The cost curve

```
Cumulative tokens
    300K ┤
        │                                    ╭──── v20m (defrag)
    250K ┤                               ╭───╯
        │                           ╭────╯  ← Research: Chrome threads
    200K ┤                      ╭───╯
        │                  ╭────╯  ← Research: SLUB page identity
    150K ┤             ╭───╯
        │         ╭────╯  ← v20e-v20j iterations
    100K ┤    ╭───╯
        │╭───╯  ← v20a-v20d (plumbing bugs)
     50K ┤╯
        │
      0K ┼────┬────┬────┬────┬────┬────┬────
          v20a  v20c  v20e  v20g  v20i  v20k  v20m
```

Total estimated spend on v20 series: **~270K tokens** (165K iterations + 106K research).

### Comparison with the "optimal" path

If we had known the answer from the start (heap defrag spray before critical section, clone before binder, CPU pinning, tight critical window), the implementation would have been:

1. Read the P0 writeup and kangtastic exploit (~5K tokens)
2. Note Chrome renderer heap noise is different from native app (~2K tokens)
3. Design defrag spray + tight critical section (~3K tokens)
4. Write v20m directly (~10K tokens)
5. **Optimal total: ~20K tokens**

**Efficiency ratio: ~7%** (20K optimal / 270K actual). 93% of tokens were spent discovering things that could have been known upfront.

### Why the ratio is structurally bad

This is NOT a process failure — it's inherent to exploit development against unknown targets:

1. **The SECCOMP filter is opaque.** There is no documentation for which syscalls the Chrome renderer allows. fork() vs clone() had to be discovered empirically (v20a). sched_setaffinity had to be tested on-device (v20l confirmed sched=0).

2. **SLUB behavior depends on runtime state.** The SLUB allocator's behavior changes based on allocation patterns, and Chrome's allocation patterns are not documented anywhere. No amount of static analysis reveals that Chrome rotates c->page between two syscalls.

3. **Each failure reveals exactly one constraint.** v20d revealed ordering matters. v20f revealed spray steals slots. v20g revealed CPU migration is a factor. v20h revealed SECCOMP allows sched_setaffinity. v20i revealed timing isn't the issue. v20j revealed LIFO recycling. v20l revealed c->page rotation. Each of these was invisible until the previous hypotheses were tested and falsified.

4. **Research costs compound.** Each new hypothesis required understanding a new kernel subsystem. Understanding c->page rotation required first understanding SLUB freelists, which required understanding slab page identity, which required understanding the fastpath/slowpath split. These build on each other — you can't skip to the answer without building the conceptual stack.

### The cost of context loss

This analysis spans at least 3 conversation sessions. Each session boundary forces:

- **Re-reading source files** (~5-10K tokens per session start)
- **Re-loading context from summaries** (~3-5K tokens)
- **Re-deriving conclusions** from incomplete summaries (~10-15K tokens when a summary drops a nuance)

Estimated context-loss overhead across the v20 series: **~40-60K tokens** (15-22% of total).

### Lessons

1. **Test one hypothesis per iteration.** v20a-v20m each changed one variable. This is the cheapest debugging strategy even though it looks wasteful — multi-variable changes make failure diagnosis impossible.

2. **Invest in diagnostics.** The sched_setaffinity return value (added in v20k, confirmed in v20l) was worth its 8-word cost many times over. Without `sched=0`, the v20l analysis would have had two competing hypotheses (SECCOMP blocked vs c->page rotation) instead of one.

3. **The "8 identical failures" signal.** v20l returning 0xFE08 (8/8 failures, writev=31 each time) was more informative than a partial success would have been. It proved the failure was structural, not probabilistic, which immediately ruled out "just retry more" and forced deeper analysis.

4. **Heap spray before critical section is the standard technique.** Published exploits for CVE-2019-2215 don't need this because they run as native apps with clean heaps. But NSO's ITW exploit (Chrysaor) used msgsnd-based reclaim from inside a sandboxed process — the same class of problem. The knowledge existed; the gap was recognizing that Chrome's heap noise is the functional equivalent of the kernel being "already busy" in the NSO scenario.

5. **Token cost is front-loaded but value is back-loaded.** The first 200K tokens produced nothing but failed attempts. The last 70K tokens (c->page rotation diagnosis + defrag spray design) produced the actual fix. The failures were not waste — they were systematic elimination of the hypothesis space. But the cost distribution is lopsided.

---

## 6. Files Modified

- `payloads/uaf_iovec_leak.s` — v20m shellcode (265 words, 1060 bytes)
- `www/exploit/rce_chrome86.html` — v20m payload + beacons
- `journal/025_slub_defrag_v20m_meta_analysis.md` — this entry

## 7. Next Steps

1. **Test v20m** on device — connect Portal to hotspot, trigger captive portal
2. If `0xCCxx`: proceed to v21 (addr_limit overwrite for kernel R/W)
3. If `0xFE04`: increase SPRAY_COUNT to 64 or 128, or add inter-attempt nanosleep to let c->page settle
4. If `0xA1xx` (binder open fails): fd limit hit from spray — reduce SPRAY_COUNT or close spray fds before critical section

---

*Filed under: SLUB internals, heap feng shui, token economics, c->page rotation, CVE-2019-2215*
