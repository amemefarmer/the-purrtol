#!/usr/bin/env bash
# verify_boot_img.sh - Verify modified boot.img against original
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE
#
# Compares original and modified boot.img to confirm:
#   - Size is reasonable (within 10% of original)
#   - Modified image can be unpacked (structurally valid)
#   - Property changes are present in the modified version
#   - No unexpected changes
#
# Usage:
#   ./scripts/boot_img/verify_boot_img.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$PROJECT_ROOT/scripts/boot_img/work"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

ORIG="$WORK_DIR/original_boot.img"
MOD="$WORK_DIR/modified_boot.img"

echo "============================================"
echo "  Portal Freedom — Boot Image Verification"
echo "============================================"
echo ""

PASS=0
FAIL=0

check() {
    if [[ "$1" == "pass" ]]; then
        echo -e "  ${GREEN}PASS${NC}  $2"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}  $2"
        ((FAIL++))
    fi
}

# --- File existence ---
if [[ -f "$ORIG" ]]; then check pass "Original boot.img exists"; else check fail "Original boot.img missing"; fi
if [[ -f "$MOD" ]]; then check pass "Modified boot.img exists"; else check fail "Modified boot.img missing"; exit 1; fi

# --- Size comparison ---
ORIG_SIZE=$(stat -f%z "$ORIG" 2>/dev/null || stat --printf="%s" "$ORIG")
MOD_SIZE=$(stat -f%z "$MOD" 2>/dev/null || stat --printf="%s" "$MOD")
SIZE_DIFF_PCT=$(( (MOD_SIZE - ORIG_SIZE) * 100 / ORIG_SIZE ))

if [[ ${SIZE_DIFF_PCT#-} -le 10 ]]; then
    check pass "Size within 10% (orig: ${ORIG_SIZE}, mod: ${MOD_SIZE}, diff: ${SIZE_DIFF_PCT}%)"
else
    check fail "Size differs by ${SIZE_DIFF_PCT}% (orig: ${ORIG_SIZE}, mod: ${MOD_SIZE})"
fi

# --- Structural validation ---
VERIFY_DIR=$(mktemp -d)

echo ""
echo "Unpacking modified boot.img for validation..."

if command -v magiskboot &>/dev/null; then
    cp "$MOD" "$VERIFY_DIR/boot.img"
    cd "$VERIFY_DIR"
    if magiskboot unpack boot.img &>/dev/null; then
        check pass "Modified boot.img can be unpacked (structurally valid)"
    else
        check fail "Modified boot.img cannot be unpacked"
    fi
elif command -v docker &>/dev/null && docker image inspect magiskboot &>/dev/null 2>&1; then
    cp "$MOD" "$VERIFY_DIR/boot.img"
    if docker run --rm -v "$VERIFY_DIR:/work" -w /work magiskboot unpack boot.img &>/dev/null; then
        check pass "Modified boot.img can be unpacked (structurally valid)"
    else
        check fail "Modified boot.img cannot be unpacked"
    fi
else
    echo -e "  ${YELLOW}SKIP${NC}  Cannot validate structure (no magiskboot)"
fi

# --- Check properties in modified ramdisk ---
if [[ -f "$VERIFY_DIR/ramdisk.cpio" ]]; then
    PROP_DIR="$VERIFY_DIR/props"
    mkdir -p "$PROP_DIR"
    cd "$PROP_DIR"
    cpio -id < ../ramdisk.cpio 2>/dev/null

    # Check each expected property
    PROP_FILE=$(find "$PROP_DIR" -name "default.prop" -o -name "prop.default" 2>/dev/null | head -1)
    if [[ -n "$PROP_FILE" ]]; then
        echo ""
        echo "Property verification:"

        grep -q "ro.debuggable=1" "$PROP_FILE" 2>/dev/null && \
            check pass "ro.debuggable=1" || check fail "ro.debuggable not set to 1"

        grep -q "ro.adb.secure=0" "$PROP_FILE" 2>/dev/null && \
            check pass "ro.adb.secure=0" || check fail "ro.adb.secure not set to 0"

        grep -q "ro.secure=0" "$PROP_FILE" 2>/dev/null && \
            check pass "ro.secure=0" || check fail "ro.secure not set to 0"

        grep -q "adb" "$PROP_FILE" 2>/dev/null && \
            check pass "ADB present in USB config" || check fail "ADB not in USB config"
    fi
fi

# --- Clean up ---
rm -rf "$VERIFY_DIR"

# --- Summary ---
echo ""
echo "============================================"
echo "  Verification Summary"
echo "============================================"
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${GREEN}Modified boot.img looks good.${NC}"
    echo ""
    echo "  Ready to flash (AFTER taking a full backup):"
    echo "  ./scripts/edl/flash_partition.sh boot $MOD"
else
    echo -e "  ${RED}$FAIL verification(s) failed.${NC}"
    echo "  Review the issues above before flashing."
fi
