#!/usr/bin/env bash
# setup_bkerler_edl.sh - Clone and install bkerler/edl in a Python venv
#
# RISK LEVEL: ZERO
# DEVICE IMPACT: NONE — only installs software on the host Mac
#
# bkerler/edl is an open-source tool for Qualcomm EDL (Emergency Download)
# mode communication. It supports the Sahara/Firehose protocol and can
# read/write partitions on Qualcomm devices.
#
# Why this over QPST/QFIL:
#   - Cross-platform (native macOS, no Windows VM needed)
#   - Open source (GPLv3)
#   - Built-in firehose loader database
#   - Actively maintained
#   See: docs/adr/003_tooling_bkerler_edl.md
#
# Usage:
#   ./scripts/setup/setup_bkerler_edl.sh

set -euo pipefail

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

EDL_DIR="${HOME}/portal-tools/edl"
VENV_DIR="${EDL_DIR}/.venv"

echo "============================================"
echo "  Portal Freedom — bkerler/edl Setup"
echo "============================================"
echo ""

# --- Check Python ---
if ! command -v python3 &>/dev/null; then
    fail "python3 not found. Run install_dependencies.sh first."
    exit 1
fi
ok "Python: $(python3 --version)"

# --- Clone or update bkerler/edl ---
if [[ -d "$EDL_DIR/.git" ]]; then
    info "bkerler/edl already cloned at $EDL_DIR"
    info "Pulling latest changes..."
    cd "$EDL_DIR" && git pull --ff-only || warn "Could not pull (may be on a branch)"
else
    info "Cloning bkerler/edl..."
    mkdir -p "$(dirname "$EDL_DIR")"
    git clone https://github.com/bkerler/edl.git "$EDL_DIR"
    ok "Cloned to $EDL_DIR"
fi

# --- Create/update Python venv ---
info "Setting up Python virtual environment..."
if [[ -d "$VENV_DIR" ]]; then
    info "Existing venv found, updating..."
else
    python3 -m venv "$VENV_DIR"
    ok "Created venv at $VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Install edl and dependencies
info "Installing bkerler/edl and dependencies..."
pip install --upgrade pip setuptools wheel 2>&1 | tail -1
pip install -e "$EDL_DIR" 2>&1 | tail -3
pip install pyusb pyserial capstone keystone-engine 2>&1 | tail -1

# --- Verify installation ---
echo ""
if edl --help &>/dev/null; then
    ok "bkerler/edl installed and working"
else
    fail "bkerler/edl installation failed"
    echo "Try manually: source $VENV_DIR/bin/activate && pip install -e $EDL_DIR"
    exit 1
fi

# --- Check for built-in loaders ---
LOADER_DIR="$EDL_DIR/edl/Loaders"
if [[ -d "$LOADER_DIR" ]]; then
    LOADER_COUNT=$(find "$LOADER_DIR" -name "*.mbn" -o -name "*.bin" 2>/dev/null | wc -l | tr -d ' ')
    ok "Found $LOADER_COUNT built-in firehose loaders"

    # Check for APQ8098/MSM8998 specifically
    QCS_MATCH=$(find "$LOADER_DIR" -iname "*qcs605*" -o -iname "*sdm670*" -o -iname "*sdm710*" 2>/dev/null | head -5)
    if [[ -n "$QCS_MATCH" ]]; then
        ok "Found potentially compatible loaders for APQ8098/MSM8998 family:"
        echo "$QCS_MATCH" | while read -r f; do echo "    $(basename "$f")"; done
    else
        warn "No APQ8098/MSM8998/SD835 loaders found in built-in database"
        echo "  This is expected — Gen 1 Portal firehose is not publicly available."
        echo "  The tool may still auto-detect a compatible loader at runtime."
    fi
else
    warn "Loader directory not found at $LOADER_DIR"
fi

# --- Create convenience alias ---
echo ""
echo "============================================"
echo "  Setup Complete"
echo "============================================"
echo ""
echo "To use bkerler/edl, activate the venv first:"
echo ""
echo "  source $VENV_DIR/bin/activate"
echo "  edl --help"
echo ""
echo "Or create an alias in your ~/.zshrc:"
echo ""
echo "  alias portal-edl='source $VENV_DIR/bin/activate && edl'"
echo ""
echo "Next step: ./scripts/setup/verify_environment.sh"
