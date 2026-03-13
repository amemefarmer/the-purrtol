#!/usr/bin/env bash
# verify_environment.sh - Validate all tools are installed and working
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — only checks host software
#
# Usage:
#   ./scripts/setup/verify_environment.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "  ${GREEN}PASS${NC}  $*"; PASS=$((PASS + 1)); }
check_fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL=$((FAIL + 1)); }
check_warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; WARN=$((WARN + 1)); }

echo "============================================"
echo "  Portal Freedom — Environment Verification"
echo "============================================"
echo ""

# --- Core Tools ---
echo "Core Tools:"

if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    check_pass "Python: $PY_VER"
else
    check_fail "python3 not found"
fi

if command -v adb &>/dev/null; then
    ADB_VER=$(adb version 2>&1 | head -1)
    check_pass "ADB: $ADB_VER"
else
    check_fail "adb not found (brew install android-platform-tools)"
fi

if command -v fastboot &>/dev/null; then
    FB_VER=$(fastboot --version 2>&1 | head -1)
    check_pass "Fastboot: $FB_VER"
else
    check_fail "fastboot not found (brew install android-platform-tools)"
fi

if command -v git &>/dev/null; then
    check_pass "Git: $(git --version)"
else
    check_fail "git not found"
fi

if command -v wget &>/dev/null; then
    check_pass "wget: available"
else
    check_warn "wget not found (brew install wget) — needed for firmware downloads"
fi

echo ""

# --- bkerler/edl ---
echo "bkerler/edl:"

EDL_DIR="${HOME}/portal-tools/edl"
VENV_DIR="${EDL_DIR}/.venv"

if [[ -d "$EDL_DIR/.git" ]]; then
    check_pass "Repository cloned at $EDL_DIR"
else
    check_fail "Not cloned — run setup_bkerler_edl.sh"
fi

if [[ -d "$VENV_DIR" ]]; then
    check_pass "Python venv exists at $VENV_DIR"

    # Test edl within the venv
    if "$VENV_DIR/bin/python" -c "import edlclient" 2>/dev/null; then
        check_pass "edlclient Python module importable"
    else
        check_fail "edlclient module not importable — reinstall with: source $VENV_DIR/bin/activate && pip install -e $EDL_DIR"
    fi

    if [[ -x "$VENV_DIR/bin/edl" ]]; then
        check_pass "edl CLI wrapper available"
    elif [[ -f "$EDL_DIR/edl.py" ]]; then
        check_pass "edl.py available at $EDL_DIR/edl.py"
    else
        check_warn "edl CLI not found in venv bin or repo"
    fi
else
    check_fail "Python venv not found — run setup_bkerler_edl.sh"
fi

echo ""

# --- libusb ---
echo "USB Support:"

if brew list libusb &>/dev/null 2>&1; then
    check_pass "libusb installed via Homebrew"
else
    check_fail "libusb not installed (brew install libusb)"
fi

# Check if any Qualcomm devices are connected (informational)
if system_profiler SPUSBDataType 2>/dev/null | grep -qi "QDLoader\|9008\|Qualcomm"; then
    check_pass "Qualcomm EDL device detected on USB!"
else
    check_warn "No Qualcomm EDL device detected (expected if Portal is not in EDL mode)"
fi

if system_profiler SPUSBDataType 2>/dev/null | grep -qi "fastboot\|Android"; then
    check_pass "Android/fastboot device detected on USB!"
else
    check_warn "No fastboot device detected (expected if Portal is not in fastboot mode)"
fi

echo ""

# --- Docker (optional) ---
echo "Docker (optional — for magiskboot):"

if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        check_pass "Docker running: $(docker --version | head -1)"
    else
        check_warn "Docker installed but not running — start Docker Desktop"
    fi

    # Check for magiskboot image
    if docker image inspect magiskboot &>/dev/null 2>&1; then
        check_pass "magiskboot Docker image built"
    else
        check_warn "magiskboot Docker image not built yet"
        echo "         Build with: docker build -t magiskboot tools/docker/"
    fi
else
    check_warn "Docker not installed — needed for boot.img unpacking"
    echo "         Install from: https://www.docker.com/products/docker-desktop/"
fi

echo ""

# --- Disk Space ---
echo "System:"

AVAIL_GB=$(df -g "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
if [[ "$AVAIL_GB" -ge 50 ]]; then
    check_pass "Disk space: ${AVAIL_GB}GB available (need ~50GB for firmware dumps)"
elif [[ "$AVAIL_GB" -ge 20 ]]; then
    check_warn "Disk space: ${AVAIL_GB}GB available (50GB+ recommended for full firmware dumps)"
else
    check_fail "Disk space: only ${AVAIL_GB}GB available (need at least 20GB)"
fi

# Check project structure
EXPECTED_DIRS=(
    "docs/research" "docs/guides" "docs/adr"
    "scripts/setup" "scripts/edl" "scripts/fastboot" "scripts/firmware" "scripts/boot_img"
    "tools/firehose" "tools/firmware" "tools/docker"
    "backups" "risk" "journal"
)

MISSING_DIRS=0
for dir in "${EXPECTED_DIRS[@]}"; do
    if [[ ! -d "$PROJECT_ROOT/$dir" ]]; then
        MISSING_DIRS=$((MISSING_DIRS + 1))
    fi
done

if [[ "$MISSING_DIRS" -eq 0 ]]; then
    check_pass "Project directory structure complete (${#EXPECTED_DIRS[@]} directories)"
else
    check_warn "$MISSING_DIRS project directories missing — run from the project root"
fi

echo ""

# --- Summary ---
echo "============================================"
echo "  Verification Summary"
echo "============================================"
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${GREEN}Environment is ready!${NC}"
    echo ""
    echo "  Next steps:"
    echo "    1. Download firmware:  ./scripts/firmware/download_firmware.sh ohana"
    echo "    2. Analyze offline:    ./scripts/firmware/analyze_boot_img.sh"
    echo "    3. Connect Portal:     ./scripts/edl/detect_edl_device.sh"
else
    echo -e "  ${RED}$FAIL checks failed. Fix the issues above before proceeding.${NC}"
    exit 1
fi
