#!/usr/bin/env bash
# extract_boot_img.sh - Extract boot.img from a firmware dump
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — works on downloaded files only
#
# Firmware dumps from tadiphone may be in various formats:
#   - Raw .img files in the dump directory
#   - Inside a super.img (dynamic partitions)
#   - Compressed archives
#
# This script searches for boot.img in the firmware directory
# and copies it to a working location.
#
# Usage:
#   ./scripts/firmware/extract_boot_img.sh <firmware_dir>
#   ./scripts/firmware/extract_boot_img.sh tools/firmware/ohana

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

FIRMWARE_DIR="${1:?Usage: extract_boot_img.sh <firmware_directory>}"

if [[ ! -d "$FIRMWARE_DIR" ]]; then
    echo -e "${RED}[FAIL]${NC} Directory not found: $FIRMWARE_DIR"
    exit 1
fi

echo "============================================"
echo "  Portal Freedom — Boot Image Extraction"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} Searching for boot images in: $FIRMWARE_DIR"
echo ""

# Search for boot.img files
BOOT_FILES=$(find "$FIRMWARE_DIR" -name "boot.img" -o -name "boot_a.img" -o -name "boot_b.img" -o -name "boot*.bin" 2>/dev/null)

if [[ -n "$BOOT_FILES" ]]; then
    echo -e "${GREEN}[FOUND]${NC} Boot image(s):"
    echo ""
    echo "$BOOT_FILES" | while read -r f; do
        SIZE=$(stat -f%z "$f" 2>/dev/null || stat --printf="%s" "$f" 2>/dev/null || echo "?")
        echo "  $f  ($(( SIZE / 1024 / 1024 )) MB)"
    done
    echo ""

    # Use the first one found
    BOOT_IMG=$(echo "$BOOT_FILES" | head -1)
    WORK_DIR="$PROJECT_ROOT/scripts/boot_img/work"
    mkdir -p "$WORK_DIR"

    cp "$BOOT_IMG" "$WORK_DIR/boot.img"
    echo -e "${GREEN}[OK]${NC} Copied to: $WORK_DIR/boot.img"
    echo ""
    echo "Next step: ./scripts/firmware/analyze_boot_img.sh $WORK_DIR/boot.img"
else
    echo -e "${YELLOW}[NOT FOUND]${NC} No boot.img found directly."
    echo ""
    echo "The firmware may use a different structure. Searching for related files..."
    echo ""

    # Search for other image files
    echo "Image files found:"
    find "$FIRMWARE_DIR" -name "*.img" -o -name "*.bin" 2>/dev/null | head -20 | while read -r f; do
        SIZE=$(stat -f%z "$f" 2>/dev/null || stat --printf="%s" "$f" 2>/dev/null || echo "?")
        echo "  $(basename "$f")  ($(( SIZE / 1024 / 1024 )) MB)"
    done

    echo ""
    echo "If you see a 'super.img' or compressed file, additional extraction may be needed."
    echo "Check the tadiphone dump README for the specific layout."
fi
