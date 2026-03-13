# Journal 028: syscall_test 4/4 SUCCESS — All Kernel Exploit Primitives Confirmed

**Date:** 2026-03-12
**Status:** MILESTONE — All syscalls for CVE-2021-1048 available

## Results

4 runs, all returned `0xBB3F` (bitmap=0x3F = all 6 tests completed):

| Syscall | Result | Details |
|---------|--------|---------|
| socketpair(AF_UNIX,SOCK_STREAM) | OK | fds: 67/68, 69/70, 53/62, 50/62 |
| sendmsg(sv[0], 1-byte msg) | OK(1) | Sent 1 byte successfully |
| recvmsg(sv[1]) | OK(1, byte=0x54) | Received 'T' — data integrity verified |
| clone(SIGCHLD) | OK | PIDs: 5486, 5028, 5069, 4816 — all reaped by wait4 |
| sched_setaffinity(CPU 0) | OK(0) | Can pin threads to specific CPU |
| socket(AF_INET) | ERR(-1) | EPERM from SECCOMP — no network sockets |

## Implications for CVE-2021-1048

Every syscall needed for the kernel exploit is available:

1. **Race condition threads**: clone() works, sched_setaffinity() works
2. **Heap spray**: sendmsg() works on AF_UNIX socketpair
3. **Existing confirmed**: epoll_create1, epoll_ctl, close, pipe2, writev (from v20s)
4. **No network**: AF_INET blocked, so all shellcode must be in w[] array (64KB limit)

## Exploit Architecture (planned)

### Phase 1: Setup (~50 instructions)
- Create epoll-in-epoll topology (epfd_outer watches epfd_inner)
- Pre-create many fds (pipes) and add to epfd_inner (widen race window)
- Create socketpair for heap spray channel
- Allocate child thread stack in wasm_mem

### Phase 2: Race (~80 instructions)
- clone(CLONE_VM|CLONE_FILES|SIGCHLD) to create racing thread
- Thread A (child): loop calling epoll_ctl(epfd_outer, EPOLL_CTL_ADD, pipe_fd, ...)
- Thread B (parent): loop calling close(epfd_inner) then recreating
- Repeat until UAF fires (~100-1000 iterations)

### Phase 3: Detection + Spray (~60 instructions)
- After each close, spray sendmsg with 128-byte msg_control
- Check if sprayed data was read by ep_loop_check_proc
- Detection: read back from recvmsg on spray socket

### Phase 4: Escalation (~100 instructions)
- Use corrupted pointer to find task_struct via addr_limit technique
- Overwrite addr_limit to 0xFFFFFFFFFFFFFFFF
- Kernel R/W via pipe read/write
- Patch creds: zero UID/GID, full caps, SELinux SID

### Phase 5: Post-exploit (~50 instructions)
- Disable SELinux (selinux_enforcing = 0)
- Enable ADB (write to system properties)
- Report success to captive portal server

### Size estimate
~340 instructions = ~1360 bytes = ~340 words. Well within 64KB wasm_mem.

## Key Research Findings (from background agent)

- userfaultfd is ni_syscall — can't stabilize race
- msgsnd/msgrcv are ni_syscall — can't use message queues
- add_key at 0xffffff800832fa5c IS available (alternative spray)
- epi_cache may or may not merge with kmalloc-128 under SLUB
- No HW PAN on SD835 (ARMv8.0) — can place fake structures in userspace
- addr_limit at thread_info+0x08 is the proven escalation target
- Race reliability: ~1-5% per attempt, 100-1000x for near-certain success
- Failed races are generally clean (no kernel panic)
