# Journal 019: CVE Research — Alternative Attack Paths for Portal Gen 1

**Date:** 2026-03-02
**Risk Level:** ZERO (research only, no device interaction)
**Context:** CVE-2021-1931 DMA overflow fully exhausted (journal 018). Researching alternative
vulnerabilities for APQ8098/SD835 at 2019-08-01 security patch level.

---

## Objective

With the DMA overflow proven unable to unlock the device (lock state unreachable, 12KB hard
ceiling, all 7 strategies exhausted), systematically research other CVEs that could provide
an alternative path to bootloader unlock or code execution on the Facebook Portal Gen 1.

---

## Tier 1: HIGH Priority — Testable with Current Setup

### 1. 2026 Qualcomm Fastboot 0-Day (getvar overflow + oem ramdump stack overflow)

**Source:** Security researcher disclosure, early 2026
**Bug:** Two related vulnerabilities in Qualcomm's ABL fastboot implementation:
- `getvar` command hangs/crashes when input exceeds ~502 bytes (stack buffer overflow)
- `oem ramdump` has a stack-based buffer overflow with large arguments

**Relevance:** DIRECT — our Portal runs Qualcomm ABL in fastboot mode right now.

**Test plan (LOW risk — read-only probing, worst case = device hang requiring power cycle):**
```bash
# Test 1: getvar with 502+ byte input
fastboot getvar $(python3 -c "print('A'*502)")
fastboot getvar $(python3 -c "print('A'*600)")
fastboot getvar $(python3 -c "print('A'*1024)")

# Test 2: oem ramdump with large input
fastboot oem ramdump $(python3 -c "print('A'*256)")
fastboot oem ramdump $(python3 -c "print('A'*1024)")
fastboot oem ramdump $(python3 -c "print('A'*8000)")
```

**Expected results:**
- If vulnerable: device hangs, crashes, or returns garbled response (confirms stack overflow)
- If patched: "unknown command" or clean error response
- If not applicable: "unknown variable" / "unknown command" (command not present)

**Exploit potential:** If confirmed, a stack buffer overflow in ABL fastboot is MUCH more
powerful than the DMA heap overflow — stack overflows can directly hijack return addresses
for immediate code execution. Could redirect execution to shellcode or known ABL functions.

**Probability:** ~15-30% (depends on whether Facebook's ABL fork includes the vulnerable code)

**TESTED 2026-03-03 — NOT VULNERABLE:**
```
getvar A*502  → "GetVar Variable Not found" (clean, 2ms)
getvar A*600  → "GetVar Variable Not found" (clean, 2ms)
getvar A*1024 → "GetVar Variable Not found" (clean, 2ms)
getvar A*2048 → "GetVar Variable Not found" (clean, 2ms)
getvar A*3000 → "GetVar Variable Not found" (clean, 2ms)
getvar A*3800 → "GetVar Variable Not found" (clean, 2ms)
getvar A*4096 → CLIENT-SIDE rejection ("Command length too long")
oem ramdump   → "unknown command"
oem ramdump A*256  → "unknown command"
oem ramdump A*1024 → "unknown command"
oem A*2048    → "unknown command"
```
Device handled ALL sizes up to client-side max with clean responses. No hang, no crash,
no garbled output. Facebook's ABL fork is NOT vulnerable to the getvar/ramdump overflow.
The ABL likely uses a large or dynamic buffer for command parsing.

---

### 2. CVE-2022-40516 / CVE-2022-40517 / CVE-2022-40520 — UEFI Core Stack Overflows

**Source:** Binarly Research (2022-2023), affects Qualcomm reference UEFI implementation
**Bug:** Stack-based buffer overflows in UEFI DXE drivers:
- CVE-2022-40516: Stack overflow in DXE driver handling variable-length data
- CVE-2022-40517: Stack overflow in UEFI runtime services
- CVE-2022-40520: Stack overflow in UEFI variable handling

**Relevance:** HIGH — LinuxLoader.efi (ABL) IS a UEFI DXE application built on Qualcomm's
reference UEFI code. We have LinuxLoader-terry.efi fully decompiled in Ghidra.

**Test plan (ZERO risk — offline Ghidra analysis):**
1. Search LinuxLoader decompilation for Binarly's identified vulnerable function patterns
2. Look for variable-length stack buffers in UEFI variable handling code
3. Check if the DXE driver entry points match known vulnerable signatures
4. If vulnerable functions found: craft inputs through fastboot to trigger them

**Probability:** ~20-30% (Qualcomm UEFI code is shared across platforms; Portal's 2019
build likely predates patches)

**ANALYZED 2026-03-03 — NOT EXPLOITABLE via fastboot:**

Ghidra decompilation of LinuxLoader.efi reveals THREE layers of protection:

1. **CommandDispatcher (0x10078) truncates ALL commands to 64 bytes** (line 224-227):
   ```c
   if (0x3f < param_1) { param_1 = 0x40; }
   param_2[param_1] = '\0';
   ```
   This means partition names in `flash:` are limited to ~58 chars max.

2. **FlashHandler (0x12010) bounds-checks partition name** (line 455):
   ```c
   uVar12 = FUN_0003bff4(param_1);  // AsciiStrLen
   if (0x47 < uVar12) goto LAB_000120a8;  // if len > 71, skip
   FUN_0003c830(param_1, auStack_188);  // safe: 72 wide chars = 144 bytes
   ```

3. **Stack canary present** (line 439): `local_68 = DAT_00095418`

The vulnerable PATTERN exists (wide-char copy into stack buffer) but is properly bounded.
CVE-2022-40516/17/20 target UEFI *variable services* (GetVariable/SetVariable) called
through Boot Services Table, not the fastboot command interface. No direct trigger path
available from fastboot.

**Confirmed by device testing:** getvar with 57, 58, 502, 1024, 2048, 3800 bytes — all
return clean "GetVar Variable Not found" (2ms). No hang, crash, or garbled output.

---

### 3. CVE-2021-30327 — Sahara Protocol Buffer Overflow (PBL-level)

**Source:** Qualcomm security bulletin, 2021
**Bug:** Buffer overflow in Sahara protocol handler in Primary Boot Loader (PBL)
**Affected:** APQ8098 **CONFIRMED** in advisory
**Severity:** Critical — PBL is burned into ROM, CANNOT be patched by OTA updates

**Relevance:** DIRECT — we can enter EDL/Sahara mode on the Portal (Mute + Power + USB).
The Sahara protocol is what bkerler/edl uses to communicate before firehose loading.

**Current state:** No public exploit exists. The vulnerability is in the PBL's Sahara
command handler — a malformed Sahara packet could overflow a buffer and achieve code
execution at PBL privilege level (highest possible — above TrustZone).

**Test plan (MEDIUM risk — could hang device in EDL, recoverable with power cycle):**
1. Study bkerler/edl Sahara protocol implementation
2. Identify which Sahara commands handle variable-length data
3. Craft oversized Sahara packets and observe device response
4. Monitor for crashes, hangs, or unexpected responses

**Probability:** ~10-15% (PBL exploit development is extremely difficult even with confirmed
vuln — no symbols, no debugging, minimal attack surface)

**Upside:** If successful, PBL code execution = game over. Full device control, can load
arbitrary firehose, dump/write any partition, unlock bootloader permanently.

---

## Tier 2: MEDIUM Priority — Requires Additional Setup

### 4. Captive Portal Browser Chain (ctrsec.io proven approach)

**Source:** ctrsec.io "Pwning the Facebook Portal" (2022)
**Bug chain:**
- Step 1: CVE-2021-30632 — Chrome V8 OOB write (type confusion in TurboFan JIT)
- Step 2: CVE-2019-2215 — Binder UAF kernel exploit for sandbox escape
- Combined: renderer code execution → kernel privilege escalation → root shell

**Relevance:** PROVEN on Facebook Portal. ctrsec.io demonstrated this exact chain:
1. Portal's setup wizard connects to WiFi
2. Captive portal detection opens embedded Chrome/WebView browser
3. Serve exploit page via fake captive portal
4. Achieve renderer code execution via V8 bug
5. Escape sandbox via kernel Binder UAF
6. Root shell → disable dm-verity → enable ADB → flash custom boot

**Portal specifics:**
- Portal runs Chrome 92 (vulnerable to CVE-2021-30632, patched in Chrome 93)
- Android 9 kernel is vulnerable to CVE-2019-2215 (patched in Oct 2019, Portal at Aug 2019)
- Both CVEs have public exploit code

**Requirements:**
- WiFi access point (laptop/phone hotspot)
- DNS/HTTP server for captive portal
- Compiled exploit payloads for ARM64 Android 9
- Network setup to intercept Portal's connectivity check

**Test plan:**
1. Set up WiFi AP with captive portal redirect
2. Connect Portal to AP during setup wizard
3. Verify Chrome version exposed via User-Agent
4. Serve CVE-2021-30632 exploit page
5. If renderer exec achieved, deploy CVE-2019-2215 kernel exploit
6. Root shell → enable ADB, disable verity, flash modified boot

**Probability:** ~40-60% (both exploits proven on similar hardware; main risk is
stability/reliability of exploit chain on specific Portal firmware)

**Complexity:** HIGH — requires setting up WiFi AP, captive portal, compiling two separate
exploits, and chaining them reliably.

---

### 5. QualPwn (CVE-2019-10538 / CVE-2019-10539 / CVE-2019-10540)

**Source:** Tencent Blade Team, BlackHat 2019
**Bug:** WiFi firmware remote code execution chain:
- CVE-2019-10539: Heap overflow in WiFi firmware (WLAN host)
- CVE-2019-10540: Buffer overflow in WLAN firmware
- CVE-2019-10538: WiFi → Application Processor escalation

**Affected:** Snapdragon 835 (SD835/APQ8098) **explicitly listed**
**Patch:** August 2019 security bulletin — Portal's patch level is EXACTLY 2019-08-01

**Relevance:** The Portal's security patch is dated exactly when this was patched.
Depending on whether the August patch was applied BEFORE or AFTER the QualPwn fix
was merged, the device may or may not be vulnerable.

**Requirements:** WiFi proximity, custom WiFi frames, complex exploit development
**Probability:** ~15-25% (exploit exists but adapting to Portal firmware is non-trivial)
**Complexity:** VERY HIGH — WiFi firmware exploitation requires specialized tooling

---

## Tier 3: LOWER Priority — Hardware or Long-Term

### 6. RPMB Physical Attacks (CVE-2024-31955 and related research)

**Source:** Multiple academic papers, CVE-2024-31955 (EMFI bypass)
**Bug:** RPMB (Replay Protected Memory Block) stores the lock state. Physical attacks:
- CVE-2024-31955: Electromagnetic fault injection bypasses RPMB authentication
- Key extraction: side-channel attacks on RPMB authentication key
- Direct UFS: read/modify devinfo partition directly via UFS test pads

**Relevance:** Lock state is ultimately stored in RPMB on the UFS chip. If RPMB
authentication can be bypassed, the lock state can be directly modified.

**Requirements:** UFS programmer ($200-500), FPGA for glitching ($50-150), PCB probing
**Probability:** ~50-70% (well-understood attack surface, requires hardware investment)

### 7. ChoiceJacking / AOAP USB Injection

**Source:** 2025 research on Android USB trust model
**Bug:** USB input injection through Android Open Accessory Protocol (AOAP)
**Relevance:** LOW for our use case — Portal has no touch screen unlock, and the
USB attack surface in fastboot mode is already fully explored via CVE-2021-1931.

---

## Prioritized Action Plan

### Immediate (can test NOW, zero additional setup):

| # | Action | Risk | Time | Probability |
|---|--------|------|------|-------------|
| 1 | Test getvar 502+ byte overflow | LOW | 10 min | 15-30% |
| 2 | Test `oem ramdump` with large args | LOW | 10 min | 10-20% |
| 3 | Search LinuxLoader.efi in Ghidra for CVE-2022-40516/17/20 patterns | ZERO | 2-4 hrs | 20-30% |

### Short-term (days, software setup):

| # | Action | Risk | Time | Probability |
|---|--------|------|------|-------------|
| 4 | Set up captive portal WiFi AP + Chrome exploit | MEDIUM | 1-2 days | 40-60% |
| 5 | Study Sahara protocol for CVE-2021-30327 fuzzing | MEDIUM | 2-3 days | 10-15% |
| 6 | Research QualPwn WiFi exploit adaptation | LOW | 1-2 days | 15-25% |

### Medium-term (weeks, hardware investment):

| # | Action | Risk | Time | Probability |
|---|--------|------|------|-------------|
| 7 | UFS direct access via test pads | HIGH | 1-2 weeks | 60-70% |
| 8 | Voltage glitching during boot | HIGH | 1-2 weeks | 30-40% |
| 9 | RPMB key extraction / EMFI | HIGH | 2-4 weeks | 40-50% |

---

## Recommended Next Steps

**Right now (this session):**
1. Power cycle Portal into fastboot → test getvar overflow (10 minutes)
2. Test oem ramdump if recognized (10 minutes)
3. Begin Ghidra search for UEFI stack overflow patterns

**This week:**
4. Set up captive portal browser chain (HIGHEST probability software-only path at 40-60%)
5. Research Sahara protocol internals for CVE-2021-30327

**Key insight:** The captive portal browser chain (item 4) is the most promising
software-only path. It's the ONLY approach proven to work on a Facebook Portal by
independent researchers. The main barrier is complexity of setup, not feasibility.

---

## References

- ctrsec.io: "Pwning the Facebook Portal" (2022) — proven captive portal exploit chain
- Binarly: "Qualcomm UEFI Vulnerabilities" (2022-2023) — CVE-2022-40516/17/20
- Qualcomm Security Bulletin: CVE-2021-30327 (Sahara PBL overflow, APQ8098 confirmed)
- Tencent Blade: QualPwn BlackHat 2019 — CVE-2019-10538/39/40
- Google Project Zero: CVE-2019-2215 (Binder UAF, exploited ITW)
- 2026 Qualcomm fastboot 0-day disclosure (getvar/ramdump stack overflows)
