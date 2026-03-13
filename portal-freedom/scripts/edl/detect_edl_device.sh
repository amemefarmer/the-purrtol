#!/usr/bin/env bash
# detect_edl_device.sh - Check if a Qualcomm EDL (9008) device is connected
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — only reads USB device list
#
# EDL (Emergency Download) mode is a Qualcomm hardware diagnostic mode.
# The device appears as "Qualcomm HS-USB QDLoader 9008" on USB.
#
# How to enter EDL mode on Portal Gen 1:
#   1. Power off the Portal completely
#   2. Hold Volume Up + Volume Down + Power simultaneously
#   3. While holding all buttons, connect USB-C cable to Mac
#   4. Hold for 5-10 seconds, then release
#   5. Device screen should be blank (no logo)
#
# Usage:
#   ./scripts/edl/detect_edl_device.sh

set -euo pipefail

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — EDL Device Detection"
echo "============================================"
echo ""

echo -e "${CYAN}[INFO]${NC} Scanning USB bus for Qualcomm EDL device..."
echo ""

# Method 1: system_profiler (macOS native)
USB_INFO=$(system_profiler SPUSBDataType 2>/dev/null)

if echo "$USB_INFO" | grep -qi "QDLoader\|9008\|Qualcomm HS-USB"; then
    echo -e "${GREEN}[SUCCESS]${NC} Qualcomm EDL device detected!"
    echo ""
    echo "Device details:"
    echo "$USB_INFO" | grep -A10 -i "QDLoader\|9008\|Qualcomm HS-USB" | head -15
    echo ""
    echo "The device is in EDL mode (QDLoader 9008)."
    echo ""
    echo "Next steps:"
    echo "  1. Query device info:     ./scripts/edl/query_device_info.sh"
    echo "  2. If firehose available:  ./scripts/edl/backup_all_partitions.sh"
else
    echo -e "${YELLOW}[NOT FOUND]${NC} No Qualcomm EDL device detected."
    echo ""
    echo "Possible reasons:"
    echo "  - Portal is not in EDL mode"
    echo "  - USB cable doesn't support data (charge-only cable)"
    echo "  - USB-C port issue (try different cable or port)"
    echo ""
    echo "To enter EDL mode on Portal Gen 1:"
    echo "  1. Unplug the Portal from everything"
    echo "  2. Wait 30 seconds for full power off"
    echo "  3. Hold Volume Up + Volume Down + Power simultaneously"
    echo "  4. While holding, connect USB-C cable to your Mac"
    echo "  5. Keep holding for 10 seconds, then release"
    echo "  6. The screen should remain blank (no Portal logo)"
    echo "  7. Run this script again"
    echo ""
    echo "Troubleshooting:"
    echo "  - Try a USB-C to USB-A cable (more reliable than USB-C to USB-C)"
    echo "  - Try a different USB port on your Mac"
    echo "  - If the Portal logo appears, it booted normally — try again"
    echo ""

    # Check if fastboot is visible instead
    if echo "$USB_INFO" | grep -qi "fastboot\|Android"; then
        echo -e "${CYAN}[INFO]${NC} An Android/fastboot device IS detected."
        echo "  The Portal may be in fastboot mode instead of EDL."
        echo "  Try: ./scripts/fastboot/query_fastboot_vars.sh"
    fi
fi
