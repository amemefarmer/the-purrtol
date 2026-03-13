#!/usr/bin/env bash
# test_oem_commands.sh - Enumerate available fastboot OEM commands
#
# RISK LEVEL: LOW
# DEVICE IMPACT: READ-ONLY — sends command names only, no payloads
#
# Fastboot OEM commands are vendor-specific extensions. Probing which ones
# exist reveals the device's capabilities and potential attack surface.
# Of particular interest: 'oem ramdump' (related to Qualcomm 0-day).
#
# Prerequisites:
#   - Device in fastboot mode
#
# Usage:
#   ./scripts/fastboot/test_oem_commands.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
LOG_FILE="$LOG_DIR/oem_commands_$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — OEM Command Probe"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} Sending command names only — no data payloads."
echo -e "${CYAN}[INFO]${NC} Most will return 'unknown command'. That is expected."
echo ""

mkdir -p "$LOG_DIR"

# --- Check for device ---
if ! fastboot devices | grep -q "."; then
    echo -e "${RED}[FAIL]${NC} No fastboot device detected."
    exit 1
fi

# --- Probe commands ---
COMMANDS=(
    # Standard Qualcomm OEM commands
    "oem help"
    "oem device-info"
    "oem ramdump"
    "oem uefilog"
    "oem unlock"
    "oem lock"
    "oem off-mode-charge"
    "oem select-display-panel"
    "oem get-bsn"
    "oem get-psn"
    "oem battery"

    # Facebook/Meta-specific (speculative)
    "oem fb-mode"
    "oem seal"
    "oem unseal"
    "oem adb-enable"
    "oem developer"
    "oem entitlement"

    # Standard flashing commands
    "flashing unlock"
    "flashing lock"
    "flashing get_unlock_ability"
    "flashing unlock_bootloader"
    "flashing get_unlock_data"
)

RECOGNIZED=()
UNKNOWN=()

echo "Command Results:" | tee "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for cmd in "${COMMANDS[@]}"; do
    result=$(fastboot $cmd 2>&1) || true
    status="?"

    if echo "$result" | grep -qi "unknown command\|not found\|not supported\|invalid"; then
        status="UNKNOWN"
        UNKNOWN+=("$cmd")
    elif echo "$result" | grep -qi "OKAY\|FAILED\|permission\|locked\|denied"; then
        status="RECOGNIZED"
        RECOGNIZED+=("$cmd")
    else
        # Any other response is interesting
        status="RESPONSE"
        RECOGNIZED+=("$cmd")
    fi

    printf "  %-40s %s\n" "$cmd" "[$status]" | tee -a "$LOG_FILE"
    if [[ "$status" != "UNKNOWN" ]]; then
        echo "    Response: $result" | tee -a "$LOG_FILE"
    fi
done

# --- Summary ---
echo ""
echo "============================================"
echo "  Results Summary"
echo "============================================"
echo ""

if [[ ${#RECOGNIZED[@]} -gt 0 ]]; then
    echo -e "${GREEN}Recognized commands (${#RECOGNIZED[@]}):${NC}"
    for cmd in "${RECOGNIZED[@]}"; do
        echo "  - $cmd"
    done
    echo ""

    # Special attention to ramdump
    for cmd in "${RECOGNIZED[@]}"; do
        if [[ "$cmd" == "oem ramdump" ]]; then
            echo -e "${YELLOW}[IMPORTANT]${NC} 'oem ramdump' is RECOGNIZED!"
            echo "  This is relevant to the Qualcomm fastboot 0-day."
            echo "  See: docs/adr/007_fastboot_0day_assessment.md"
            echo "  Next step: ./scripts/fastboot/probe_ramdump.sh"
            echo ""
        fi

        if [[ "$cmd" == *"unlock"* ]]; then
            echo -e "${YELLOW}[IMPORTANT]${NC} '$cmd' returned a response!"
            echo "  This may indicate unlock capability."
            echo "  Check the log for the full response."
            echo ""
        fi
    done
else
    echo "No OEM commands were recognized."
    echo "The Portal's fastboot may have a very restricted command set."
fi

echo "Unrecognized: ${#UNKNOWN[@]} commands returned 'unknown command'"
echo ""
echo "Log saved to: $LOG_FILE"
