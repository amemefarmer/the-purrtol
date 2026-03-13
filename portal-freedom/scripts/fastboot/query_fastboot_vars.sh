#!/usr/bin/env bash
# query_fastboot_vars.sh - Read all fastboot variables from the device
#
# RISK LEVEL: LOW
# DEVICE IMPACT: READ-ONLY — queries device info, writes nothing
#
# Fastboot variables reveal critical device information:
#   - Bootloader lock status
#   - Firmware version
#   - Hardware revision
#   - Partition scheme (A/B vs A-only via slot-count)
#   - Secure boot state
#
# Prerequisites:
#   - Device in fastboot mode (Volume Down + Power during boot)
#   - USB-C cable connected
#
# Usage:
#   ./scripts/fastboot/query_fastboot_vars.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
LOG_FILE="$LOG_DIR/fastboot_vars_$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — Fastboot Variable Query"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} This is READ-ONLY — nothing is written to the device."
echo ""

mkdir -p "$LOG_DIR"

# --- Check for device ---
if ! fastboot devices | grep -q "."; then
    echo -e "${RED}[FAIL]${NC} No fastboot device detected."
    echo "Enter fastboot mode first: Volume Down + Power during boot"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Fastboot device connected."
echo ""

# --- Query all variables ---
echo "=== All Variables ===" | tee "$LOG_FILE"
fastboot getvar all 2>&1 | tee -a "$LOG_FILE"
echo ""

# --- Key variables for our purposes ---
echo "============================================" | tee -a "$LOG_FILE"
echo "  Key Variables for Portal Unlocking" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

KEY_VARS=(
    "unlocked"
    "device-state"
    "secure"
    "hw-revision"
    "variant"
    "version-bootloader"
    "version-baseband"
    "serialno"
    "product"
    "slot-count"
    "current-slot"
    "has-slot:boot"
    "has-slot:system"
    "has-slot:vbmeta"
    "max-download-size"
    "battery-voltage"
)

for var in "${KEY_VARS[@]}"; do
    result=$(fastboot getvar "$var" 2>&1 | grep -i "$var" || echo "$var: (not available)")
    echo "  $result" | tee -a "$LOG_FILE"
done

echo "" | tee -a "$LOG_FILE"

# --- Interpret results ---
echo "============================================"
echo "  Interpretation"
echo "============================================"
echo ""

# Check lock status
UNLOCKED=$(fastboot getvar unlocked 2>&1 | grep -i "unlocked" | head -1 || echo "unknown")
if echo "$UNLOCKED" | grep -qi "true\|yes"; then
    echo -e "  ${GREEN}BOOTLOADER: UNLOCKED${NC}"
    echo "  This is extremely unusual for a retail Portal."
    echo "  You may have a developer unit!"
elif echo "$UNLOCKED" | grep -qi "false\|no"; then
    echo -e "  ${RED}BOOTLOADER: LOCKED${NC} (expected for retail units)"
else
    echo -e "  ${YELLOW}BOOTLOADER: Could not determine lock status${NC}"
fi

# Check slot count (A/B vs A-only)
SLOTS=$(fastboot getvar slot-count 2>&1 | grep -i "slot-count" | head -1 || echo "unknown")
if echo "$SLOTS" | grep -q "2"; then
    echo "  PARTITION SCHEME: A/B (two slots)"
    echo "  This means boot_a/boot_b, system_a/system_b, etc."
elif echo "$SLOTS" | grep -q "1"; then
    echo "  PARTITION SCHEME: A-only (single slot)"
else
    echo -e "  ${YELLOW}PARTITION SCHEME: Could not determine${NC}"
fi

echo ""
echo "Log saved to: $LOG_FILE"
echo ""
echo "Next steps:"
echo "  1. Test OEM commands: ./scripts/fastboot/test_oem_commands.sh"
echo "  2. Probe ramdump: ./scripts/fastboot/probe_ramdump.sh"
