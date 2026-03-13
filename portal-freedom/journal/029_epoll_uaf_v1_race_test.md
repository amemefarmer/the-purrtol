# Journal 029: epoll_uaf v1 — CVE-2021-1048 Race Test Shellcode

**Date:** 2026-03-12
**Status:** DEPLOYED — awaiting device test
**Depends on:** Journal 028 (syscall_test 4/4 SUCCESS)

## Overview

Built and deployed the first version of the CVE-2021-1048 (epoll UAF) kernel exploit shellcode. This v1 is a **race test** — it exercises the full race condition and spray mechanism but does NOT yet implement kernel escalation. The goal is to verify that:

1. epoll-in-epoll topology can be created
2. The race loop (close + recreate vs epoll_ctl ADD/DEL) runs without crashing
3. sendmsg spray (128-byte msg_control) sends and recvmsg drains correctly
4. clone(CLONE_VM|CLONE_FILES) creates a racing child thread
5. The renderer process survives 200 race iterations

## Architecture

```
Phase 1: SETUP
  epfd_outer = epoll_create1()
  epfd_inner = epoll_create1()
  epoll_ctl(outer, ADD, inner)     ← epoll-in-epoll topology
  8x pipe() + epoll_ctl(inner, ADD, pipe[i])  ← widen race window
  socketpair(AF_UNIX) → sv[0], sv[1]  ← spray channel
  pipe() → rw[0], rw[1]           ← for future kernel R/W
  pipe() → trig[0], trig[1]       ← child's trigger fd
  sched_setaffinity(CPU 0)         ← pin parent

Phase 2: RACE (200 iterations)
  Parent loop:
    close(epfd_inner)              ← free epitems
    sendmsg(sv[0], 128B ctrl)     ← spray into freed slab
    epfd_inner = epoll_create1()   ← recreate
    epoll_ctl(outer, ADD, inner)   ← re-link topology
    recvmsg(sv[1], DONTWAIT)       ← drain spray socket
    yield()

  Child thread (CLONE_VM):
    sched_setaffinity(CPU 1)       ← pin to different CPU
    Loop:
      epoll_ctl(outer, ADD, trig)  ← triggers ep_loop_check_proc
      yield()
      epoll_ctl(outer, DEL, trig)
      check stop_flag

Phase 3: RESULTS
  getuid32() → store uid
  Return 0xCCxx status
```

## Memory Layout

```
wasm_mem offsets:
  +0x0000..0x040F: shellcode (1040 bytes, 260 words)
  +0x0800..0x0FFF: child thread stack (2KB)
  +0x1000..0x107F: spray control data buffer (128 bytes)
  +0x1080..0x10FF: recv control buffer (128 bytes)
  +0x1100..0x117F: scratch (iovec, dummy bytes)
  +0x1200..0x120B: child's epoll_event struct
  +0x1400..0x142F: results (read by JS decoder)
  +0x1500..0x150F: shared state (epfd_inner, epfd_outer, stop_flag, trig_pipe0)
  +0x1510..0x154F: pipe fd array (8 pipes × 8 bytes)
```

## Shared State (wasm_mem + 0x1500, via R11 + 0x100)

| Offset | Field | Description |
|--------|-------|-------------|
| +0x00 | epfd_inner | Updated by parent on recreate |
| +0x04 | epfd_outer | Set once in setup |
| +0x08 | stop_flag | Parent sets to 1 when done |
| +0x0C | trig_pipe0 | Trigger pipe read-end fd |

## Results (wasm_mem + 0x1400)

| Offset | Field | Description |
|--------|-------|-------------|
| +0x00 | phase | Phase reached (1-5) |
| +0x04 | epfd_outer | Outer epoll fd |
| +0x08 | epfd_inner | Last inner epoll fd |
| +0x0C | iterations | Race loop count |
| +0x10 | spray_sent | Successful sendmsg count |
| +0x14 | spray_recv | Successful recvmsg count |
| +0x18 | child_pid | Child thread PID |
| +0x1C | uid_after | UID after race (99000 = no change) |
| +0x20 | final_status | 0xCCxx status code |

## Return Codes

| Code | Meaning |
|------|---------|
| 0xCC00 | ROOT achieved (uid=0) |
| 0xCC01 | Race completed, no root (expected for v1) |
| 0xCC10 | Setup failed (epoll/socket/pipe error) |
| 0xCC20 | Clone failed |

## Key Design Decisions

1. **CLONE_VM|CLONE_FILES (0x511):** Child shares memory AND file descriptors with parent. Essential for the race — child needs to see parent's recreated epfd_inner via shared memory, and both threads need to operate on the same epoll fds.

2. **Child stack at wasm_mem+0x0FF0:** Stack grows down from 0x0FF0 into the 2KB region at +0x0800. This is within the RWX wasm memory.

3. **8 pipes added to epfd_inner:** More monitored fds = more epitems = longer list traversal in ep_loop_check_proc = wider race window.

4. **sched_setaffinity to different CPUs:** Parent on CPU 0, child on CPU 1. Ensures true parallel execution for the race.

5. **200 max iterations:** Conservative for v1 testing. Production will use 500-1000.

6. **Spray marker 0x41414141:** Easy to detect in memory dumps. Production v2 will use carefully crafted values targeting epitem fields.

7. **MSG_DONTWAIT on recvmsg:** Non-blocking drain prevents the parent from blocking if no spray data is queued.

## Race Mechanism (CVE-2021-1048)

The vulnerability: `ep_loop_check_proc` traverses epoll's `visited_list` using `list_for_each_entry()` (NOT the `_safe` variant). This function is called during `epoll_ctl(ADD)` to check for circular references.

When parent calls `close(epfd_inner)`:
- Kernel calls `ep_free()` which removes all epitems from the eventpoll
- The epitems are freed back to the SLUB allocator (epi_cache / kmalloc-128)

Simultaneously, child calls `epoll_ctl(epfd_outer, ADD, trig_pipe)`:
- Kernel calls `ep_loop_check_proc()` which traverses epfd_inner's epitem list
- If an epitem was just freed and reclaimed by our sendmsg spray, the kernel reads our controlled data as if it were an epitem struct → UAF

## What v1 Tests

- Does the epoll-in-epoll topology work? (epoll_create1 + epoll_ctl)
- Does clone with CLONE_VM work for racing threads?
- Does the close+recreate+re-add cycle survive 200 iterations?
- Does sendmsg spray 128-byte allocations successfully?
- Does recvmsg drain them?
- Does the process survive without crashing? (important — bad UAF can panic)

## Expected v1 Results

- `0xCC01` = race completed, no root → **SUCCESS** (v1 doesn't escalate)
- `phase=2` or `phase=3` = race phase reached
- `iters=200` = all iterations completed
- `sent>0` = spray messages sent
- `uid=99000` = unchanged (no escalation)
- Process alive (no crash) = race is safe to iterate

## Next Steps (v2)

After v1 confirms the race runs safely:
1. Increase iterations to 500-1000
2. Replace 0x41414141 marker with crafted fake epitem data
3. Place fake `struct eventpoll` in userspace (no HW PAN on SD835)
4. Use fake ep pointer to redirect kernel read to addr_limit
5. Implement pipe-based kread/kwrite after addr_limit clobber
6. Patch credentials (zero UIDs, full caps, SELinux SID=1)

## Files Modified

- `captive-portal/payloads/epoll_uaf.s` — NEW (260 words, 1040 bytes)
- `captive-portal/www/exploit/rce_chrome86.html` — MODIFIED (syscall_test → epoll_uaf_v1)
