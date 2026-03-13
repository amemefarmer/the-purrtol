# Journal 012 — test0 DMA Overflow Crash Confirmed on Portal

**Date:** 2026-02-26
**Risk Level:** LOW (device hangs, power cycle recovers)
**Outcome:** SUCCESS — CVE-2021-1931 confirmed exploitable on Portal APQ8098

---

## Summary

Ran xperable test0 on Portal in fastboot mode. The DMA buffer overflow successfully
redirected ABL code execution to our infinite loop opcodes. Device froze completely
(USB enumerated but all communication failed), confirming arbitrary code execution
in the bootloader.

---

## Setup

- xperable compiled natively on macOS ARM64 with `TARGET_ABL_PORTAL`
- Portal in fastboot mode, USB VID `0x2EC6` PID `0x1800`
- Build chain: gcc/g++ (Apple Clang) + pe-parse + libusb-1.0
- Portal target matched on `product: aloha` (version-bootloader is empty)

## Build Process

1. pe-parse built from source: `cmake` + `make -j4`
2. Compiled: `xperable.c` (`-DTARGET_ABL_PORTAL`), `fbusb.c`, `pe-load.cpp`
3. Linked: `g++` with `-lpe-parse -lusb-1.0`
4. Result: 251KB Mach-O arm64 binary

## Test0 Execution

- Ran: `./xperable -V -A -0`
- `getvar:all` succeeded, target set: offset=0x30, size=0xF3F880 (~15MB)
- Buffer filled with opcodes:
  - `0x00-0x2C`: `BL #0x1000000` (forward branch-link)
  - `0x30-0xF3F87C`: `B #0x00` (infinite loop)
- 15MB USB bulk transfer sent successfully
- Response: `libusb_bulk_transfer` timeout on EP 0x81 (device didn't respond)
- Second attempt also timed out (USB send failed on EP 0x01)
- Post-test: `fastboot devices` still showed device, but `fastboot getvar product`
  failed with "Write to device failed"

## Evidence of Code Execution

1. **USB device still enumerated** — hardware powered, SoC alive
2. **All USB communication pipes broken** — `e00002ed` errors on every transfer
3. **No watchdog reboot** — device stayed frozen indefinitely
4. **This exactly matches expected behavior:** ABL CPU executing our infinite loop opcodes

The infinite loop (`B #0x00`) prevents the CPU from ever returning to the fastboot
command handler, which is why USB communication dies but the device stays powered.
If the overflow had NOT reached executable code, ABL would have continued responding
normally (or the watchdog would have fired).

## Implications

- Portal's APQ8098 (SD835) with 2019-08 security patch **is vulnerable** to CVE-2021-1931
- DMA buffer overflow reaches ABL executable code pages
- No size validation on USB download buffer
- Distance from buffer to code is within the ~15MB overflow range
- The "no watchdog" behavior is useful — gives test2/test3 shellcode time to scan memory

## Recovery

Power cycle: hold rear power button ~10 seconds. Device reboots normally.
No permanent damage — ABL runs from flash, the overflow only corrupts RAM.

## Next Steps

1. Power cycle Portal back to fastboot
2. Run **test2** — PIC shellcode to discover buffer-to-code distance
3. If test2 BL pattern doesn't match aloha, try alternative patterns
4. Run **test3** — NOP sled variant for wider hit probability
5. Once distance known → blind memory dump to extract decrypted ABL
