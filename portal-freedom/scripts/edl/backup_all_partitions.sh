#!/usr/bin/env bash
# backup_all_partitions.sh - Full partition dump via EDL
#
# RISK LEVEL: LOW
# DEVICE IMPACT: READ-ONLY — reads all partitions from flash storage
#
# THIS IS THE MOST IMPORTANT SCRIPT IN THE PROJECT.
# Always run this BEFORE making ANY modifications.
# Your backup is your lifeline if something goes wrong.
#
# Prerequisites:
#   - Device in EDL mode (QDLoader 9008)
#   - Valid firehose programmer loaded (auto or manual)
#   - bkerler/edl installed
#
# Usage:
#   ./scripts/edl/backup_all_partitions.sh
#   ./scripts/edl/backup_all_partitions.sh --loader=tools/firehose/my_loader.mbn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
EDL_VENV="${HOME}/portal-tools/edl/.venv"
BACKUP_DIR="$PROJECT_ROOT/backups/$(date +%Y-%m-%d_%H%M%S)_full_dump"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# --- Parse args ---
LOADER_ARG=""
for arg in "$@"; do
    case $arg in
        --loader=*) LOADER_ARG="$arg" ;;
    esac
done

echo "============================================"
echo "  Portal Freedom — Full Partition Backup"
echo "============================================"
echo ""
echo -e "${CYAN}[INFO]${NC} Backup destination: $BACKUP_DIR"
echo ""

# --- Check prerequisites ---
if [[ ! -d "$EDL_VENV" ]]; then
    echo -e "${RED}[FAIL]${NC} bkerler/edl not installed."
    exit 1
fi
source "$EDL_VENV/bin/activate"

# --- Disk space check ---
AVAIL_GB=$(df -g "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
if [[ "$AVAIL_GB" -lt 20 ]]; then
    echo -e "${RED}[FAIL]${NC} Only ${AVAIL_GB}GB available. Need at least 20GB for a full dump."
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Disk space: ${AVAIL_GB}GB available"

# --- Confirmation ---
echo ""
echo "This will READ all partitions from the device to your Mac."
echo "No data will be WRITTEN to the device."
echo "Estimated time: 15-45 minutes depending on storage size."
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# --- Create backup directory ---
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"

echo ""
echo -e "${CYAN}[INFO]${NC} Starting full partition dump..."
echo "Log: $LOG_FILE"
echo ""

# --- Dump all partitions ---
START_TIME=$(date +%s)

if edl rl "$BACKUP_DIR" --genxml $LOADER_ARG 2>&1 | tee "$LOG_FILE"; then
    END_TIME=$(date +%s)
    DURATION=$(( END_TIME - START_TIME ))
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Partition dump complete in ${DURATION}s"
else
    echo ""
    echo -e "${RED}[FAIL]${NC} Partition dump failed."
    echo "Check the log: $LOG_FILE"
    echo ""
    echo "Common issues:"
    echo "  - No valid firehose loader (try --loader=path/to/file.mbn)"
    echo "  - Device disconnected during dump"
    echo "  - USB timeout (try a different cable/port)"
    exit 1
fi

# --- Generate checksums ---
echo ""
echo -e "${CYAN}[INFO]${NC} Generating SHA-256 checksums..."
cd "$BACKUP_DIR"

# Use shasum (macOS) or sha256sum (Linux)
if command -v shasum &>/dev/null; then
    find . -maxdepth 1 -type f ! -name "checksums.sha256" ! -name "backup.log" -exec shasum -a 256 {} \; > checksums.sha256
elif command -v sha256sum &>/dev/null; then
    find . -maxdepth 1 -type f ! -name "checksums.sha256" ! -name "backup.log" -exec sha256sum {} \; > checksums.sha256
fi

echo -e "${GREEN}[OK]${NC} Checksums written to checksums.sha256"

# --- Summary ---
FILE_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type f ! -name "*.sha256" ! -name "*.log" ! -name "*.xml" | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo ""
echo "============================================"
echo "  Backup Summary"
echo "============================================"
echo ""
echo "  Location:   $BACKUP_DIR"
echo "  Files:      $FILE_COUNT partitions"
echo "  Total size: $TOTAL_SIZE"
echo "  Duration:   ${DURATION}s"
echo "  Checksums:  checksums.sha256"
echo ""
echo -e "${GREEN}  YOUR BACKUP IS YOUR LIFELINE.${NC}"
echo "  Keep a copy somewhere safe (external drive, cloud, etc.)"
echo ""
echo "Next steps:"
echo "  1. Verify backup: check file sizes are non-zero"
echo "  2. Copy to a second location for safety"
echo "  3. Analyze: ./scripts/firmware/analyze_boot_img.sh $BACKUP_DIR/boot.img"
