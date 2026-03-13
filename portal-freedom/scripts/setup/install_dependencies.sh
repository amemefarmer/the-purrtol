#!/usr/bin/env bash
# install_dependencies.sh - Install all required tools via Homebrew
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — only installs software on the host Mac
#
# Prerequisites:
#   - macOS with Homebrew installed (https://brew.sh)
#
# Usage:
#   ./scripts/setup/install_dependencies.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

echo "================================================"
echo "  Portal Freedom — Dependency Installer (macOS)"
echo "================================================"
echo ""

# --- Platform check ---
if [[ "$(uname)" != "Darwin" ]]; then
    fail "This script is for macOS only."
    echo "For Linux, install: python3, libusb-1.0-0-dev, adb, fastboot"
    exit 1
fi

# --- Check for Homebrew ---
if ! command -v brew &>/dev/null; then
    fail "Homebrew not found."
    echo "Install it from https://brew.sh:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
ok "Homebrew found: $(brew --version | head -1)"

# --- Install packages ---
PACKAGES=(
    "python@3.11"           # Python for bkerler/edl
    "libusb"                # USB communication for Qualcomm EDL
    "android-platform-tools" # adb and fastboot
    "git"                   # Version control
    "wget"                  # Firmware downloads
    "coreutils"             # GNU tools (sha256sum, etc.)
)

echo ""
info "Installing Homebrew packages..."
for pkg in "${PACKAGES[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        ok "$pkg already installed"
    else
        info "Installing $pkg..."
        brew install "$pkg"
        ok "$pkg installed"
    fi
done

# --- Check for Docker (optional, for magiskboot) ---
echo ""
if command -v docker &>/dev/null; then
    ok "Docker found: $(docker --version)"
else
    warn "Docker not found (optional — needed for magiskboot)"
    echo "  Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    echo "  Or use: brew install --cask docker"
    echo "  This is only needed for boot.img unpacking/repacking."
fi

# --- Create journal/logs directory ---
mkdir -p "$PROJECT_ROOT/journal/logs"

# --- Summary ---
echo ""
echo "================================================"
echo "  Installation Summary"
echo "================================================"
echo ""
echo "  python3:    $(python3 --version 2>&1)"
echo "  adb:        $(adb version 2>&1 | head -1)"
echo "  fastboot:   $(fastboot --version 2>&1 | head -1)"
echo "  git:        $(git --version 2>&1)"
echo "  libusb:     $(brew info libusb 2>/dev/null | head -1)"
echo ""
ok "All core dependencies installed."
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/setup/setup_bkerler_edl.sh"
echo "  2. Run: ./scripts/setup/verify_environment.sh"
