#!/usr/bin/env bash
# probe_ramdump.sh - Cautious probe of the fastboot oem ramdump command
#
# RISK LEVEL: LOW (command name only, NO overflow payload)
# DEVICE IMPACT: READ-ONLY — sends only the command name
#
# CONTEXT: A Qualcomm fastboot 0-day was disclosed in Feb 2025 involving
# a stack overflow in the 'oem ramdump' handler. The exploit requires
# sending a massive character parameter to trigger the overflow.
#
# THIS SCRIPT DOES NOT ATTEMPT THE EXPLOIT.
# It only checks if the command exists and what it returns.
# Sending the command name alone is completely safe.
#
# See: docs/adr/007_fastboot_0day_assessment.md
#
# Prerequisites:
#   - Device in fastboot mode
#   - Ran test_oem_commands.sh first (to know if ramdump is recognized)
#
# Usage:
#   ./scripts/fastboot/probe_ramdump.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
LOG_FILE="$LOG_DIR/probe_ramdump_$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — Ramdump Command Probe"
echo "============================================"
echo ""
echo -e "${CYAN}[SAFETY]${NC} This sends ONLY the command name."
echo "  No payload. No overflow attempt. Completely safe."
echo "  We are checking if the command handler EXISTS."
echo ""

mkdir -p "$LOG_DIR"

# --- Check for device ---
if ! fastboot devices | grep -q "."; then
    echo -e "${RED}[FAIL]${NC} No fastboot device detected."
    exit 1
fi

read -p "Continue with probe? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo "" | tee "$LOG_FILE"

# --- Probe oem ramdump ---
echo "=== fastboot oem ramdump ===" | tee -a "$LOG_FILE"
RAMDUMP_RESULT=$(fastboot oem ramdump 2>&1) || true
echo "$RAMDUMP_RESULT" | tee -a "$LOG_FILE"
echo ""

# --- Probe oem uefilog ---
echo "=== fastboot oem uefilog ===" | tee -a "$LOG_FILE"
UEFILOG_RESULT=$(fastboot oem uefilog 2>&1) || true
echo "$UEFILOG_RESULT" | tee -a "$LOG_FILE"
echo ""

# --- Interpretation ---
echo "============================================"
echo "  Interpretation"
echo "============================================"
echo ""

RAMDUMP_EXISTS=false
UEFILOG_EXISTS=false

if echo "$RAMDUMP_RESULT" | grep -qi "unknown command"; then
    echo "  oem ramdump: NOT available"
    echo "  The ramdump handler does not exist on this device."
    echo "  The Qualcomm fastboot 0-day is NOT applicable here."
elif echo "$RAMDUMP_RESULT" | grep -qi "not supported\|not found"; then
    echo "  oem ramdump: NOT supported"
else
    RAMDUMP_EXISTS=true
    echo -e "  ${GREEN}oem ramdump: AVAILABLE${NC}"
    echo "  The ramdump command handler EXISTS on this device."
fi

echo ""

if echo "$UEFILOG_RESULT" | grep -qi "unknown command"; then
    echo "  oem uefilog: NOT available"
elif echo "$UEFILOG_RESULT" | grep -qi "not supported\|not found"; then
    echo "  oem uefilog: NOT supported"
else
    UEFILOG_EXISTS=true
    echo -e "  ${GREEN}oem uefilog: AVAILABLE${NC}"
fi

echo ""

if $RAMDUMP_EXISTS; then
    echo "============================================"
    echo -e "  ${YELLOW}SIGNIFICANT FINDING${NC}"
    echo "============================================"
    echo ""
    echo "  The 'oem ramdump' command is recognized by this device."
    echo "  This is relevant to the Qualcomm fastboot 0-day vulnerability."
    echo ""
    echo "  DO NOT attempt to exploit this yourself. The exploit requires:"
    echo "    - Precise payload size calculation"
    echo "    - ARM64 ROP chain construction"
    echo "    - Understanding of this specific ABL's memory layout"
    echo "    - A single mistake can permanently brick the device"
    echo ""
    echo "  Recommended actions:"
    echo "    1. Document this finding (saved to log)"
    echo "    2. Share on the XDA Portal thread"
    echo "    3. Monitor for public exploit tools"
    echo "    4. Consider reaching out to the 0-day discoverer"
    echo ""
    echo "  See: docs/adr/007_fastboot_0day_assessment.md"

    if $UEFILOG_EXISTS; then
        echo ""
        echo "  BOTH 'oem ramdump' AND 'oem uefilog' are available."
        echo "  This matches the 0-day exploit prerequisites exactly."
    fi
fi

echo ""
echo "Log saved to: $LOG_FILE"
