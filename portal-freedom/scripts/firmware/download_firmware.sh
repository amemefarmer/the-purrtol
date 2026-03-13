#!/usr/bin/env bash
# download_firmware.sh - Download Portal firmware dump from tadiphone
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — downloads to local disk only
#
# Downloads firmware dumps from dumps.tadiphone.dev/dumps/facebook
# These are full firmware images extracted from Portal devices.
# Used for OFFLINE analysis (no device needed).
#
# Available codenames:
#   ohana  - Portal 10" Gen 1 (2018) — YOUR device
#   aloha  - Portal+ Gen 1 (2018)
#   atlas  - Portal 10" Gen 2 (2019)
#   omni   - Portal 10" Gen 2 (alternate)
#   terry  - Portal Go
#
# WARNING: These are multi-GB downloads. Ensure adequate disk space.
#
# Usage:
#   ./scripts/firmware/download_firmware.sh ohana
#   ./scripts/firmware/download_firmware.sh atlas

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIRMWARE_DIR="$PROJECT_ROOT/tools/firmware"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
    echo "Usage: download_firmware.sh <device_codename>"
    echo ""
    echo "Available devices:"
    echo "  ohana  - Portal 10\" Gen 1 (2018) — most likely yours"
    echo "  aloha  - Portal+ Gen 1 (2018)"
    echo "  atlas  - Portal 10\" Gen 2 (2019)"
    echo "  omni   - Portal 10\" Gen 2 (alternate codename)"
    echo "  terry  - Portal Go"
    exit 1
fi

echo "============================================"
echo "  Portal Freedom — Firmware Download"
echo "============================================"
echo ""

DEST="$FIRMWARE_DIR/$DEVICE"
REPO_URL="https://dumps.tadiphone.dev/dumps/facebook/${DEVICE}.git"

# --- Disk space check ---
AVAIL_GB=$(df -g "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
echo -e "${CYAN}[INFO]${NC} Available disk space: ${AVAIL_GB}GB"

if [[ "$AVAIL_GB" -lt 15 ]]; then
    echo -e "${RED}[FAIL]${NC} Insufficient disk space (need 15GB+)."
    exit 1
fi

# --- Check if already downloaded ---
if [[ -d "$DEST/.git" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Firmware already downloaded at: $DEST"
    echo ""
    read -p "Update existing download? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}[INFO]${NC} Pulling latest..."
        cd "$DEST" && git pull --ff-only
        echo -e "${GREEN}[OK]${NC} Updated."
    fi
    exit 0
fi

# --- Download ---
echo -e "${CYAN}[INFO]${NC} Downloading firmware for: $DEVICE"
echo "  Source: $REPO_URL"
echo "  Destination: $DEST"
echo ""
echo "This may take 30-60 minutes depending on your connection."
echo "The download is several GB."
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

mkdir -p "$FIRMWARE_DIR"

# Use depth=1 to minimize download size
echo ""
echo -e "${CYAN}[INFO]${NC} Starting git clone (depth=1)..."
if git clone --depth 1 "$REPO_URL" "$DEST"; then
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Firmware downloaded to: $DEST"
    echo ""
    echo "Contents:"
    ls -lh "$DEST/" | head -20
    TOTAL_SIZE=$(du -sh "$DEST" | cut -f1)
    echo ""
    echo "Total size: $TOTAL_SIZE"
else
    echo ""
    echo -e "${RED}[FAIL]${NC} Download failed."
    echo ""
    echo "Possible issues:"
    echo "  - Repository may not exist for '$DEVICE'"
    echo "  - Network connectivity issue"
    echo "  - Git LFS may be required"
    echo ""
    echo "Try manually: git clone --depth 1 $REPO_URL"
    exit 1
fi

echo ""
echo "Next steps:"
echo "  1. Find boot.img:  find $DEST -name 'boot.img' -o -name 'boot*'"
echo "  2. Analyze it:     ./scripts/firmware/analyze_boot_img.sh <path-to-boot.img>"
