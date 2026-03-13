#!/usr/bin/env bash
# analyze_vbmeta.sh - Parse and analyze vbmeta partition image
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — works on files only
#
# vbmeta (Verified Boot Metadata) contains the cryptographic hashes
# that verify boot.img and other partitions during boot. Understanding
# vbmeta is critical because:
#
#   - If we modify boot.img, the hash in vbmeta won't match
#   - The bootloader checks vbmeta before loading boot.img
#   - We may need to flash a vbmeta with verification disabled (flags=2)
#   - Understanding the signing chain tells us what's possible
#
# Uses avbtool from Android Open Source Project if available,
# otherwise falls back to manual hexdump analysis.
#
# Usage:
#   ./scripts/firmware/analyze_vbmeta.sh <path-to-vbmeta.img>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
LOG_FILE="$LOG_DIR/analyze_vbmeta_$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

VBMETA_IMG="${1:?Usage: analyze_vbmeta.sh <path-to-vbmeta.img>}"

if [[ ! -f "$VBMETA_IMG" ]]; then
    echo -e "${RED}[FAIL]${NC} File not found: $VBMETA_IMG"
    exit 1
fi

mkdir -p "$LOG_DIR"

echo "============================================"
echo "  Portal Freedom — vbmeta Analysis"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} Source: $VBMETA_IMG"
echo -e "${CYAN}[INFO]${NC} Size: $(stat -f%z "$VBMETA_IMG" 2>/dev/null || stat --printf="%s" "$VBMETA_IMG" 2>/dev/null) bytes"
echo ""

# --- Try avbtool first ---
if command -v avbtool &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Using avbtool for analysis"
    echo ""

    echo -e "${BOLD}=== vbmeta Info ===${NC}" | tee "$LOG_FILE"
    avbtool info_image --image "$VBMETA_IMG" 2>&1 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    echo -e "${BOLD}=== Verification Data ===${NC}" | tee -a "$LOG_FILE"
    avbtool verify_image --image "$VBMETA_IMG" 2>&1 | tee -a "$LOG_FILE" || true
else
    echo -e "${YELLOW}[WARN]${NC} avbtool not found — using manual analysis"
    echo ""
    echo "To install avbtool:"
    echo "  pip3 install avbtool"
    echo "  OR: download from AOSP external/avb/"
    echo ""

    # Manual analysis: parse the AVB header
    echo -e "${BOLD}=== Manual Header Analysis ===${NC}" | tee "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # AVB magic is "AVB0" at offset 0
    MAGIC=$(xxd -l 4 -p "$VBMETA_IMG" 2>/dev/null)
    echo "Magic bytes: $MAGIC" | tee -a "$LOG_FILE"
    if [[ "$MAGIC" == "41564230" ]]; then
        echo -e "${GREEN}Valid AVB header (AVB0)${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Invalid or non-standard header${NC}" | tee -a "$LOG_FILE"
    fi

    # Flags at offset 120 (4 bytes, big-endian)
    FLAGS=$(xxd -s 120 -l 4 -p "$VBMETA_IMG" 2>/dev/null)
    echo "Flags: 0x$FLAGS" | tee -a "$LOG_FILE"
    case "$FLAGS" in
        "00000000") echo "  Verification: ENABLED (flags=0)" | tee -a "$LOG_FILE" ;;
        "00000001") echo "  Verification: HASHTREE disabled (flags=1)" | tee -a "$LOG_FILE" ;;
        "00000002") echo "  Verification: DISABLED (flags=2)" | tee -a "$LOG_FILE" ;;
        "00000003") echo "  Verification: FULLY disabled (flags=3)" | tee -a "$LOG_FILE" ;;
        *) echo "  Unknown flags value" | tee -a "$LOG_FILE" ;;
    esac

    echo "" | tee -a "$LOG_FILE"
    echo -e "${BOLD}=== Raw Header (first 256 bytes) ===${NC}" | tee -a "$LOG_FILE"
    xxd -l 256 "$VBMETA_IMG" | tee -a "$LOG_FILE"

    echo "" | tee -a "$LOG_FILE"
    echo -e "${BOLD}=== Strings in vbmeta ===${NC}" | tee -a "$LOG_FILE"
    strings "$VBMETA_IMG" | head -50 | tee -a "$LOG_FILE"
fi

# --- Interpretation ---
echo ""
echo "============================================"
echo "  Interpretation"
echo "============================================"
echo ""
echo "If verification is ENABLED (flags=0):"
echo "  - Modifying boot.img alone will cause a boot loop"
echo "  - You must ALSO flash vbmeta with flags=2 to disable verification"
echo "  - Command: avbtool make_vbmeta_image --flags 2 --output vbmeta_disabled.img"
echo ""
echo "If verification is already DISABLED (flags=2):"
echo "  - Unusual for a retail unit — you may have a special firmware"
echo "  - You can modify boot.img without touching vbmeta"
echo ""
echo "Log saved to: $LOG_FILE"
