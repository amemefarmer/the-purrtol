#!/usr/bin/env bash
# modify_props.sh - Modify ADB/debug properties in boot.img ramdisk
#
# RISK LEVEL: ZERO (modifying files only — does NOT touch device)
# DEVICE IMPACT: NONE — changes are to local files
#
# This script modifies the ramdisk properties to enable ADB access.
# The modified ramdisk must be repacked into boot.img and then
# flashed to the device (that's the risky part, not this script).
#
# Properties modified:
#   ro.debuggable:       0 → 1
#   ro.adb.secure:       1 → 0
#   ro.secure:           1 → 0
#   persist.sys.usb.config:  adds 'adb' if not present
#   persist.service.adb.enable: 0 → 1
#
# Prerequisites:
#   - Boot image unpacked (run unpack_boot_img.sh first)
#
# Usage:
#   ./scripts/boot_img/modify_props.sh
#   ./scripts/boot_img/modify_props.sh --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$PROJECT_ROOT/scripts/boot_img/work"
RAMDISK_DIR="$WORK_DIR/ramdisk_extracted"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "============================================"
echo "  Portal Freedom — Modify Boot Properties"
echo "============================================"
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN]${NC} No files will be modified."
    echo ""
fi

# --- Verify working directory ---
if [[ ! -d "$RAMDISK_DIR" ]]; then
    echo -e "${RED}[FAIL]${NC} Ramdisk not found at: $RAMDISK_DIR"
    echo "Run unpack_boot_img.sh first."
    exit 1
fi

# --- Find prop files ---
PROP_FILES=$(find "$RAMDISK_DIR" -name "default.prop" -o -name "prop.default" -o -name "build.prop" 2>/dev/null)

if [[ -z "$PROP_FILES" ]]; then
    echo -e "${RED}[FAIL]${NC} No property files found in ramdisk."
    echo "The ramdisk structure may be different than expected."
    echo ""
    echo "Files in ramdisk:"
    find "$RAMDISK_DIR" -type f | head -20
    exit 1
fi

echo "Property files found:"
echo "$PROP_FILES"
echo ""

# --- Define modifications ---
declare -A MODIFICATIONS=(
    ["ro.debuggable"]="1"
    ["ro.adb.secure"]="0"
    ["ro.secure"]="0"
    ["persist.service.adb.enable"]="1"
    ["persist.service.debuggable"]="1"
)

# --- Apply modifications ---
CHANGES_MADE=0

for prop_file in $PROP_FILES; do
    echo -e "${CYAN}--- Processing: $(basename "$prop_file") ---${NC}"
    echo ""

    for prop_key in "${!MODIFICATIONS[@]}"; do
        target_value="${MODIFICATIONS[$prop_key]}"
        current_line=$(grep "^${prop_key}=" "$prop_file" 2>/dev/null || echo "")

        if [[ -n "$current_line" ]]; then
            current_value=$(echo "$current_line" | cut -d= -f2)
            if [[ "$current_value" == "$target_value" ]]; then
                echo -e "  ${GREEN}[OK]${NC} $prop_key=$target_value (already correct)"
            else
                echo -e "  ${YELLOW}[CHANGE]${NC} $prop_key: $current_value → $target_value"
                if ! $DRY_RUN; then
                    if [[ "$(uname)" == "Darwin" ]]; then
                        sed -i '' "s/^${prop_key}=.*/${prop_key}=${target_value}/" "$prop_file"
                    else
                        sed -i "s/^${prop_key}=.*/${prop_key}=${target_value}/" "$prop_file"
                    fi
                fi
                ((CHANGES_MADE++))
            fi
        else
            echo -e "  ${YELLOW}[ADD]${NC} $prop_key=$target_value (not present, adding)"
            if ! $DRY_RUN; then
                echo "${prop_key}=${target_value}" >> "$prop_file"
            fi
            ((CHANGES_MADE++))
        fi
    done

    # Handle persist.sys.usb.config specially (need to add 'adb')
    USB_LINE=$(grep "^persist.sys.usb.config=" "$prop_file" 2>/dev/null || echo "")
    if [[ -n "$USB_LINE" ]]; then
        if echo "$USB_LINE" | grep -q "adb"; then
            echo -e "  ${GREEN}[OK]${NC} persist.sys.usb.config already includes adb"
        else
            current_usb=$(echo "$USB_LINE" | cut -d= -f2)
            new_usb="${current_usb},adb"
            echo -e "  ${YELLOW}[CHANGE]${NC} persist.sys.usb.config: $current_usb → $new_usb"
            if ! $DRY_RUN; then
                if [[ "$(uname)" == "Darwin" ]]; then
                    sed -i '' "s/^persist.sys.usb.config=.*/persist.sys.usb.config=${new_usb}/" "$prop_file"
                else
                    sed -i "s/^persist.sys.usb.config=.*/persist.sys.usb.config=${new_usb}/" "$prop_file"
                fi
            fi
            ((CHANGES_MADE++))
        fi
    else
        echo -e "  ${YELLOW}[ADD]${NC} persist.sys.usb.config=mtp,adb"
        if ! $DRY_RUN; then
            echo "persist.sys.usb.config=mtp,adb" >> "$prop_file"
        fi
        ((CHANGES_MADE++))
    fi

    echo ""
done

# --- Search and report Facebook-specific gating ---
echo -e "${CYAN}--- Checking init scripts for ADB gating ---${NC}"
echo ""

FB_GATES=$(grep -rn "adb\|adbd" "$RAMDISK_DIR"/*.rc "$RAMDISK_DIR"/init*.rc 2>/dev/null || echo "(none found)")
if [[ "$FB_GATES" != "(none found)" ]]; then
    echo "ADB references in init scripts:"
    echo "$FB_GATES"
    echo ""
    echo -e "${YELLOW}[NOTE]${NC} Review these manually."
    echo "If there are Facebook entitlement checks, they may need to be"
    echo "commented out or bypassed for ADB to actually work."
fi

# --- Summary ---
echo ""
echo "============================================"
echo "  Modification Summary"
echo "============================================"
echo ""

if $DRY_RUN; then
    echo "  Mode: DRY RUN (no files changed)"
    echo "  Changes that WOULD be made: $CHANGES_MADE"
else
    echo "  Changes made: $CHANGES_MADE"
fi

echo ""

if ! $DRY_RUN && [[ $CHANGES_MADE -gt 0 ]]; then
    echo "Next step: ./scripts/boot_img/repack_boot_img.sh"
else
    echo "Run without --dry-run to apply changes."
fi
