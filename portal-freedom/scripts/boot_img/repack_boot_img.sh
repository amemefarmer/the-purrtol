#!/usr/bin/env bash
# repack_boot_img.sh - Repack modified ramdisk into boot.img
#
# RISK LEVEL: ZERO (creating files only — does NOT touch device)
# DEVICE IMPACT: NONE
#
# Repacks the modified ramdisk back into a boot.img file.
# The resulting modified_boot.img can then be flashed to the device.
#
# Prerequisites:
#   - Boot image unpacked (unpack_boot_img.sh)
#   - Properties modified (modify_props.sh)
#
# Usage:
#   ./scripts/boot_img/repack_boot_img.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$PROJECT_ROOT/scripts/boot_img/work"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Portal Freedom — Repack Boot Image"
echo "============================================"
echo ""

# --- Verify prerequisites ---
if [[ ! -f "$WORK_DIR/original_boot.img" ]]; then
    echo -e "${RED}[FAIL]${NC} original_boot.img not found in $WORK_DIR"
    echo "Run unpack_boot_img.sh first."
    exit 1
fi

if [[ ! -d "$WORK_DIR/ramdisk_extracted" ]]; then
    echo -e "${RED}[FAIL]${NC} ramdisk_extracted not found in $WORK_DIR"
    echo "Run unpack_boot_img.sh first."
    exit 1
fi

cd "$WORK_DIR"

# --- Repack ramdisk ---
echo -e "${CYAN}[INFO]${NC} Repacking ramdisk from modified files..."

cd ramdisk_extracted
find . | cpio -o -H newc > ../ramdisk.cpio 2>/dev/null
cd "$WORK_DIR"

echo -e "${GREEN}[OK]${NC} Ramdisk repacked"

# --- Repack boot.img ---
echo -e "${CYAN}[INFO]${NC} Repacking boot.img..."

if command -v magiskboot &>/dev/null; then
    magiskboot repack original_boot.img modified_boot.img
elif command -v docker &>/dev/null && docker image inspect magiskboot &>/dev/null 2>&1; then
    docker run --rm -v "$WORK_DIR:/work" -w /work magiskboot repack original_boot.img modified_boot.img
else
    echo -e "${RED}[FAIL]${NC} Neither magiskboot nor Docker magiskboot available."
    exit 1
fi

# --- Verify ---
if [[ -f "$WORK_DIR/modified_boot.img" ]]; then
    ORIG_SIZE=$(stat -f%z "$WORK_DIR/original_boot.img" 2>/dev/null || stat --printf="%s" "$WORK_DIR/original_boot.img")
    MOD_SIZE=$(stat -f%z "$WORK_DIR/modified_boot.img" 2>/dev/null || stat --printf="%s" "$WORK_DIR/modified_boot.img")

    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Modified boot image created"
    echo ""
    echo "  Original: $WORK_DIR/original_boot.img ($ORIG_SIZE bytes)"
    echo "  Modified: $WORK_DIR/modified_boot.img ($MOD_SIZE bytes)"
    echo ""

    SIZE_DIFF=$(( MOD_SIZE - ORIG_SIZE ))
    if [[ ${SIZE_DIFF#-} -gt 1048576 ]]; then
        echo -e "${YELLOW}[WARN]${NC} Size difference is > 1MB (${SIZE_DIFF} bytes)."
        echo "  This may indicate a packing issue. Verify with:"
        echo "  ./scripts/boot_img/verify_boot_img.sh"
    else
        echo -e "${GREEN}[OK]${NC} Size difference: ${SIZE_DIFF} bytes (normal)"
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Verify:  ./scripts/boot_img/verify_boot_img.sh"
    echo "  2. Flash:   ./scripts/edl/flash_partition.sh boot $WORK_DIR/modified_boot.img"
    echo ""
    echo -e "${YELLOW}REMINDER:${NC} Ensure you have a FULL BACKUP before flashing!"
else
    echo -e "${RED}[FAIL]${NC} modified_boot.img was not created."
    echo "Check magiskboot output above for errors."
    exit 1
fi
