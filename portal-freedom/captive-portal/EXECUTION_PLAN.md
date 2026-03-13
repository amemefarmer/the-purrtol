# Captive Portal Exploit Chain — Execution Plan

**Date:** 2026-03-03
**Status:** Phase 1 COMPLETE (infrastructure + Chrome version confirmed)
**Target:** Chrome 86.0.4240.198, V8 8.6, Android 9, kernel 4.4.153, ARM64

---

## Summary

Three-stage exploit chain to root the Facebook Portal 10" Gen 1:

```
Stage 1: CVE-2021-30632 (Chrome V8 type confusion → renderer RCE)
    ↓ shellcode drops Stage 2 ELF binary
Stage 2: CVE-2019-2215 (Binder UAF → kernel privilege escalation → root)
    ↓ root shell executes post-exploit
Stage 3: Post-exploitation (enable ADB, disable dm-verity, persist root)
```

**Probability of success:** 50-70%
- Stage 1 (renderer RCE): ~80% — proven PoC, known-vulnerable Chrome version
- Stage 2 (kernel root): ~65% — proven CVE, but KASLR + reliability concerns
- Stage 3 (post-exploit): ~95% — standard Android root persistence

---

## Completed Work

| Item | Status | Location |
|------|--------|----------|
| Captive portal HTTP server | DONE | `captive-portal/server.py` |
| DNS wildcard resolution | DONE | `captive-portal/dnsmasq.conf` |
| macOS hotspot setup script | DONE | `captive-portal/setup_hotspot.sh` |
| Version detection landing page | DONE | `captive-portal/www/index.html` |
| Chrome version confirmed (86) | DONE | journal 020, MEMORY.md |
| Kernel offsets extracted | DONE | `captive-portal/payloads/portal_offsets.h` |
| CVE-2021-30632 PoC analyzed | DONE | GitHub SecurityLab source reviewed |
| CVE-2019-2215 approach mapped | DONE | journal 020, MEMORY.md |

---

## Priority 1: Chrome Renderer RCE (CVE-2021-30632)

**Goal:** Execute arbitrary ARM64 code in the Portal's WebView renderer process.

### Task 1.1: Adapt V8 Exploit for Chrome 86 / V8 8.6
- **Input:** GitHub SecurityLab CVE-2021-30632 PoC (JavaScript)
- **Work:**
  - Port type confusion trigger to V8 8.6 (verify GC timing, map transitions)
  - Calibrate object layout offsets for V8 8.6 compressed pointers:
    - OOB array element indices (x[20], x[24] in PoC — verify for 8.6)
    - TypedArray backing_store offset
    - WASM instance → RWX code pointer (instanceAddr + 0x60, verify)
  - Replace `console.log` debug output with `fetch()` to captive portal server
  - Add error handling / retry logic for reliability
  - Test with a Chrome 86 debug build if possible (or calibrate live on device)
- **Output:** `captive-portal/www/exploit/rce_chrome86.html`
- **Effort:** 2-4 hours
- **Risk:** ZERO (JavaScript development, no device interaction)

### Task 1.2: Write ARM64 Shellcode
- **Input:** x86-64 shellcode from PoC (execve /bin/sh)
- **Work:**
  - Write AArch64 assembly for:
    1. `fork()` system call (SVC #0, x8=220 on ARM64)
    2. Parent: return 0 to JavaScript (WebView stays alive)
    3. Child: write stage2 ELF to `/data/local/tmp/stage2`
    4. Child: `chmod` +x
    5. Child: `execve("/data/local/tmp/stage2", NULL, NULL)`
  - Stage2 binary will be passed to shellcode as a memory pointer
  - Encode as JavaScript Uint8Array for the exploit page
- **Output:** `captive-portal/payloads/shellcode_arm64.S` + encoded bytes
- **Effort:** 1-2 hours
- **Risk:** ZERO (assembly development)
- **Note:** Can run in parallel with Task 1.1

---

## Priority 2: Kernel Privilege Escalation (CVE-2019-2215)

**Goal:** Escalate from renderer process (uid=app) to root (uid=0), disable SELinux.

### Task 2.1: Write Kernel Exploit
- **Input:** `portal_offsets.h`, cve-2019-2215 reference implementations
- **Work:**
  - Implement double-UAF KASLR bypass:
    1. First UAF: trigger binder_thread free, reclaim with iovec, leak kernel ptr
    2. Calculate KASLR slide from leaked pointer
    3. Adjust all kernel symbol addresses
  - Implement privilege escalation:
    4. Second UAF: overwrite `addr_limit` → kernel R/W primitive
    5. Read our task_struct → get cred pointer
    6. Zero uid/gid fields in cred → root
    7. Set capabilities to FULL_CAPABILITIES
    8. Write 0 to selinux_enforcing (+ KASLR slide)
    9. Clear seccomp mode and filter
  - Add reliability measures:
    - Retry logic for UAF race conditions
    - Verify exploit success before proceeding
    - Clean exit on failure (avoid kernel panic)
- **Output:** `captive-portal/payloads/stage2_kernel.c`
- **Effort:** 2-4 hours
- **Risk:** ZERO (C development, no device interaction)
- **Dependencies:** portal_offsets.h (DONE)

### Task 2.2: Handle KASLR
- **Input:** Kernel config analysis (KASLR confirmed enabled)
- **Work:**
  - Implement `/proc/self/pagemap` leak (check kptr_restrict first)
  - If pagemap restricted: use double-UAF leak strategy (leak from freed binder_thread)
  - Validate leaked address looks like a kernel pointer (0xffffff80XXXXXXXX range)
  - Calculate slide: `slide = leaked_addr - expected_pre_kaslr_addr`
  - Verify slide is 2MB-aligned (ARM64 KASLR alignment)
- **Output:** Integrated into stage2_kernel.c
- **Effort:** 1-2 hours (included in Task 2.1)

### Task 2.3: Cross-Compile for ARM64
- **Input:** stage2_kernel.c + portal_offsets.h
- **Work:**
  - Install cross-compiler: `brew install aarch64-elf-gcc` or use Docker
  - Static compile: `aarch64-linux-gnu-gcc -static -O2 -o stage2 stage2_kernel.c`
  - Verify: `file stage2` → ELF 64-bit LSB executable, ARM aarch64
  - Strip symbols for size: `aarch64-linux-gnu-strip stage2`
  - Target size: <100KB static binary
- **Output:** `captive-portal/payloads/stage2` (ARM64 ELF)
- **Effort:** 30 minutes
- **Risk:** ZERO (compilation)
- **Dependencies:** Task 2.1

---

## Priority 3: Post-Exploitation

### Task 3.1: Write Post-Exploit Script
- **Input:** Post-root requirements (ADB, dm-verity, persistence)
- **Work:**
  - Enable ADB: `setprop persist.sys.usb.config mtp,adb && start adbd`
  - ADB over WiFi: `setprop service.adb.tcp.port 5555`
  - Disable dm-verity: write disabled flags to vbmeta_a and vbmeta_b
  - Remount /system read-write
  - Create root marker: `/data/local/tmp/ROOTED`
  - Signal success to captive portal server via HTTP POST
- **Output:** `captive-portal/payloads/post_exploit.sh`
- **Effort:** 30 minutes
- **Risk:** ZERO (script writing)

---

## Priority 4: Integration & Testing

### Task 4.1: Integrate Full Chain
- **Input:** All outputs from Priorities 1-3
- **Work:**
  - Embed stage2 ARM64 ELF as base64 in exploit HTML
  - Exploit page flow:
    1. Load → trigger V8 type confusion
    2. Build primitives (OOB → addrOf → arbitrary R/W)
    3. Leak WASM RWX page
    4. Write ARM64 shellcode to RWX page
    5. Shellcode: fork, decode stage2 from base64, write to /data/local/tmp, exec
    6. Stage2: kernel exploit → root → run post_exploit.sh
    7. POST success/failure report to captive portal server
  - Update `server.py` to serve exploit page (add `--exploit` mode routing)
  - Add progress indicators / status updates via fetch() to server
- **Output:** Complete exploit chain in `captive-portal/www/exploit/rce_chrome86.html`
- **Effort:** 1-2 hours
- **Dependencies:** ALL of Priority 1, 2, 3

### Task 4.2: Test on Device
- **Input:** Integrated exploit chain, WiFi hotspot running
- **Work:**
  1. Start captive portal: `sudo ./setup_hotspot.sh`
  2. Boot Portal normally
  3. Connect Portal to PortalNet WiFi
  4. Portal opens captive portal WebView → exploit page loads
  5. Monitor server console for:
     - Stage 1 status (V8 exploit progress)
     - Stage 2 status (kernel exploit progress)
     - Root confirmation
  6. After root: `adb connect <portal_ip>:5555`
  7. Verify: `adb shell id` → uid=0(root)
- **Effort:** 30 minutes per attempt
- **Risk:** MEDIUM — kernel exploit could cause kernel panic (device recovers on power cycle)
- **Dependencies:** Task 4.1

---

## Risk Matrix

| Stage | Failure Mode | Impact | Recovery |
|-------|-------------|--------|----------|
| V8 type confusion trigger | GC timing wrong | WebView crash | Portal reboots, retry |
| V8 offset calibration | Wrong object layout | Silent failure or crash | Adjust offsets, retry |
| ARM64 shellcode | Bad syscall numbers | Renderer crash | Fix shellcode, retry |
| Binder UAF (first) | Race condition loss | No kernel leak | Retry (increase attempts) |
| KASLR bypass | Wrong slide calc | Kernel panic | Power cycle, fix calculation |
| Binder UAF (second) | Slab mismatch | Kernel panic | Power cycle, fix sizes |
| addr_limit overwrite | Wrong offset | Kernel panic | Power cycle, verify offsets |
| SELinux disable | Wrong address | No effect or panic | Verify selinux_enforcing addr |
| Post-exploitation | Permission denied | Partial root | Debug SELinux context |

**Worst case:** Kernel panic → hard reboot (hold power 10s). No persistent damage.
Device boots to normal state. Retry with fixes.

---

## Dependencies to Install

```bash
# Already installed
brew install dnsmasq        # DNS wildcard resolution

# Needed for Priority 2.3
brew install aarch64-elf-gcc  # ARM64 cross-compiler
# OR
brew install --cask docker    # Docker with ARM64 toolchain
```

---

## File Manifest (to create)

| File | Priority | Purpose |
|------|----------|---------|
| `www/exploit/rce_chrome86.html` | P1 | Chrome 86 V8 RCE exploit page |
| `payloads/shellcode_arm64.S` | P1 | ARM64 fork+exec shellcode source |
| `payloads/stage2_kernel.c` | P2 | Binder UAF kernel exploit source |
| `payloads/portal_offsets.h` | P2 | **CREATED** — Kernel struct offsets |
| `payloads/stage2` | P2 | Compiled ARM64 kernel exploit ELF |
| `payloads/post_exploit.sh` | P3 | Post-root ADB + persistence script |
| `tools/build_payload.sh` | P2 | Cross-compilation script |
