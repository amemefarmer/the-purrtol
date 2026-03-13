#!/usr/bin/env bash
# unpack_boot_img.sh - Unpack boot.img for modification
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — works on files only
#
# Creates a working directory with the unpacked boot.img contents:
#   - kernel, ramdisk.cpio, dtb, etc.
#   - Extracted ramdisk filesystem
#
# Usage:
#   ./scripts/boot_img/unpack_boot_img.sh <boot.img>
#   ./scripts/boot_img/unpack_boot_img.sh scripts/boot_img/work/boot.img

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$PROJECT_ROOT/scripts/boot_img/work"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BOOT_IMG="${1:?Usage: unpack_boot_img.sh <path-to-boot.img>}"

if [[ ! -f "$BOOT_IMG" ]]; then
    echo -e "${RED}[FAIL]${NC} File not found: $BOOT_IMG"
    exit 1
fi

echo "============================================"
echo "  Portal Freedom — Unpack Boot Image"
echo "============================================"
echo ""

mkdir -p "$WORK_DIR"

# Copy boot.img to work directory
BOOT_IMG_ABS=$(cd "$(dirname "$BOOT_IMG")" && pwd)/$(basename "$BOOT_IMG")
cp "$BOOT_IMG_ABS" "$WORK_DIR/original_boot.img"
echo -e "${GREEN}[OK]${NC} Copied to: $WORK_DIR/original_boot.img"

cd "$WORK_DIR"

# --- Unpack with magiskboot ---
if command -v magiskboot &>/dev/null; then
    echo -e "${CYAN}[INFO]${NC} Unpacking with magiskboot..."
    magiskboot unpack original_boot.img
elif command -v docker &>/dev/null && docker image inspect magiskboot &>/dev/null 2>&1; then
    echo -e "${CYAN}[INFO]${NC} Unpacking with Docker magiskboot..."
    docker run --rm -v "$WORK_DIR:/work" -w /work magiskboot unpack original_boot.img
else
    echo -e "${RED}[FAIL]${NC} Neither magiskboot nor Docker magiskboot available."
    echo "Build Docker image: docker build -t magiskboot $PROJECT_ROOT/tools/docker/"
    exit 1
fi

echo ""
echo -e "${GREEN}[OK]${NC} Boot image unpacked."

# --- Extract ramdisk ---
if [[ -f ramdisk.cpio ]]; then
    echo -e "${CYAN}[INFO]${NC} Extracting ramdisk..."
    mkdir -p ramdisk_extracted
    cd ramdisk_extracted
    cpio -id < ../ramdisk.cpio 2>/dev/null
    cd "$WORK_DIR"
    echo -e "${GREEN}[OK]${NC} Ramdisk extracted to: $WORK_DIR/ramdisk_extracted/"
fi

echo ""
echo "Contents of work directory:"
ls -la "$WORK_DIR"
echo ""
echo "Ramdisk contents:"
ls -la "$WORK_DIR/ramdisk_extracted/" 2>/dev/null || echo "(no ramdisk)"
echo ""
echo "Next step: ./scripts/boot_img/modify_props.sh"
