# Journal 020: Captive Portal Browser Exploit Chain — Setup

**Date:** 2026-03-03
**Risk Level:** ZERO (infrastructure only, no device modification)
**Context:** CVE-2021-1931 DMA overflow exhausted (journal 018), fastboot 0-day not vulnerable,
UEFI stack overflows protected (journal 019). Captive portal browser chain is the highest
probability software-only path remaining.

---

## Objective

Set up a captive portal WiFi network on macOS to intercept the Portal's connectivity check
and serve a web page to its embedded WebView. Phase 1 goal: **verify the Chrome/WebView version**
on the actual device, which determines the exploit selection.

## Background

### ctrsec.io Proven Approach (2022)

Chi Tran demonstrated a working renderer RCE exploit against the Facebook Portal via captive
portal at firmware v1.29.1 (Chrome 92). The attack:
1. Create rogue WiFi AP with captive portal
2. Portal connects, Android opens CaptivePortalLogin WebView
3. Serve CVE-2021-30632 exploit page (V8 TurboFan type confusion)
4. Renderer code execution achieved

### Chrome Version — RESOLVED

The firmware dump from tadiphone.dev shows **Chrome 106.0.5249.126** in both chromium.apk
and portal-webview.apk (December 2024 build). However, that dump is NEWER firmware than what
is on our device.

**Actual Chrome version confirmed via captive portal User-Agent (2026-03-03):**

```
Chrome/86.0.4240.198 (V8 8.6)
```

Full User-Agent:
```
Mozilla/5.0 (Linux; Android 9; Portal+ Build/PKQ1.191202.001; wv)
AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/86.0.4240.198 Safari/537.36
```

This confirms Chrome 86 << Chrome 93 (CVE-2021-30632 patch). **The ctrsec.io exploit approach
is directly applicable** — same vulnerability class, same device family, older Chrome version.

### Exploit Selection — DECIDED

| Chrome Version | V8 Version | Primary CVE | Status | PoC Available |
|---------------|-----------|-------------|--------|--------------|
| **69-92** | **6.9-9.2** | **CVE-2021-30632** | **OUR TARGET — Chrome 86** | **Yes (GitHub SecurityLab)** |
| 93-106 | 9.3-10.6 | CVE-2023-3420 | Not needed | Yes (GitHub SecurityLab) |
| 93-106 | 9.3-10.6 | CVE-2022-3723 | Not needed | Yes (Numen Cyber Labs) |
| 107+ | 10.7+ | Various | Not needed | Partial |

### Kernel Exploit (Stage 2)

CVE-2019-2215 (Binder UAF) is confirmed viable regardless of Chrome version:
- Kernel 4.4.153 (fix not backported)
- CONFIG_DEBUG_LIST NOT enabled (confirmed via kallsyms)
- selinux_enforcing at 0xffffff800a925a94
- binder_thread_release at 0xffffff8008d3b15c

---

## Infrastructure Created

### Directory Structure
```
captive-portal/
├── server.py              # Python HTTP server (captive portal + logging)
├── dnsmasq.conf           # DNS wildcard resolution config
├── setup_hotspot.sh       # macOS hotspot + dnsmasq + pfctl setup
├── www/
│   ├── index.html         # Version detection landing page
│   └── exploit/           # Exploit payloads (Phase 2)
├── payloads/              # Stage 2 kernel exploit, post-exploit scripts
├── tools/                 # Offset extraction, cross-compilation
└── logs/                  # Request logs, device reports
```

### Components

1. **server.py** — Python HTTP server that:
   - Intercepts Android connectivity check URLs (/generate_204)
   - Returns 302 redirect to trigger captive portal detection
   - Serves landing page with JavaScript device fingerprinting
   - Logs all requests with full headers to JSON log files
   - Reports Chrome version, screen size, GPU, CPU cores, memory

2. **dnsmasq.conf** — DNS wildcard resolution:
   - Resolves ALL domains to Mac's bridge IP (192.168.2.1)
   - Ensures connectivitycheck.gstatic.com reaches our server

3. **setup_hotspot.sh** — Automated setup:
   - Checks prerequisites (dnsmasq, python3, bridge interface)
   - Starts dnsmasq with wildcard DNS
   - Configures pfctl for HTTP/HTTPS redirect
   - Starts the captive portal server
   - Cleanup with --stop flag

4. **www/index.html** — Device reconnaissance page:
   - Extracts Chrome version from User-Agent
   - Displays V8 version estimate
   - Reports WebGL renderer (GPU), CPU cores, memory
   - Tests WebAssembly, SharedArrayBuffer, JIT support
   - Color-coded version assessment (green=Chrome 92 CVE, yellow=Chrome 106 CVE)
   - POSTs full device report to server as JSON

### Dependencies Installed
- dnsmasq 2.92 (via Homebrew)

---

## Test Results — COMPLETED 2026-03-03

### WiFi Hotspot Configuration (actual setup used)
- **Source**: iPhone USB tethering (en8, 172.20.10.4)
- **Internet Sharing**: Share from iPhone USB → To: Wi-Fi
- **SSID**: PortalNet, Security: WPA2/WPA3 Personal
- **Bridge**: bridge101 (192.168.2.1, member: ap1)
- Note: WiFi-only Mac, no wired ethernet. bridge100 was VM (vmenet0), not WiFi AP.

### Steps Executed
1. Connected iPhone via USB → en8 interface active (172.20.10.4)
2. Internet Sharing: Share from iPhone USB → To: Wi-Fi (PortalNet, WPA2/WPA3)
3. `sudo ./setup_hotspot.sh` — started dnsmasq + pfctl + server on bridge101 (192.168.2.1)
4. Portal booted normally → connected to PortalNet in WiFi settings
5. Portal detected captive portal → opened WebView → loaded our index.html

### Results
- **Chrome version**: 86.0.4240.198 (V8 8.6)
- **Device identifier**: Portal+ (Build/PKQ1.191202.001)
- **Android**: 9 (Pie)
- **WebView context**: CaptivePortalLogin WebView (wv flag in UA)
- Portal also queries: `portal.fb.com/mobile/status.php`
- **Verdict**: CVE-2021-30632 IS APPLICABLE (Chrome 86 << 93 patch)

---

## Chrome Version Confirmed — Exploit Plan

**Chrome 86.0.4240.198 confirmed.** CVE-2021-30632 is the primary renderer exploit.

---

## Stage 1: CVE-2021-30632 — V8 TurboFan Type Confusion (Renderer RCE)

### Vulnerability Mechanism
V8 TurboFan JIT compiler confuses `PACKED_SMI_ELEMENTS` with `PACKED_DOUBLE_ELEMENTS` after
garbage collection. JIT-compiled code accesses array elements using the wrong size (4 bytes
for SMI vs 8 bytes for double), creating a **2x out-of-bounds read/write** on double arrays.

### Exploitation Flow (from GitHub SecurityLab PoC)
1. **Trigger type confusion**: Create map transitions that cause TurboFan to emit code
   assuming SMI elements while the array has been transitioned to DOUBLE elements
2. **OOB R/W**: Confused element access gives 2x out-of-bounds on a double array
3. **addrOf primitive**: Read compressed heap pointers of adjacent objects
4. **Arbitrary read**: Corrupt TypedArray backing_store pointer → read any address
5. **Leak WASM RWX page**: Read WASM instance object → extract RWX code pointer
6. **Write shellcode**: Redirect TypedArray backing_store to RWX page → write ARM64 shellcode
7. **Execute**: Call WASM function → jumps to our shellcode = renderer code execution

### Adaptations Required for Portal (Chrome 86 / V8 8.6 / ARM64 / Android 9)

| Item | PoC (x86-64 d8) | Portal Target |
|------|-----------------|---------------|
| Architecture | x86-64 | ARM64 (AArch64) |
| Shellcode | execve("/bin/sh") | fork() + exec(stage2_kernel) |
| V8 context | d8 shell | Android WebView |
| Pointer compression | V8 8.0+ (yes) | V8 8.6 (yes) |
| V8 sandbox | Not present | Not present (Chrome 86) |
| Exfiltration | console.log | fetch() to captive portal server |
| Object offsets | x86-64 heap layout | ARM64 heap layout (same compressed) |

### Key V8 8.6 Object Layout (Compressed Pointers)
- TypedArray backing_store: full 64-bit pointer (not compressed)
- WASM instance → RWX pointer at instanceAddr + 0x60 (approximate, needs calibration)
- OOB array element indices: x[20], x[24] (may need adjustment for V8 8.6)
- Compressed pointer base (isolate root): upper 32 bits of any heap pointer

### ARM64 Shellcode Requirements
```
1. fork() → child process (avoid crashing WebView)
2. In child: write stage2 ELF to /data/local/tmp/stage2
3. chmod +x /data/local/tmp/stage2
4. execve("/data/local/tmp/stage2", NULL, NULL)
5. Parent: return cleanly to JavaScript (WebView stays alive)
```

The stage2 ELF binary will be embedded in the exploit HTML as base64, decoded by JavaScript,
and written to a temp file via the shellcode.

### Files to Create
- `captive-portal/www/exploit/rce_chrome86.html` — Full exploit page
- `captive-portal/payloads/shellcode_arm64.S` — ARM64 shellcode source

---

## Stage 2: CVE-2019-2215 — Binder UAF (Kernel Privilege Escalation)

### Confirmed Kernel Configuration
- **Kernel**: 4.4.153 (fix NOT backported)
- **Security patch**: 2019-08-01 (Binder UAF disclosed 2019-10, fix not in Aug patch)
- **CONFIG_DEBUG_LIST**: NOT enabled (no list corruption checks — exploit-friendly)
- **KASLR**: ENABLED (CONFIG_RANDOMIZE_BASE=y) — **major complication**
- **KPTI**: enabled, **PAN**: software-emulated
- **Stack protector**: strong, **Hardened usercopy**: enabled
- **SECCOMP**: enabled (must disable in post-exploit)

### Extracted Kernel Offsets (pre-KASLR addresses)

```c
#define BINDER_THREAD_SZ        0x198   // 408 bytes, kmalloc-512 bucket
#define IOVEC_ARRAY_SZ          32      // 32 iovecs = 512 bytes = same slab
#define WAITQUEUE_OFFSET        0xA0    // wait_queue_head_t in binder_thread
#define OFFSET_ADDR_LIMIT       0x08    // thread_info.addr_limit in task_struct
#define OFFSET_REAL_CRED        0x7B0   // task->real_cred
#define OFFSET_CRED             0x7B8   // task->cred
#define OFFSET_SECCOMP_MODE     0x850   // task->seccomp.mode
#define OFFSET_SECCOMP_FILTER   0x858   // task->seccomp.filter
#define OFFSET_PID              0x5F8   // task->pid
#define SELINUX_ENFORCING       0xffffff800a925a94
#define COMMIT_CREDS            0xffffff80080cdddc
#define PREPARE_KERNEL_CRED     0xffffff80080ce2c4
#define KERNEL_BASE             0xffffff8008080000  // _text
```

### KASLR Strategy
KASLR randomizes the kernel base address at boot. Options to handle it:
1. **Leak via /proc/self/pagemap** — may work if read access not restricted
2. **Leak via timing side-channel** — unreliable on ARM64
3. **Leak from initial Binder UAF** — use first UAF to leak a kernel pointer from freed
   binder_thread, calculate KASLR slide, then use second UAF for actual exploit
4. **Brute-force** — kernel slide on ARM64 is limited range, but risky (kernel panics)

Preferred: Option 3 (double UAF — first for leak, second for exploit).

### Exploit Flow
1. Open `/dev/binder`, register with epoll
2. Create binder_thread, trigger `BINDER_THREAD_EXIT` → UAF
3. Reclaim freed memory with iovec array (same kmalloc-512 slab)
4. Use `writev()` on corrupted wait_queue → leak task_struct pointer
5. Calculate KASLR slide from leaked kernel pointer
6. Second UAF → overwrite `addr_limit` → kernel R/W primitive
7. Zero UID/GID in cred struct → root
8. Set capabilities to `0x3ffffffffful`
9. Write 0 to `selinux_enforcing` (adjusted for KASLR slide)
10. Clear SECCOMP flags
11. Execute post-exploitation

### Files to Create
- `captive-portal/payloads/portal_offsets.h` — Kernel offsets header
- `captive-portal/payloads/stage2_kernel.c` — Binder UAF exploit
- `captive-portal/tools/build_payload.sh` — Cross-compilation script

---

## Stage 3: Post-Exploitation

```bash
# Run as root after kernel exploit
setprop persist.sys.usb.config mtp,adb
setprop ro.debuggable 1
start adbd
setprop service.adb.tcp.port 5555
stop adbd && start adbd
# Disable dm-verity via vbmeta flags
# Remount system partition
mount -o remount,rw /system
# Persist root + create marker
echo "ROOT ACHIEVED" > /data/local/tmp/ROOTED
```

### File to Create
- `captive-portal/payloads/post_exploit.sh`

---

## Execution Priority (ordered)

| # | Task | Effort | Risk | Dependency |
|---|------|--------|------|------------|
| 1 | Adapt CVE-2021-30632 exploit for Chrome 86 ARM64 WebView | 2-4 hrs | ZERO | None |
| 2 | Write ARM64 shellcode (fork + exec stage2) | 1-2 hrs | ZERO | None |
| 3 | Build CVE-2019-2215 kernel exploit with Portal offsets | 2-4 hrs | ZERO | portal_offsets.h |
| 4 | Handle KASLR (double-UAF leak strategy) | 1-2 hrs | ZERO | #3 |
| 5 | Cross-compile stage2 for ARM64 | 30 min | ZERO | #3, #4 |
| 6 | Write post-exploitation script | 30 min | ZERO | None |
| 7 | Integrate full chain into exploit HTML | 1-2 hrs | ZERO | #1, #2, #5 |
| 8 | Test on device (connect Portal, trigger chain) | 30 min | MEDIUM | #7 |

**Total estimated effort: 8-15 hours**
**Critical path: #1 → #7 → #8**
