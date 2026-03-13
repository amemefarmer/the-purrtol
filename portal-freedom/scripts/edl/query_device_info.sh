#!/usr/bin/env bash
# query_device_info.sh - Read device identifiers via Qualcomm Sahara protocol
#
# RISK LEVEL: LOW
# DEVICE IMPACT: READ-ONLY — no data is written to the device
#
# This script reads the Hardware ID (HWID) and Public Key hash (PK Hash)
# from the device via the Sahara protocol. These values determine which
# firehose programmer (.mbn file) is compatible with your device.
#
# The HWID identifies the processor (APQ8098 / Snapdragon 835 for Gen 1).
# The PK Hash identifies the signing chain (Facebook OEM key).
#
# Prerequisites:
#   - Device must be in EDL mode (QDLoader 9008 / QUSB__BULK)
#   - bkerler/edl must be installed (run setup_bkerler_edl.sh)
#
# Usage:
#   ./scripts/edl/query_device_info.sh
#   ./scripts/edl/query_device_info.sh --dump-pbl    # Also dump PBL ROM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
LOG_FILE="$LOG_DIR/query_device_info_$(date +%Y%m%d_%H%M%S).log"
EDL_DIR="${HOME}/portal-tools/edl"
EDL_VENV="${EDL_DIR}/.venv"

DUMP_PBL=false
[[ "${1:-}" == "--dump-pbl" ]] && DUMP_PBL=true

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — Device Info Query"
echo "============================================"
echo ""

# --- Check prerequisites ---
if [[ ! -d "$EDL_VENV" ]]; then
    echo -e "${RED}[FAIL]${NC} bkerler/edl venv not found."
    echo "Run: ./scripts/setup/setup_bkerler_edl.sh"
    exit 1
fi

# Activate venv
source "$EDL_VENV/bin/activate"

# Ensure logs directory exists (bkerler/edl needs it too)
mkdir -p "$EDL_DIR/logs"

# --- Setup logging ---
mkdir -p "$LOG_DIR"

echo -e "${CYAN}[INFO]${NC} Reading device info via Sahara protocol..."
echo -e "${CYAN}[INFO]${NC} This is READ-ONLY — nothing is written to the device."
echo ""

# --- Check for device in EDL mode ---
echo -e "${CYAN}[INFO]${NC} Checking for device in EDL mode..."
if system_profiler SPUSBDataType 2>/dev/null | grep -qi "QUSB\|QDLoader\|9008"; then
    echo -e "${GREEN}[OK]${NC} Device detected in EDL mode (QDLoader 9008)"
    echo ""
else
    echo -e "${RED}[FAIL]${NC} No device in EDL mode detected on USB."
    echo ""
    echo "To enter EDL mode on Portal Gen 1:"
    echo "  1. Connect USB-C data cable (not charge-only!)"
    echo "  2. Hold Vol Down + Power button (on REAR of device, near bottom)"
    echo "  3. Keep holding until QUSB__BULK appears on USB"
    echo "  4. Re-run this script"
    exit 1
fi

# --- Query device via secureboot (Sahara command mode) ---
echo "=== Sahara Device Info ===" | tee "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

cd "$EDL_DIR"
if python edl.py secureboot --debugmode 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Sahara device info retrieved."
else
    echo ""
    echo -e "${YELLOW}[WARN]${NC} secureboot command had issues."
    echo "Check the log for HWID/PK Hash data — it may have succeeded partially."
fi

echo ""

# --- Extract key values from log ---
echo "=== Parsed Results ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

HWID=$(grep -o "HWID:.*" "$LOG_FILE" | head -1 || echo "Not found")
CPU=$(grep -o "CPU detected:.*" "$LOG_FILE" | head -1 || echo "Not found")
PKHASH=$(grep -o "PK_HASH:.*" "$LOG_FILE" | head -1 || echo "Not found")
SERIAL=$(grep -o "Serial:.*" "$LOG_FILE" | head -1 || echo "Not found")

echo "  $HWID" | tee -a "$LOG_FILE"
echo "  $CPU" | tee -a "$LOG_FILE"
echo "  $PKHASH" | tee -a "$LOG_FILE"
echo "  $SERIAL" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# --- Optionally dump PBL ---
if $DUMP_PBL; then
    PBL_FILE="$PROJECT_ROOT/backups/pbl_dump_$(date +%Y%m%d_%H%M%S).bin"
    mkdir -p "$PROJECT_ROOT/backups"
    echo -e "${CYAN}[INFO]${NC} Attempting to dump PBL ROM to: $PBL_FILE"
    echo ""

    # Re-enter EDL — the previous command may have disrupted the connection
    echo -e "${YELLOW}[NOTE]${NC} The device may need to be re-entered into EDL mode."
    echo "If the dump fails, re-enter EDL and run again."
    echo ""

    if python edl.py pbl "$PBL_FILE" --debugmode 2>&1 | tee -a "$LOG_FILE"; then
        if [[ -f "$PBL_FILE" ]]; then
            PBL_SIZE=$(stat -f%z "$PBL_FILE" 2>/dev/null || stat --printf="%s" "$PBL_FILE")
            echo ""
            echo -e "${GREEN}[SUCCESS]${NC} PBL dumped: $PBL_FILE ($PBL_SIZE bytes)"
        fi
    else
        echo ""
        echo -e "${YELLOW}[WARN]${NC} PBL dump had issues. Check log."
    fi
    echo ""
fi

# --- Firehose availability check ---
echo "============================================"
echo "  Firehose Loader Status"
echo "============================================"
echo ""

LOADER_FILE="000620e10137b8a1_7291ef5c5d99dc05"
echo "Looking for loader matching: ${LOADER_FILE}_[FHPRG/ENPRG].bin"
echo ""

FOUND_LOADER=false
for dir in "$EDL_DIR/edlclient/Loaders" "$PROJECT_ROOT/tools/firehose"; do
    if [[ -d "$dir" ]]; then
        MATCH=$(find "$dir" -name "*000620e1*" -o -name "*7291ef5c*" 2>/dev/null | head -5)
        if [[ -n "$MATCH" ]]; then
            echo -e "${GREEN}[FOUND]${NC} Potential loader in $dir:"
            echo "$MATCH"
            FOUND_LOADER=true
        fi
    fi
done

if ! $FOUND_LOADER; then
    echo -e "${YELLOW}[NOT FOUND]${NC} No matching firehose loader available."
    echo ""
    echo "Without a firehose signed with Facebook's key, partition"
    echo "read/write via EDL is not possible. You can still:"
    echo "  - Read device identity (done above)"
    echo "  - Dump PBL ROM (--dump-pbl flag)"
    echo "  - Try fastboot mode for additional probing"
fi

echo ""
echo "============================================"
echo "  What to Do With These Results"
echo "============================================"
echo ""
echo "1. Record the HWID and PK Hash values above"
echo "2. Search for compatible APQ8098/MSM8998 loaders signed by Facebook:"
echo "   - https://github.com/bkerler/Loaders"
echo "   - https://www.temblast.com/ref/loaders.htm"
echo "   - XDA Forums Portal thread"
echo "   - XDA Forums MSM8998 firehose thread"
echo "3. If you find a matching loader, place it in:"
echo "   $PROJECT_ROOT/tools/firehose/"
echo "4. Try fastboot mode next:"
echo "   ./scripts/fastboot/query_fastboot_vars.sh"
echo ""
echo "Log saved to: $LOG_FILE"
