#!/usr/bin/env bash
# detect_fastboot_device.sh - Check if a fastboot device is connected
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — only reads USB device list
#
# How to enter fastboot on Portal Gen 1:
#   - Hold Volume Down + Power during boot
#   - Screen shows Portal logo with "Please Reboot..." in a black box
#   - Device shows as a fastboot device via USB-C
#
# Usage:
#   ./scripts/fastboot/detect_fastboot_device.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — Fastboot Detection"
echo "============================================"
echo ""

echo -e "${CYAN}[INFO]${NC} Checking for fastboot device..."
echo ""

DEVICES=$(fastboot devices 2>&1)

if [[ -n "$DEVICES" ]]; then
    echo -e "${GREEN}[SUCCESS]${NC} Fastboot device detected!"
    echo ""
    echo "  $DEVICES"
    echo ""
    echo "Next steps:"
    echo "  1. Query variables: ./scripts/fastboot/query_fastboot_vars.sh"
    echo "  2. Test OEM commands: ./scripts/fastboot/test_oem_commands.sh"
else
    echo -e "${YELLOW}[NOT FOUND]${NC} No fastboot device detected."
    echo ""
    echo "To enter fastboot mode on Portal Gen 1:"
    echo "  1. Power off the Portal completely"
    echo "  2. Hold Volume Down + Power button together"
    echo "  3. Connect USB-C cable while holding"
    echo "  4. Wait for Portal logo with 'Please Reboot...' text"
    echo ""
    echo "Note: Fastboot is LOCKED on retail units."
    echo "You can still READ information — just can't write or unlock."
fi
