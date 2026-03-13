# Journal 024: UAF + Iovec Reclaim Info Leak (v20)

**Date:** 2026-03-06 → 2026-03-07
**Status:** In progress — v20k (reordered alloc→free window)

## Objective

Combine CVE-2019-2215 (Binder UAF) with writev iovec reclaim to leak a kernel heap address from the sandboxed Chrome renderer on Facebook Portal Gen 1.

## Architecture

### CVE-2019-2215 Recap

The Binder driver allocates `binder_thread` (408 bytes) from `kmalloc-512` when a thread first interacts with a binder fd. `BINDER_THREAD_EXIT` frees the thread via `kfree()`, but epoll still holds a reference to the thread's `wait_queue_head` at offset `WAITQUEUE_OFFSET = 0xA0`.

When `close(epoll_fd)` triggers `ep_free()`:
1. `ep_remove()` → `ep_unregister_pollwait()` → `remove_wait_queue()`
2. `spin_lock_irqsave(&q->lock)` on the freed memory's spinlock at +0xA0
3. `list_del(&entry->task_list)` writes kernel pointers at offsets +0xA8 and +0xB0
4. `spin_unlock_irqrestore()`

### The Spinlock Problem

The `wait_queue_head` layout at `WAITQUEUE_OFFSET` in the freed `binder_thread`:

```
+0xA0: spinlock_t lock     (4 bytes, ARM64 ticket spinlock)
+0xA4: padding             (4 bytes)
+0xA8: list_head.next      (8 bytes, 64-bit pointer)
+0xB0: list_head.prev      (8 bytes, 64-bit pointer)
```

Native `struct iovec` on AArch64 is 16 bytes (`iov_base: u64`, `iov_len: u64`).
With 32 compat iovecs, the kernel allocates 32 × 16 = 512 bytes from `kmalloc-512`.

**Critical overlap:** `iov[10]` starts at offset 10×16 = 0xA0:
- `iov[10].iov_base` (8 bytes) at offset 0xA0 — **overlaps spinlock!**
- `iov[10].iov_len` (8 bytes) at offset 0xA8 — overlaps `list.next`

The spinlock (low 4 bytes of `iov_base`) will be non-zero (valid userspace address),
making the ticket spinlock appear **locked** → `spin_lock` deadlocks → kernel hang.

**This means iovec reclaim and kzalloc spray are fundamentally incompatible for this
WAITQUEUE_OFFSET.** The kzalloc spray zeros the spinlock, but then the iovec isn't in
the slot. The iovec reclaim fills the slot, but makes the spinlock non-zero.

### v20 Design: Clone + Pipe Blocking

**Approach:** Fork a child process via `clone(SIGCHLD, 0)` to hold a blocking `writev`
while the parent triggers the UAF.

1. **Setup:** Open binder, create epoll watching binder_fd (registers wait_queue on binder_thread)
2. **Pipe:** Create pipe, fill to 64KB capacity
3. **Iovecs:** Set up 32 compat iovecs at WASM memory +0x1000
4. **Clone:** `clone(SIGCHLD, 0, 0, 0)` — child shares COW address space, own fd table
5. **Child:** `writev(pipe_wr, iovecs, 32)` — **blocks** because pipe is full.
   Kernel allocates native iovec array from `kmalloc-512` via `compat_import_iovec()`.
6. **Parent:** Sleep 100ms, then `BINDER_THREAD_EXIT` (free binder_thread)
7. **Parent:** Spray 4× `open(/dev/binder) + ioctl` → `kzalloc(408)` zeros freed slot
8. **Parent:** Sleep 10ms, then `close(epoll_fd)` — UAF trigger via refcount
9. **Parent:** Close `pipe_wr` (critical!), sleep 50ms, drain pipe
10. **Child:** Eventually unblocks when pipe space appears, writes data, `_exit(0)`

### File Descriptor Reference Counting (Key Insight)

After `clone(SIGCHLD, 0)` **without** `CLONE_FILES`:
- Child gets **its own fd table** (copy of parent's)
- Both parent and child fds point to the **same `struct file`** (refcount = 2)

```
                Parent FDs              Child FDs
                ─────────               ─────────
binder_fd ──┐                   ┌── binder_fd
             └──→ struct file ←─┘   (f_count = 2)
epoll_fd  ──┐                   ┌── epoll_fd
             └──→ struct file ←─┘   (f_count = 2)
pipe_rd   ──┐                   ┌── pipe_rd
             └──→ struct file ←─┘   (f_count = 2)
pipe_wr   ──┐                   ┌── pipe_wr
             └──→ struct file ←─┘   (f_count = 2)
```

**Parent's `close(epoll_fd)`:** f_count 2→1. `ep_free()` is **NOT called** (f_count > 0).
**No UAF trigger from parent's close!**

The actual UAF trigger happens when the **child exits** (`_exit(0)` closes all fds).
Child's `close(epoll_fd)`: f_count 1→0 → `ep_free()` → `remove_wait_queue()` → `list_del`.

### The Pipe Drain Hang (v20a Bug)

**Bug:** Parent's drain loop calls `read(pipe_rd)` in a loop. When the pipe is empty
but `pipe_wr` is still open by the parent, `read()` **blocks forever** waiting for data.
The parent holds `pipe_wr` → pipe always has a writer → `read()` never returns EOF.

**Fix (v20b):** Parent closes `pipe_wr` **before** draining:
1. Parent `close(pipe_wr)`: f_count 2→1 (child still has it)
2. Parent drains pipe (reads fill data + child's writev data)
3. Child's writev completes, child `_exit(0)` closes its `pipe_wr` (f_count 1→0)
4. Pipe now has no writers → parent's `read()` returns 0 (EOF)
5. Drain loop exits

### Syscall Decisions

| Syscall | Number | Status | Notes |
|---------|--------|--------|-------|
| `fork` (\_\_NR_fork=2) | 2 | **BLOCKED by SECCOMP** | v20a failed with 0xB1xx |
| `clone` (\_\_NR_clone=120) | 120 | **ALLOWED** | Confirmed in v16 (0xCC00) |
| `write` (\_\_NR_write=4) | 4 | Assumed allowed | Used for pipe fill |
| `read` (\_\_NR_read=3) | 3 | Assumed allowed | Used for pipe drain |
| `_exit` (\_\_NR_exit=1) | 1 | Assumed allowed | Child cleanup |

### UAF Corruption Analysis

When `list_del` runs on the freed+sprayed slot:

```
Before list_del (kzalloc-sprayed, all zeros):
  +0xA0: 00000000 (spinlock = unlocked ✓)
  +0xA8: 00000000 00000000 (list.next = 0)
  +0xB0: 00000000 00000000 (list.prev = 0)

Epoll's eppoll_entry still has stale pointers:
  entry->task_list.prev = slot+0xA8
  entry->task_list.next = slot+0xA8

list_del(&entry->task_list):
  __list_del(prev=slot+0xA8, next=slot+0xA8):
    next->prev = prev  →  *(slot+0xB0) = slot+0xA8
    prev->next = next  →  *(slot+0xA8) = slot+0xA8

After list_del:
  +0xA8: <slot+0xA8> (self-pointer = kernel heap address!)
  +0xB0: <slot+0xA8> (same self-pointer)
```

This writes a **kernel heap address** into the freed slot at offsets +0xA8 and +0xB0.
However, in v20's current design, the **child's iovec is NOT in this slot** (allocated
before BINDER_THREAD_EXIT), so the corruption only affects the spray binder_thread.

### WASM Memory Overflow (v20c Bug)

WASM linear memory is **1 page = 64KB = 0x10000 bytes**. The v20b/c drain loop accumulated
all pipe data at `wasm_mem+0x2000`:

```
drain_loop:
    read(pipe_rd, wasm_mem+0x2000+total_read, 4096)
    total_read += bytes_read
```

After draining 65568 bytes of pipe data, the write pointer reaches:
`wasm_mem + 0x2000 + 0x10020 = wasm_mem + 0x12020`

This is **0x2020 bytes past the end of WASM memory** (which ends at `wasm_mem + 0x10000`).
Writing past WASM memory corrupts the V8 heap → renderer crash → Portal reboot.

The data scan was even worse: it read from `wasm_mem + 0x2000 + 0x10000 = wasm_mem + 0x12000`.

**Fix (v20d):** Drain reads into a **fixed 4KB buffer** at `wasm_mem+0x0800` (reusing
the fill buffer). Each read() overwrites the same 4KB. Only `total_read` is accumulated
as a counter. The LAST read() leaves the child's 32 bytes of marker data in the buffer,
which d0-d3 can read from `wasm_mem+0x0800`.

### Expected v20b Result

Since the child's writev iovec is NOT in the freed binder_thread slot (it was allocated
before the free), the child's writev will complete normally with 32 bytes written.
Expected result: `0xFE00` (no extra bytes = no leak detected).

This confirms the timing/drain fix works. The next step is to restructure the exploit
so the iovec DOES reclaim the freed slot (allocate AFTER BINDER_THREAD_EXIT).

### WASM Memory Layout

```
+0x0000: Shellcode (238 words = 952 bytes)
+0x0800: Pipe fill buffer (64KB, zeros)
+0x1000: Compat iovec array (32 × 8 = 256 bytes)
+0x1100: Iovec data buffers (32 bytes, markers 'A'-'`')
+0x1200: (unused)
+0x1400: Results area
  +0x1400: total_read (uint32)
  +0x1404: expected_read (uint32, = 65568)
  +0x1408: extra_bytes (int32, = total - expected)
  +0x140C: d0-d3 (4 × uint32, first 16 bytes of child's data region)
  +0x1420: child_writev_ret (int32, from child via WASM memory)
+0x2000: Pipe drain buffer (~128KB max)
```

## Files Modified

- `payloads/uaf_iovec_leak.s` — v20 shellcode (238 words, 952 bytes)
- `www/exploit/rce_chrome86.html` — v20 exploit page with updated payload + decoding

## Test Results

| Version | Result | Hex | Issue | Fix Applied |
|---------|--------|-----|-------|-------------|
| v20a (fork) | FAIL | `0xB1xx` | `__NR_fork` blocked by SECCOMP | → clone() |
| v20b (clone, no pipe_wr close) | HANG | — | Parent's drain `read()` blocks forever (pipe_wr still open) | → close pipe_wr before drain |
| v20c (clone + close pipe_wr) | CRASH | — | WASM memory overflow: drain buffer at +0x2000 accumulated ~65KB past 64KB boundary | → fixed-size drain buffer |
| v20d (fixed drain, old ordering) | OK | `0xFE00` | Drain works, writev=31 (no corruption). Child writev before BINDER_THREAD_EXIT → wrong slot | → restructure ordering in v20e |
| v20e (correct ordering, CLONE_FILES) | OK | `0xCC1F` | Buffer overlap! child's 4KB drain buf (0x0800-0x17FF) overwrote results at 0x1400 with zeros. writev_ret read as 0 | → separate buffers in v20f |
| v20f (separate child buffer at +0xD000) | OK | `0xFE00` | writev=31, no corruption. Spray (4× kzalloc) stole freed slot before writev's kmalloc | → remove spray in v20g |
| v20g (no spray) | OK | `0xFE00` | writev=31, STILL no corruption. CPU migration: free on CPU X, kmalloc on CPU Y → different SLUB freelist | → CPU pinning in v20h |
| v20h (sched_setaffinity CPU 0) | OK | `0xFE00` | writev=31, CPU pinning didn't help. sched_setaffinity likely SECCOMP-blocked + slab page mismatch is the real root cause | → tight timing in v20i |
| v20i (tight free→alloc, 5 instr gap) | OK | `0xFE00` | writev=31, tight timing didn't help either. Root cause is NOT timing — it's SLUB slab page identity | → heap warmup spray in v20j |
| v20j (SLUB heap warmup spray) | OK | `0xFE00` | writev=31, spray was a NO-OP: SLUB LIFO recycles same slot on every kmalloc+kfree cycle, c->page never changes | → reorder alloc→free gap in v20k |
| v20k (reordered alloc→free, 3 syscalls) | **PENDING** | — | Move epoll/pipe/fill BEFORE binder open. Alloc→free gap: 3 syscalls (was 37+). Also stores sched_setaffinity result. Assembled with clang --target=armv7 (240 words, 960 bytes) | — |

## Detailed Fix History

### v20d → v20e: Ordering + FD Refcount (2 bugs)

**Bug 1: Wrong ordering.** In v20d, child's writev ran BEFORE BINDER_THREAD_EXIT. The child's
kmalloc(512) got a random kmalloc-512 slot, then BINDER_THREAD_EXIT freed the binder_thread
to a DIFFERENT slot. Result: writev iovec not in the freed slot.

**Bug 2: FD refcount.** `clone(SIGCHLD)` without `CLONE_FILES` gives the child its OWN fd table
(copy of parent's fds, but independent). Both parent and child fds point to the same `struct file`
with refcount=2. Parent's `close(epoll_fd)` decrements refcount to 1 — `ep_free()` never fires!
The UAF only triggers when the child exits and closes ITS copy of epoll_fd.

**Fix (v20e):** Complete architectural redesign:
1. BINDER_THREAD_EXIT + spray run BEFORE clone
2. `clone(CLONE_VM|CLONE_FILES|SIGCHLD = 0x511)` creates a TRUE THREAD:
   - CLONE_VM: shared address space (child can access wasm_mem)
   - CLONE_FILES: shared fd table (close(epoll) in child triggers ep_free immediately)
3. PARENT calls writev → kmalloc(512) should RECLAIM freed slot → blocks (pipe full)
4. CHILD sleeps 100ms → close(epoll_fd) → UAF! → drains pipe → parent unblocks

### v20e → v20f: Buffer Overlap

**Bug:** Child's pipe drain buffer started at wasm_mem+0x0800 and was 4KB (0x0800-0x17FF).
The results area is at +0x1400. Child's drain loop wrote zeros (from pipe filler data) over
the writev_ret stored at +0x1400 → writev_ret read as 0 → reported as 0xCC1F (deficit=31).

**Diagnosis:** Result 0xCC1F means writev_ret=0. But writev can't return 0 (it either returns
bytes written or -1 on error). The 0 was pipe fill data (zeros) overwriting the results area.

**Fix (v20f):** Parent buffer shrunk to 2KB (0x0800-0x0FFF). Child gets SEPARATE drain buffer
at +0xD000 (2KB, 0xD000-0xD7FF). Added `const_cbuf = 0xD000` to data pool for child's LDR.

### v20f → v20g: Spray Stealing Freed Slot

**Bug:** The 4× kzalloc(408) spray was designed to zero the spinlock at +0xA0. But spray
allocations from `kmalloc-512` consumed the freed binder_thread slot BEFORE writev's
kmalloc(512) could claim it. SLUB LIFO: first kzalloc gets the most recently freed slot.
writev's kmalloc got a different kmalloc-512 entry → no corruption (0xFE00, writev=31).

**Key insight:** The spray is unnecessary! Setting iov[10]={base=0, len=0} makes native
iov[10].iov_base = 8 zero bytes at offset +0xA0, which perfectly zeros the spinlock.
No separate zeroing needed.

**Fix (v20g):** Removed spray loop entirely. BINDER_THREAD_EXIT directly followed by
iovec setup + clone. writev's kmalloc(512) should be the FIRST allocation after the free,
getting the slot via SLUB LIFO.

### v20g → v20h: CPU Migration (SLUB Per-CPU Freelists)

**Bug:** SLUB allocator maintains PER-CPU freelists. SD835 has 8 cores. Between
BINDER_THREAD_EXIT (frees on CPU X) and writev's kmalloc (runs on CPU Y), the
scheduler can migrate the thread to a different CPU. Different CPU = different freelist
= writev gets a slot from a different page, not the freed binder_thread.

**Key insight:** This is exactly the problem the ORIGINAL CVE-2019-2215 exploit solves
with `sched_setaffinity()`. All public exploits for this CVE pin to a single CPU first.

**Fix (v20h):** Added `sched_setaffinity(0, 4, &mask=1)` as the FIRST operation (A0),
pinning the process to CPU 0. All subsequent syscalls (BINDER_THREAD_EXIT, writev)
run on the same CPU → same SLUB freelist → LIFO guarantees reclamation.

Syscall 241 (__NR_sched_setaffinity) may be blocked by SECCOMP. If so, we ignore the error
and the exploit may still work probabilistically (~1/8 chance of same CPU).

### v20h → v20i: Tight Free→Alloc Timing

**Bug:** Even with CPU pinning (if it worked), there were ~50 ARM instructions between
BINDER_THREAD_EXIT (free) and writev (alloc). This included iovec setup, marker fill,
and clone() — all running between the two syscalls. This window gave interrupts, softirqs,
and other kernel threads time to do kmalloc-512 operations and steal the freed slot.

**Fix (v20i):** Reorder so BINDER_THREAD_EXIT is immediately followed by writev — only
5 ARM instructions (mov, add, mov, mov, svc) between the two SVC calls. Move iovec setup,
marker fill, and clone() to BEFORE BINDER_THREAD_EXIT.

**Result:** Still 0xFE00. Tight timing didn't help because the root cause was NOT the
timing window — it was slab page mismatch (see SLUB aside below).

### v20i → v20j: SLUB Heap Warmup Spray

**Root cause identified:** Across all v20 iterations, the freed `binder_thread` was on a
different slab page than `c->page` (the per-CPU active page). `kfree` took the SLUB slowpath,
adding the object to the slab's own partial freelist instead of `c->freelist`. Subsequent
`kmalloc(512)` calls got objects from `c->freelist` (fastpath, different page).

This explains why neither CPU pinning (v20h) nor tight timing (v20i) helped — the issue is
slab page identity, not CPU affinity or timing.

**Fix (v20j):** Add a "slab warming" spray BEFORE opening `/dev/binder`:
1. Set up iov array first (pure memory writes)
2. Open `/dev/null` for write
3. 32× `writev(devnull_fd, iov, 32)` — each cycles `kmalloc(512)` + `kfree(512)`
4. Close `/dev/null`
5. NOW open `/dev/binder` — `binder_thread` allocated from warmed `c->page`

After spray, `c->page` for `kmalloc-512` is established and active. The `binder_thread`
allocates from this page. When freed by `BINDER_THREAD_EXIT`, it goes to `c->freelist`
(fastpath LIFO, same page). writev's `kmalloc(512)` gets it immediately.

This is the standard "heap feng shui" technique used in real-world SLUB exploits.
See detailed SLUB analysis in the aside section below.

### v20j → v20k: Reordered Alloc→Free Window

**v20j result:** `0xFE00` — the 32× writev-to-/dev/null spray was a **NO-OP**.

**Root cause:** SLUB LIFO recycles the same slot on every kmalloc+kfree cycle. Each
`writev(devnull, iov, 32)` does `kmalloc(512)` → `vfs_writev` → `kfree(512)`. SLUB pushes
the freed object to `c->freelist` head, then the next kmalloc pops the same object from the
head. After 32 iterations, the heap topology is identical to before the spray. `c->page`
never changes because the freelist was never exhausted.

**Additional confirmed finding:** `binder_get_thread → kzalloc(0x198)` verified from kernel
binary disassembly at `0xffffff8008d37ea8`. BINDER_THREAD_SZ = 0x198 (408 bytes) is correct.
Uses `kmem_cache_alloc_trace(kmalloc-512_cache, GFP_KERNEL|__GFP_ZERO, 0x198)`.

**New insight:** The real problem may be CPU migration during the 37+ syscall gap between
binder_thread allocation (first ioctl) and free (BINDER_THREAD_EXIT). The gap included
`epoll_create1`, `pipe2`, 32× `write` (fill pipe), and `clone` — plenty of time for the
scheduler to migrate the process to a different CPU.

**Fix (v20k):** Reorder operations to minimize the alloc→free gap:
1. Move `epoll_create1`, `pipe2`, and fill pipe BEFORE opening `/dev/binder`
2. Open binder → first ioctl (allocates binder_thread) → epoll_ctl → clone → BINDER_THREAD_EXIT
3. The alloc→free gap is now only **3 syscalls** (was 37+), a 12× reduction
4. Remove the writev-to-/dev/null spray (proven no-op)
5. Store `sched_setaffinity` return value at +0x1408 for diagnostic (verifies if CPU pinning works)

Assembly: `clang --target=armv7-none-eabi` (first time using real cross-assembler instead of
hand-encoding). 240 words (960 bytes), down from 262 words (1048 bytes) in v20j.

## SLUB Freelist Architecture (Key Learning)

```
CPU 0 freelist:  [slot_A] → [slot_B] → [slot_C] → ...
CPU 1 freelist:  [slot_X] → [slot_Y] → [slot_Z] → ...
CPU 2 freelist:  [slot_P] → [slot_Q] → ...
...

kfree(ptr) on CPU 0: pushes ptr to HEAD of CPU 0's freelist
kmalloc(512) on CPU 0: pops HEAD of CPU 0's freelist → gets ptr back (LIFO!)
kmalloc(512) on CPU 1: pops HEAD of CPU 1's freelist → gets slot_X (WRONG!)
```

Without CPU pinning: free on CPU 0, thread migrates to CPU 3, kmalloc on CPU 3
→ gets a completely different slot from CPU 3's freelist.

With CPU pinning: free on CPU 0, stays on CPU 0, kmalloc on CPU 0
→ gets the exact same slot back (LIFO guarantee).

## Current WASM Memory Layout (v20k)

```
+0x0000: Shellcode (240 words = 960 bytes)
+0x0800: Parent pipe fill/drain buffer (2KB, 0x0800-0x0FFF)
+0x1000: 32 compat iovecs (32 × 8 = 256 bytes, 0x1000-0x10FF)
+0x1100: Iovec data buffers (32 bytes, markers 'A'-'`')
+0x1400: Results area (0x1400-0x141F)
  +0x1400: writev_ret (int32)
  +0x1404: total_read (uint32, parent's drain count)
  +0x1408: sched_setaffinity return (0=OK, -errno=SECCOMP blocked)
  +0x140C: (reserved)
  +0x1410: d0-d3 (4 × uint32, diagnostic from last read buffer)
+0xD000: Child drain buffer (2KB, 0xD000-0xD7FF)
+0xE000: Child thread stack (4KB, grows down from +0xF000)
```

## Expected v20k Result

If reordered alloc→free window keeps process on same CPU:
- writev's kmalloc(512) reclaims the freed binder_thread slot
- close(epoll_fd) triggers list_del → writes slot+0xA8 at offsets +0xA8 and +0xB0
- writev processes iov[10]: base=NULL (now slot+0xA8 in high 4 bytes), len=slot+0xA8 (huge)
- copy_from_user(dest, NULL, huge) faults → writev returns 10
- Result: **0xCC15** (31-10=21, UAF CONFIRMED)

## Next Steps After UAF Confirmation

1. **v21: addr_limit overwrite** — Second UAF cycle to get kernel R/W:
   - Use the leaked heap address (slot+0xA8) to calculate task_struct location
   - Set iov[X] to point at `thread_info.addr_limit` (offset 0x08 in thread_info)
   - writev writes controlled data over addr_limit → set to 0xFFFFFFFFFFFFFFFF
   - With addr_limit = -1, kernel ignores user/kernel boundary checks
   - Arbitrary kernel R/W via read()/write() on a pipe

2. **v22: Root escalation** — Using kernel R/W:
   - Zero UID/GID in `cred` struct (offsets 0x7B0/0x7B8 from task_struct)
   - Set capabilities to 0x3FFFFFFFFFUL
   - Zero `selinux_enforcing` at 0xffffff800a925a94 + KASLR slide
   - Clear SECCOMP mode and filter

3. **Post-exploitation** — Enable ADB, disable dm-verity, persist root

---

## Aside: SLUB Internals and Real-World Exploitation Challenges

### Why v20d–v20i All Failed (The Slab Page Identity Problem)

Every version from v20d through v20i returned `0xFE00` — writev returned 31 bytes (all iovecs processed normally, no corruption). The exploit's `kmalloc(512)` from writev was consistently getting a **different** kmalloc-512 slot than the freed `binder_thread`. Here's why.

### SLUB Allocation Internals

SLUB (the default Linux slab allocator since 2.6.22) maintains a **per-CPU structure** (`struct kmem_cache_cpu`) for each slab cache (e.g., `kmalloc-512`):

```
struct kmem_cache_cpu {
    void **freelist;      // Head of the per-CPU freelist (LIFO linked list)
    struct page *page;    // The "active" slab page (c->page)
    unsigned long tid;    // Transaction ID (for cmpxchg)
};
```

#### kfree() Path

```
kfree(ptr):
  1. Determine which slab page the object belongs to (via virt_to_head_page)
  2. Get the per-CPU kmem_cache_cpu for this cache on the CURRENT CPU

  FASTPATH (object's page == c->page):
    3a. Push object onto c->freelist (LIFO, lock-free cmpxchg)
    → Object is immediately available for the next kmalloc on THIS CPU

  SLOWPATH (object's page != c->page):
    3b. Add object to the slab page's own freelist
    3c. If the page was full, move it to the per-CPU partial list
    → Object is NOT on c->freelist! Only accessible after c->page is exhausted
```

#### kmalloc() Path

```
kmalloc(512):
  1. Get per-CPU kmem_cache_cpu for kmalloc-512

  FASTPATH (c->freelist != NULL):
    2a. Pop from c->freelist (LIFO, lock-free cmpxchg)
    → Gets the most recently freed object on THIS CPU

  SLOWPATH (c->freelist == NULL):
    2b. Check c->page for remaining objects
    2c. If c->page exhausted, get a new page from partial list (get_partial)
    2d. If no partials, allocate a new slab page from page allocator
```

### The Root Cause: Slab Page Mismatch

When we open `/dev/binder`, `binder_get_thread()` calls `kzalloc(sizeof(binder_thread))` → `kmalloc(408)` → `kmalloc-512`. This allocation comes from whatever slab page is `c->page` at that time. Call it **Page A**.

Between this allocation and `BINDER_THREAD_EXIT`, many other kernel operations occur:
- `epoll_create1`, `epoll_ctl`, `pipe2`, 32 `write()` calls for pipe fill, `clone()`
- Any of these may do `kmalloc-512` operations internally
- These operations may exhaust `c->freelist` and cause `c->page` to change

By the time `BINDER_THREAD_EXIT` calls `kfree(binder_thread)`:
- `c->page` may have changed to **Page B** (a different slab page)
- The `binder_thread` is on **Page A**, which is no longer `c->page`
- `kfree` takes the **slowpath**: adds the object to Page A's own freelist
- The object does NOT go to `c->freelist`

Then writev's `kmalloc(512)`:
- Takes the **fastpath**: pops from `c->freelist` on the current CPU
- Gets an object from **Page B** (or wherever `c->freelist` points)
- The freed `binder_thread` on **Page A** is never touched

**This is why tight timing (v20i) didn't help.** The issue isn't the time window between free and alloc — it's that the freed object is on the wrong slab page. Even if `kfree` and `kmalloc` happen on consecutive instructions on the same CPU, if the object's page != `c->page`, the free goes to the slowpath and the alloc gets a fastpath object.

**This is also why CPU pinning (v20h) didn't help.** Even on the same CPU, the slab page mismatch causes the slowpath. CPU pinning solves a different problem (ensuring free and alloc use the same `kmem_cache_cpu`), but doesn't solve the slab page identity issue.

### The Fix: Slab Warming (Heap Feng Shui)

The standard technique in real-world SLUB exploits is **slab warming** (also called **heap feng shui** or **heap grooming**):

1. **Before** allocating the target object (binder_thread), perform many allocations from the same slab cache (`kmalloc-512`) to establish a predictable `c->page`
2. The target object then allocates from this established `c->page`
3. When freed, the object goes to `c->freelist` (fastpath, same page)
4. The next allocation (writev's `kmalloc(512)`) gets it immediately (LIFO)

In v20j, we use `writev` to `/dev/null` as the spray primitive:

```
open("/dev/null", O_RDWR)
for (i = 0; i < 32; i++):
    writev(devnull_fd, iov, 32)
    // Each call: kmalloc(512) → process iovecs → kfree(512)
    // Cycles the per-CPU freelist, establishes c->page
close(devnull_fd)

// NOW open /dev/binder → binder_thread allocated from warmed c->page
binder_fd = open("/dev/binder", O_RDWR)
```

Why `/dev/null`?
- `writev` to `/dev/null` returns immediately (no blocking)
- No pipe needed, no data to drain
- Each call does exactly one `kmalloc(512)` + `kfree(512)` internally
- Clean, fast, no side effects
- Safe even under SECCOMP (writev + open are always allowed)

### Real-World Considerations

**Why 32 iterations?** Each kmalloc-512 slab page holds 4096/512 = 8 objects. With 32 iterations, we cycle through ~4 pages worth of allocations. This ensures `c->page` is well-established and the freelist is populated with recently-freed objects from the active page. The binder_thread allocation will land on this page.

**CONFIG_SLAB_FREELIST_RANDOM** (introduced in 4.7, NOT present in 4.4.153): Randomizes the initial freelist order within a slab page. Would reduce LIFO predictability but doesn't affect which page `c->freelist` draws from.

**CONFIG_SLAB_FREELIST_HARDENED** (introduced in 4.14, NOT present in 4.4.153): XORs freelist pointers with a random canary. Would make direct freelist manipulation detectable but doesn't affect our approach (we don't corrupt the freelist, we just allocate/free normally).

**SLUB debugging** (CONFIG_SLUB_DEBUG): If enabled, adds red zones, poisoning, and tracking that would detect our UAF. On production kernels (like Portal's), this is disabled for performance. Our kernel confirms: no `slub_debug` in cmdline.

**Interrupt-driven allocations**: Between our kfree and kmalloc, hardware interrupts could fire and do their own kmalloc-512 operations, stealing our freed slot. The sched_setaffinity (if it works past SECCOMP) + tight timing help here. But the main mitigation is statistical: interrupt-driven kmalloc-512 allocations are rare relative to the microseconds between our syscalls.

### Comparison with Published CVE-2019-2215 Exploits

| Technique | kangtastic (native app) | Our approach (Chrome renderer shellcode) |
|-----------|------------------------|------------------------------------------|
| CPU pinning | `sched_setaffinity(0, {0x1})` | Same (may be SECCOMP-blocked) |
| Heap warmup | Not needed (native app controls allocation order) | **Critical** — 32× writev-to-/dev/null |
| Reclaim primitive | `writev` with 32 iovecs (kmalloc-512) | Same |
| Blocking mechanism | Pipe pre-fill → writev blocks → child corrupts + drains | Same |
| Corruption trigger | `close(epoll_fd)` from child with CLONE_FILES | Same |
| Detection | writev returns < expected bytes | Same (31 expected, 10 = UAF confirmed) |

The key difference is that native app exploits typically run early in the process lifecycle with a clean heap. Our shellcode runs inside Chrome's renderer, which has already done thousands of kmalloc-512 operations. The heap is "noisy" — the slab pages and freelists are unpredictable. **Heap warming is essential** in this context to establish a known-good slab state before the critical free→reclaim sequence.

### SLUB Diagnostic: How to Verify Reclaim

If v20j still returns 0xFE00, diagnostic options:
1. **Check if `/dev/null` open fails** — would return 0xA1xx (open error)
2. **Add a spray count report** — encode iteration count in unused result bits
3. **Try larger spray** — increase from 32 to 128 iterations
4. **Alternative spray** — use `add_key` or `sendmsg` instead of writev (different allocation path)
5. **Verify binder_thread size** — if it's NOT in kmalloc-512, no amount of spraying helps. Would need to check kernel binary for exact `sizeof(binder_thread)` in the kzalloc call
