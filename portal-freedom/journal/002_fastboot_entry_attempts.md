# Experiment 002: Fastboot Mode Entry Attempts

**Date:** 2026-02-24
**Duration:** ~30 minutes
**Risk Level:** ZERO (only button presses and USB monitoring)
**Outcome:** UNSUCCESSFUL — fastboot mode not reached with methods tried

---

## Objective

Enter fastboot mode on Portal Gen 1 to enumerate bootloader variables and OEM commands.

## Methods Tried

### Method 1: Vol Down + Rear Power + USB-C
- Held Vol Down (top edge) and rear power button simultaneously
- USB-C data cable connected to Mac
- **Result:** Device entered EDL mode (QUSB_BULK), not fastboot
- This is the known EDL entry method

### Method 2: Vol Down + Plug Wall Power (XDA-documented method)
- Unplugged all power, waited for full power-down
- Connected USB-C data cable to Mac
- Held Vol Down (top edge)
- Plugged in wall power while holding Vol Down
- Held for 15-20 seconds
- **Result:** Device booted normally into Portal UI
- USB monitor (200ms polling, 120+ seconds) detected zero USB changes
- No fastboot device appeared

### Method 3: Variation of Method 2 (second attempt)
- Same as Method 2 with emphasis on fully dead device first
- **Result:** Same — normal boot, no fastboot detected

## Analysis

### Why Fastboot Wasn't Reached

Possible explanations:
1. **Wrong button timing:** The Vol Down may need to be pressed at a very specific point during the boot sequence
2. **Need both USB + wall power:** Some XDA reports suggest the USB-C data cable AND wall power need specific sequencing
3. **Firmware version matters:** Our device may have a different bootloader revision that handles button combos differently
4. **Facebook may have disabled the fastboot shortcut:** Although XDA reports it works, our specific unit may behave differently

### XDA Community Findings (for reference)

According to XDA research:
- **Portal+ Gen 1:** Hold Vol Down + Power while plugging in power → shows "Please Reboot..." with black box
- **Portal TV:** Unplug power, hold side button, re-insert power → "resetting" message → fastboot
- **Portal 10" Gen 1:** Vol Down during power-up should work, but exact sequence may vary

### What the Screen Showed

Both attempts: Normal Portal boot animation → Portal UI
No "Please Reboot..." message or fastboot screen was ever displayed.

## What's Known About Portal Fastboot (from research)

If/when fastboot is accessible:
- Bootloader is **locked** (`Device unlocked: false`)
- Uses **challenge-response unlock**: `fastboot oem get_unlock_bootloader_nonce` generates a nonce
- Nonce must be signed by Meta's internal tool (not publicly available)
- Standard `fastboot oem unlock` returns "unknown command"
- Recovery mode: Hold both Vol buttons during power-up → factory reset countdown → hold Vol Up for recovery

## POST-HOC FINDING: Wrong Button All Along!

**Date added:** 2026-02-24 (after firmware analysis — see journal/003)

Analysis of the device tree source (`boot/dts/06_dtbdump_Facebook,_Inc._-_Aloha_PVT1.0.dts`) revealed that the Portal 10" (Aloha) has only **two GPIO keys**:

| Button | Label | Key Code |
|--------|-------|----------|
| Top button | `volume_up` | KEY_VOLUMEUP (115) |
| Second button | `volume_mute` | KEY_MUTE (113) |

**There is NO volume_down key defined in the hardware.** The button we thought was "Vol Down" is actually the **mute/privacy** button. This means:

1. All XDA instructions saying "hold Vol Down" are either wrong for Portal 10", or refer to a different Portal model
2. Our failed attempts were using the mute button, not a volume down button
3. The correct fastboot entry might require **Vol Up** (the actual volume button) or the **mute** button with different naming

## Revised Attempts (2026-02-24, after button discovery)

| Method | Buttons | Result |
|--------|---------|--------|
| D | Vol Up + plug wall power | Normal boot |
| E | Mute + plug wall power | Normal boot |
| F | Both (Vol Up + Mute) + plug wall power | Normal boot |

## ROOT CAUSE: PMIC RESIN Line Not Connected to Any Button

**Date added:** 2026-02-24 (after Qualcomm ABL source code research)

Deep analysis of the device tree and Qualcomm ABL source code reveals WHY fastboot is unreachable via buttons:

### PMIC PON (Power-On) Configuration

```
qcom,power-on@800 {
    qcom,pon_1 {  /* KPDPWR = Power button */
        qcom,pon-type = <0x00>;
        linux,code = <0x74>;  /* 116 = KEY_POWER */
    };
    qcom,pon_2 {  /* RESIN = "Volume Down" equivalent */
        qcom,pon-type = <0x01>;
        linux,code = <0x72>;  /* 114 = KEY_VOLUMEDOWN */
    };
};
```

The PMIC has a **RESIN** (reset input) line that maps to KEY_VOLUMEDOWN (code 114). In the standard Qualcomm ABL (LinuxLoader.efi), RESIN produces `SCAN_DOWN`, which triggers fastboot. **However, on the Portal 10", no physical button is wired to the RESIN line.**

### Why No Button Combo Works

| Input | Physical Button | ABL Sees | Triggers |
|-------|----------------|----------|----------|
| PMIC PON KPDPWR | Rear Power | SCAN_POWER | Power on |
| PMIC GPIO 6 | Vol Up (top) | SCAN_UP | Recovery (standard) |
| PMIC GPIO 5 | Mute (top) | *Nothing* | Not recognized by ABL |
| **PMIC PON RESIN** | **None** | **SCAN_DOWN** | **Fastboot** |

The fastboot trigger (SCAN_DOWN via RESIN) has **no physical button**. The ABL's `GetKeyPress()` function only checks for `SCAN_DOWN`, `SCAN_UP`, and `SCAN_ESC`. The Mute button on GPIO 5 produces a scan code that ABL doesn't recognize.

### Confirmed by keylayout files

`qpnp_pon.kl` maps: `key 114 VOLUME_DOWN` (RESIN), `key 116 POWER` (KPDPWR)
`gpio-keys.kl` maps: `key 115 VOLUME_UP`, `key 114 VOLUME_DOWN`, `key 113 MANNER_MODE`

Note that `gpio-keys.kl` includes key 114 (VOLUME_DOWN) — this is the RESIN line exposed through the Linux kernel, not a physical button.

### Portal+ vs Portal 10"

The Portal+ (Gen 1) **does** have 3 buttons (Vol Up, Vol Down, Mute) and people HAVE reached fastboot on it. The Portal 10" was designed without a Vol Down button, effectively making fastboot **inaccessible via hardware buttons alone**.

## Alternative Paths to Fastboot

Since physical button entry is impossible, fastboot must be reached via software:

1. **BCB (Bootloader Control Block):** Write `bootonce-bootloader` to the misc partition → ABL reads it on next boot → enters fastboot. Requires EDL write access (firehose loader needed).
2. **`adb reboot bootloader`:** Would work if ADB were accessible. ADB is disabled on prod builds.
3. **PMIC RESIN hardware mod:** Open the device, find the RESIN pad on PM8998, short it to ground during boot. Hardware modification required.
4. **Modified ABL:** Flash a custom ABL that uses SCAN_UP (Vol Up) for fastboot. Requires bootloader unlock or EDL write.

---

*Fastboot via buttons is confirmed impossible on Portal 10" Gen 1. The firehose loader search becomes the critical path — EDL write access would enable both BCB-based fastboot entry AND direct partition modification.*
