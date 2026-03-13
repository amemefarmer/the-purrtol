#!/usr/bin/env bash
# analyze_boot_img.sh - Unpack and analyze boot.img contents
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — works on files only, never touches the device
#
# This is the CORE ANALYSIS SCRIPT. It unpacks a boot.img and catalogs:
#   - Boot image header (kernel version, ramdisk offset, etc.)
#   - All properties in default.prop / prop.default
#   - ADB-related properties and their current values
#   - Facebook/Meta-specific security properties
#   - init.rc scripts that gate ADB access
#   - Ramdisk file listing
#
# Works with:
#   - boot.img from firmware dump (zero risk)
#   - boot.img from EDL backup (zero risk — it's a copy)
#
# Prerequisites:
#   - Docker with magiskboot image, OR
#   - magiskboot binary available
#
# Usage:
#   ./scripts/firmware/analyze_boot_img.sh <path-to-boot.img>
#   ./scripts/firmware/analyze_boot_img.sh scripts/boot_img/work/boot.img

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

BOOT_IMG="${1:?Usage: analyze_boot_img.sh <path-to-boot.img>}"

if [[ ! -f "$BOOT_IMG" ]]; then
    echo -e "${RED}[FAIL]${NC} File not found: $BOOT_IMG"
    exit 1
fi

BOOT_IMG=$(cd "$(dirname "$BOOT_IMG")" && pwd)/$(basename "$BOOT_IMG")
WORK_DIR=$(mktemp -d)
LOG_FILE="$LOG_DIR/analyze_boot_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "  Portal Freedom — Boot Image Analysis"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} Source: $BOOT_IMG"
echo -e "${CYAN}[INFO]${NC} Working dir: $WORK_DIR"
echo -e "${CYAN}[INFO]${NC} This is OFFLINE analysis — zero device risk."
echo ""

# --- Determine unpacking tool ---
USE_DOCKER=false
USE_MAGISKBOOT=false

if command -v magiskboot &>/dev/null; then
    USE_MAGISKBOOT=true
    echo -e "${GREEN}[OK]${NC} Using native magiskboot"
elif command -v docker &>/dev/null && docker image inspect magiskboot &>/dev/null 2>&1; then
    USE_DOCKER=true
    echo -e "${GREEN}[OK]${NC} Using Docker magiskboot"
else
    echo -e "${YELLOW}[WARN]${NC} Neither magiskboot nor Docker magiskboot found."
    echo "Falling back to manual analysis with basic tools."
    echo ""
    echo "For full analysis, either:"
    echo "  - Build Docker image: docker build -t magiskboot tools/docker/"
    echo "  - Install magiskboot manually"
fi

# --- Copy boot.img to working directory ---
cp "$BOOT_IMG" "$WORK_DIR/boot.img"
cd "$WORK_DIR"

# --- Unpack boot.img ---
echo ""
echo -e "${BOLD}=== Step 1: Unpacking boot.img ===${NC}" | tee "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if $USE_MAGISKBOOT; then
    magiskboot unpack boot.img 2>&1 | tee -a "$LOG_FILE"
elif $USE_DOCKER; then
    docker run --rm -v "$WORK_DIR:/work" magiskboot unpack /work/boot.img 2>&1 | tee -a "$LOG_FILE"
else
    # Fallback: try unpackbootimg if available
    if command -v unpackbootimg &>/dev/null; then
        unpackbootimg --input boot.img --output "$WORK_DIR" 2>&1 | tee -a "$LOG_FILE"
    else
        echo "Manual header analysis:" | tee -a "$LOG_FILE"
        # Read boot.img magic and header
        xxd -l 64 boot.img | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo "Cannot fully unpack without magiskboot. Install it first." | tee -a "$LOG_FILE"
    fi
fi

echo ""
echo "Unpacked contents:" | tee -a "$LOG_FILE"
ls -la "$WORK_DIR" | tee -a "$LOG_FILE"

# --- Extract ramdisk ---
echo ""
echo -e "${BOLD}=== Step 2: Extracting Ramdisk ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

RAMDISK_DIR="$WORK_DIR/ramdisk_extracted"
mkdir -p "$RAMDISK_DIR"

if [[ -f ramdisk.cpio ]]; then
    cd "$RAMDISK_DIR"
    cpio -id < ../ramdisk.cpio 2>/dev/null | tee -a "$LOG_FILE"
    echo -e "${GREEN}[OK]${NC} Ramdisk extracted" | tee -a "$LOG_FILE"
elif [[ -f ramdisk.cpio.gz ]]; then
    cd "$RAMDISK_DIR"
    gzip -d -c ../ramdisk.cpio.gz | cpio -id 2>/dev/null | tee -a "$LOG_FILE"
    echo -e "${GREEN}[OK]${NC} Ramdisk extracted (was gzipped)" | tee -a "$LOG_FILE"
else
    echo -e "${YELLOW}[WARN]${NC} No ramdisk.cpio found in unpacked boot.img" | tee -a "$LOG_FILE"
    cd "$WORK_DIR"
fi

# --- Analyze properties ---
echo ""
echo -e "${BOLD}=== Step 3: Property Analysis ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Find all prop files
PROP_FILES=$(find "$RAMDISK_DIR" -name "*.prop" -o -name "prop.*" -o -name "default.prop" -o -name "build.prop" 2>/dev/null)

if [[ -n "$PROP_FILES" ]]; then
    echo "Property files found:" | tee -a "$LOG_FILE"
    echo "$PROP_FILES" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    for pf in $PROP_FILES; do
        echo -e "${CYAN}--- $(basename "$pf") ---${NC}" | tee -a "$LOG_FILE"
        cat "$pf" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    done
else
    echo -e "${YELLOW}[WARN]${NC} No prop files found directly" | tee -a "$LOG_FILE"
    echo "Checking for symlinks..." | tee -a "$LOG_FILE"
    find "$RAMDISK_DIR" -name "*.prop" -o -name "prop.*" -type l 2>/dev/null | while read -r f; do
        echo "  $f -> $(readlink "$f")" | tee -a "$LOG_FILE"
    done
fi

# --- ADB-specific property search ---
echo ""
echo -e "${BOLD}=== Step 4: ADB Property Search ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

ADB_PROPS=(
    "ro.debuggable"
    "ro.adb.secure"
    "ro.secure"
    "persist.sys.usb.config"
    "persist.service.adb.enable"
    "persist.service.debuggable"
    "sys.usb.config"
    "sys.usb.configfs"
    "service.adb.root"
)

echo "Searching for ADB-related properties in ALL files:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for prop in "${ADB_PROPS[@]}"; do
    MATCHES=$(grep -r "$prop" "$RAMDISK_DIR" 2>/dev/null || echo "(not found)")
    echo "  $prop:" | tee -a "$LOG_FILE"
    echo "    $MATCHES" | tee -a "$LOG_FILE"
done

# --- Facebook-specific search ---
echo ""
echo -e "${BOLD}=== Step 5: Facebook/Meta-Specific Search ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

FB_PATTERNS=("facebook" "fb_" "portal" "entitlement" "seal" "unseal" "aloha" "ohana" "meta")

for pattern in "${FB_PATTERNS[@]}"; do
    MATCHES=$(grep -ri "$pattern" "$RAMDISK_DIR" 2>/dev/null | head -10)
    if [[ -n "$MATCHES" ]]; then
        echo -e "${YELLOW}Found '$pattern':${NC}" | tee -a "$LOG_FILE"
        echo "$MATCHES" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    fi
done

# --- Init script analysis ---
echo ""
echo -e "${BOLD}=== Step 6: Init Script Analysis ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

RC_FILES=$(find "$RAMDISK_DIR" -name "*.rc" 2>/dev/null)
if [[ -n "$RC_FILES" ]]; then
    echo "Init scripts found:" | tee -a "$LOG_FILE"
    echo "$RC_FILES" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    echo "ADB-related init entries:" | tee -a "$LOG_FILE"
    grep -n "adb\|adbd\|usb\|debug" $RC_FILES 2>/dev/null | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Look for device-specific init scripts
    DEVICE_RC=$(find "$RAMDISK_DIR" -name "init.aloha.rc" -o -name "init.ohana.rc" -o -name "init.portal.rc" -o -name "init.fb*.rc" 2>/dev/null)
    if [[ -n "$DEVICE_RC" ]]; then
        echo -e "${GREEN}Device-specific init scripts:${NC}" | tee -a "$LOG_FILE"
        for rc in $DEVICE_RC; do
            echo "" | tee -a "$LOG_FILE"
            echo -e "${CYAN}--- $(basename "$rc") ---${NC}" | tee -a "$LOG_FILE"
            cat "$rc" | tee -a "$LOG_FILE"
        done
    fi
fi

# --- File listing ---
echo ""
echo -e "${BOLD}=== Step 7: Full Ramdisk File Listing ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
find "$RAMDISK_DIR" -type f | sort | tee -a "$LOG_FILE"

# --- Summary ---
echo ""
echo "============================================"
echo "  Analysis Summary"
echo "============================================"
echo ""
echo "  Working directory: $WORK_DIR"
echo "  Ramdisk extracted: $RAMDISK_DIR"
echo "  Full log:          $LOG_FILE"
echo ""
echo "  Key findings are in the log above."
echo "  The working directory is TEMPORARY — copy anything you need."
echo ""
echo "Next steps:"
echo "  1. Review the ADB properties above"
echo "  2. Check the Facebook-specific entries for gating logic"
echo "  3. If ready to modify: ./scripts/boot_img/modify_props.sh"
echo ""
echo "  To keep the working directory:"
echo "  cp -r $WORK_DIR $PROJECT_ROOT/scripts/boot_img/work/"
