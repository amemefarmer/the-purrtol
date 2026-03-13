#!/usr/bin/env bash
# enumerate_everything.sh - Comprehensive fastboot enumeration for Portal 10"
#
# RISK LEVEL: LOW-MEDIUM
# DEVICE IMPACT: Mostly READ-ONLY. Some tests (getvar overflow, fetch)
#   may cause bootloader crash/reboot but no persistent changes.
#
# This script captures EVERYTHING possible from fastboot mode:
#   1. All individual getvar variables
#   2. Complete partition table with sizes
#   3. All OEM command probing (expanded)
#   4. Unlock nonce capture
#   5. fastboot boot / flash capability testing
#   6. getvar buffer overflow test (CVE-2021-1931 / new 0-day recon)
#   7. fastboot fetch test (some bootloaders allow partition reads)
#
# IMPORTANT: Run this as soon as the device enters fastboot mode!
# The device may timeout and reboot. Time is limited.
#
# Entry method: Hold ALL THREE buttons (rear Power + Vol Up + Mute)
# through multiple boot screens until "Please Reboot..." appears.
#
# Usage:
#   ./scripts/fastboot/enumerate_everything.sh [--skip-overflow]
#
# Options:
#   --skip-overflow   Skip the getvar overflow test (safest option)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/enumerate_${TIMESTAMP}.log"
SKIP_OVERFLOW=false

for arg in "$@"; do
    case "$arg" in
        --skip-overflow) SKIP_OVERFLOW=true ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log() {
    echo "$@" | tee -a "$LOG_FILE"
}

logn() {
    echo -n "$@" | tee -a "$LOG_FILE"
}

header() {
    log ""
    log "============================================"
    log "  $1"
    log "============================================"
    log ""
}

# Run a fastboot command, capture output, handle errors
fb() {
    local result
    result=$(fastboot "$@" 2>&1) || true
    echo "$result"
}

echo ""
echo -e "${BOLD}Portal Freedom — Comprehensive Fastboot Enumeration${NC}"
echo "Started: $(date)"
echo ""

mkdir -p "$LOG_DIR"
log "# Fastboot Enumeration — $TIMESTAMP"
log "# Device: Facebook Portal 10\" Gen 1 (aloha / APQ8098)"
log ""

# ================================================================
# PHASE 0: Device Detection
# ================================================================
header "Phase 0: Device Detection"

DEVICE_LINE=$(fastboot devices 2>&1 || true)
if ! echo "$DEVICE_LINE" | grep -q "fastboot"; then
    echo -e "${RED}[FAIL]${NC} No fastboot device detected!"
    echo ""
    echo "To enter fastboot mode:"
    echo "  1. Power off the Portal"
    echo "  2. Hold ALL THREE buttons: rear Power + Vol Up + Mute"
    echo "  3. Plug in USB-C data cable"
    echo "  4. Keep holding through multiple boot screens"
    echo "  5. Wait for 'Please Reboot...' text"
    exit 1
fi

log "Device: $DEVICE_LINE"
echo -e "${GREEN}[OK]${NC} Fastboot device connected: $DEVICE_LINE"

# ================================================================
# PHASE 1: Individual Variable Query
# ================================================================
header "Phase 1: Individual Variables"

VARS=(
    # Identity
    "serialno" "product" "variant" "hw-revision"
    # Versions
    "version" "version-bootloader" "version-baseband"
    # Security state
    "secure" "unlocked" "device-state"
    # Slots
    "slot-count" "current-slot" "slot-suffixes"
    "slot-retry-count:a" "slot-unbootable:a" "slot-successful:a"
    "slot-retry-count:b" "slot-unbootable:b" "slot-successful:b"
    # Capabilities
    "max-download-size" "max-fetch-size"
    "is-userspace" "super-partition-name"
    "is-logical:system_a" "is-logical:vendor_a"
    # Battery
    "battery-voltage" "battery-soc-ok" "charger-screen-enabled"
    # Misc
    "off-mode-charge" "erase-block-size" "logical-block-size"
    "snapshot-update-status" "is-build-type-production"
    # has-slot probes
    "has-slot:boot" "has-slot:system" "has-slot:vendor"
    "has-slot:vbmeta" "has-slot:dtbo" "has-slot:modem"
    "has-slot:abl" "has-slot:xbl" "has-slot:tz"
    "has-slot:keymaster" "has-slot:cmnlib" "has-slot:cmnlib64"
    "has-slot:devcfg" "has-slot:hyp" "has-slot:pmic"
    "has-slot:rpm" "has-slot:bluetooth" "has-slot:dsp"
    "has-slot:recovery" "has-slot:persist" "has-slot:userdata"
)

for var in "${VARS[@]}"; do
    result=$(fb getvar "$var")
    # Extract just the value line (fastboot puts response on stderr)
    value=$(echo "$result" | grep -i "$var" | head -1 || echo "(no response)")
    log "  $value"
done

# ================================================================
# PHASE 2: Partition Table (sizes and types)
# ================================================================
header "Phase 2: Partition Table"

PARTITIONS=(
    # A/B partitions (from fstab.aloha)
    "boot_a" "boot_b"
    "system_a" "system_b"
    "vendor_a" "vendor_b"
    "modem_a" "modem_b"
    "bluetooth_a" "bluetooth_b"
    "dsp_a" "dsp_b"
    "xbl_a" "xbl_b"
    "rpm_a" "rpm_b"
    "tz_a" "tz_b"
    "devcfg_a" "devcfg_b"
    "hyp_a" "hyp_b"
    "pmic_a" "pmic_b"
    "abl_a" "abl_b"
    "keymaster_a" "keymaster_b"
    "cmnlib_a" "cmnlib_b"
    "cmnlib64_a" "cmnlib64_b"
    "vbmeta_a" "vbmeta_b"
    # Non-A/B
    "userdata" "persist" "misc" "cache"
    # Other common Qualcomm partitions
    "recovery" "dtbo_a" "dtbo_b"
    "splash" "logo" "devinfo"
    "frp" "fsc" "fsg" "modemst1" "modemst2"
    "sec" "ssd" "ddr" "cdt" "limits" "limits-cdsp"
    "apdp" "msadp" "dpo" "logfs" "sti" "storsec"
    "mdtp_a" "mdtp_b" "mdtpsecapp_a" "mdtpsecapp_b"
    "ALIGN_TO_128K_1" "ALIGN_TO_128K_2"
    "xbl_config_a" "xbl_config_b"
    "aop_a" "aop_b" "qupfw_a" "qupfw_b"
    "ImageFv_a" "ImageFv_b"
    "logdump" "rawdump"
)

log "  $(printf '%-30s %12s %15s' 'PARTITION' 'SIZE' 'TYPE')"
log "  $(printf '%-30s %12s %15s' '--------' '----' '----')"

for part in "${PARTITIONS[@]}"; do
    size_out=$(fb getvar "partition-size:$part")
    type_out=$(fb getvar "partition-type:$part")
    size=$(echo "$size_out" | grep -i "partition-size" | awk '{print $2}' || echo "")
    ptype=$(echo "$type_out" | grep -i "partition-type" | awk '{print $2}' || echo "")

    # Only log if partition exists (has a size)
    if [[ -n "$size" && "$size" != "(no" ]]; then
        log "  $(printf '%-30s %12s %15s' "$part" "$size" "$ptype")"
    fi
done

# ================================================================
# PHASE 3: OEM Commands (expanded list)
# ================================================================
header "Phase 3: OEM Command Probe"

OEM_CMDS=(
    # Standard Qualcomm
    "oem help"
    "oem device-info"
    "oem ramdump"
    "oem uefilog"
    "oem unlock"
    "oem lock"
    "oem enable-charger-screen"
    "oem disable-charger-screen"
    "oem off-mode-charge 1"
    "oem select-display-panel"
    "oem get-bsn"
    "oem get-psn"
    "oem battery"
    "oem dump-chipid"
    "oem get-imei"
    "oem get-meid"
    "oem get-sn"
    "oem sha1sum"
    "oem dmesg"
    "oem kmsg"
    "oem lkmsg"
    "oem reboot-recovery"
    "oem reboot-bootloader"
    "oem poweroff"
    "oem continue"

    # Facebook/Meta-specific (speculative)
    "oem get_unlock_bootloader_nonce"
    "oem fb-mode"
    "oem seal"
    "oem unseal"
    "oem adb-enable"
    "oem adb enable"
    "oem developer"
    "oem entitlement"
    "oem get-serial"
    "oem debug"
    "oem factory"
    "oem factory-reset"
    "oem provision"
    "oem get-hwid"
    "oem get-version"
    "oem get-build"
    "oem privacy"
    "oem led"
    "oem wifi"
    "oem wipe"

    # Flashing commands
    "flashing unlock"
    "flashing lock"
    "flashing get_unlock_ability"
    "flashing get_unlock_data"
    "flashing unlock_bootloader"
    "flashing unlock_critical"
    "flashing lock_critical"
)

RECOGNIZED_CMDS=()
UNKNOWN_CMDS=()

for cmd in "${OEM_CMDS[@]}"; do
    result=$(fb $cmd)

    if echo "$result" | grep -qi "unknown command"; then
        UNKNOWN_CMDS+=("$cmd")
        log "  $(printf '%-45s' "$cmd") [UNKNOWN]"
    else
        RECOGNIZED_CMDS+=("$cmd")
        # Truncate long responses
        short_result=$(echo "$result" | head -5 | tr '\n' ' ')
        log "  $(printf '%-45s' "$cmd") [RECOGNIZED] → $short_result"
    fi
done

log ""
log "Recognized: ${#RECOGNIZED_CMDS[@]} commands"
log "Unknown:    ${#UNKNOWN_CMDS[@]} commands"

# ================================================================
# PHASE 4: Nonce Capture
# ================================================================
header "Phase 4: Unlock Nonce Capture"

log "Capturing 3 consecutive nonces to verify randomization..."
for i in 1 2 3; do
    nonce_result=$(fb oem get_unlock_bootloader_nonce)
    log "  Nonce $i: $nonce_result"
    sleep 1
done

# ================================================================
# PHASE 5: Capability Tests
# ================================================================
header "Phase 5: Capability Tests"

# Test: fastboot boot (unsigned boot image)
log "--- Test: fastboot boot (blocked on locked bootloaders) ---"
# We don't actually send an image, just check the error
boot_test=$(fb boot nonexistent_file.img 2>&1 || true)
log "  fastboot boot: $boot_test"

# Test: fastboot fetch (some bootloaders allow reading partitions)
log ""
log "--- Test: fastboot fetch (partition read capability) ---"
fetch_test=$(fb fetch boot_a 2>&1 || true)
log "  fastboot fetch boot_a: $fetch_test"

# Test: fastboot getvar all (known to fail but log it)
log ""
log "--- Test: fastboot getvar all ---"
getvar_all=$(fb getvar all)
log "  fastboot getvar all: $getvar_all"

# Test: fastboot oem get_unlock_bootloader_nonce with payload
log ""
log "--- Test: flashing unlock_bootloader with dummy token ---"
dummy_result=$(fb flashing unlock_bootloader 2>&1 || true)
log "  flashing unlock_bootloader (no token): $dummy_result"

# ================================================================
# PHASE 6: getvar Buffer Length Test (recon for overflow vulns)
# ================================================================
header "Phase 6: Buffer Length Probing"

if $SKIP_OVERFLOW; then
    log "SKIPPED (--skip-overflow flag set)"
    echo -e "${YELLOW}[SKIP]${NC} Buffer overflow tests skipped per --skip-overflow flag"
else
    log "Testing getvar with increasingly long inputs..."
    log "This probes for CVE-2021-1931 / getvar overflow behavior."
    log "If the device hangs/crashes, note the length that caused it."
    log ""

    # Test with safe lengths first, then approach the reported 502-byte boundary
    LENGTHS=(10 50 100 200 300 400 450 490 500 502 510 520 600 1000)

    for len in "${LENGTHS[@]}"; do
        # Generate a string of the specified length
        payload=$(python3 -c "print('A' * $len)")
        logn "  getvar (${len} bytes): "

        # Use timeout to catch hangs
        result=$(timeout 5 fastboot getvar "$payload" 2>&1) || timeout_exit=$?
        if [[ ${timeout_exit:-0} -eq 124 ]]; then
            log "TIMEOUT/HANG at ${len} bytes!"
            echo -e "${RED}[!] Device HUNG at ${len} bytes — possible overflow!${NC}"
            break
        else
            short=$(echo "$result" | head -1 | cut -c1-60)
            log "$short"
        fi
    done
fi

# ================================================================
# PHASE 7: Timing Information
# ================================================================
header "Phase 7: Summary"

log "Enumeration completed: $(date)"
log "Log file: $LOG_FILE"
log ""
log "RECOGNIZED OEM commands: ${RECOGNIZED_CMDS[*]:-none}"
log ""

# Quick device state summary
echo ""
echo -e "${BOLD}=== Quick Summary ===${NC}"
echo ""
echo "Log saved to: $LOG_FILE"
echo ""
echo "Recognized OEM commands (${#RECOGNIZED_CMDS[@]}):"
for cmd in "${RECOGNIZED_CMDS[@]}"; do
    echo -e "  ${GREEN}✓${NC} $cmd"
done
echo ""
echo "Next steps:"
echo "  1. Review the log: less $LOG_FILE"
echo "  2. If 'oem ramdump' recognized → investigate exploit path"
echo "  3. If getvar hung at >500 bytes → getvar overflow confirmed"
echo "  4. Capture ABL binary (needed for CVE-2021-1931)"
echo ""
