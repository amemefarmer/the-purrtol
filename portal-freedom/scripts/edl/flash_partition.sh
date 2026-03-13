#!/usr/bin/env bash
# flash_partition.sh - Flash a single partition to device via EDL
#
# RISK LEVEL: HIGH
# DEVICE IMPACT: WRITE (REVERSIBLE if backup exists)
#
# WARNING: This overwrites a partition on the device's flash storage.
# Only proceed if you have a FULL BACKUP (run backup_all_partitions.sh first).
# If the flash fails or the modified image is rejected by secure boot,
# you can restore from backup by re-running this script with the backup file.
#
# Prerequisites:
#   - Device in EDL mode (QDLoader 9008)
#   - Valid firehose programmer loaded
#   - FULL BACKUP completed (backup_all_partitions.sh)
#
# Usage:
#   ./scripts/edl/flash_partition.sh <partition_name> <image_file>
#   ./scripts/edl/flash_partition.sh --dry-run <partition_name> <image_file>
#   ./scripts/edl/flash_partition.sh --loader=tools/firehose/my.mbn boot modified_boot.img
#
# Examples:
#   ./scripts/edl/flash_partition.sh boot backups/2026-02-24/boot.img     # Restore backup
#   ./scripts/edl/flash_partition.sh boot scripts/boot_img/modified_boot.img  # Flash modified

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/journal/logs"
EDL_VENV="${HOME}/portal-tools/edl/.venv"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# --- Parse args ---
DRY_RUN=false
LOADER_ARG=""
POSITIONAL=()

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --loader=*) LOADER_ARG="$arg" ;;
        *) POSITIONAL+=("$arg") ;;
    esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
    echo "Usage: flash_partition.sh [--dry-run] [--loader=path.mbn] <partition_name> <image_file>"
    echo ""
    echo "Examples:"
    echo "  flash_partition.sh boot modified_boot.img"
    echo "  flash_partition.sh vbmeta vbmeta_disabled.img"
    echo "  flash_partition.sh --dry-run boot modified_boot.img"
    exit 1
fi

PARTITION="${POSITIONAL[0]}"
IMAGE="${POSITIONAL[1]}"

# --- Validate image file ---
if [[ ! -f "$IMAGE" ]]; then
    echo -e "${RED}[FAIL]${NC} Image file not found: $IMAGE"
    exit 1
fi

IMAGE_SIZE=$(stat -f%z "$IMAGE" 2>/dev/null || stat --printf="%s" "$IMAGE" 2>/dev/null)

echo "============================================"
echo "  Portal Freedom — Flash Partition"
echo "============================================"
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN]${NC} No changes will be made."
    echo ""
fi

echo "  Partition:  $PARTITION"
echo "  Image:      $IMAGE"
echo "  Image size: $IMAGE_SIZE bytes ($(( IMAGE_SIZE / 1024 / 1024 )) MB)"
echo ""

# --- Safety checks ---

# Check backup exists
BACKUP_DIRS=$(find "$PROJECT_ROOT/backups" -maxdepth 1 -name "*_full_dump" -type d 2>/dev/null | wc -l | tr -d ' ')
if [[ "$BACKUP_DIRS" -eq 0 ]]; then
    echo -e "${RED}[DANGER]${NC} NO BACKUP FOUND!"
    echo ""
    echo "You MUST have a full backup before flashing."
    echo "Run: ./scripts/edl/backup_all_partitions.sh"
    echo ""
    echo "Flashing without a backup means you CANNOT recover if something goes wrong."
    echo ""
    read -p "Continue WITHOUT backup? This is EXTREMELY RISKY. Type 'I ACCEPT THE RISK': " confirm
    if [[ "$confirm" != "I ACCEPT THE RISK" ]]; then
        echo "Aborted. Good choice — go take a backup first."
        exit 1
    fi
else
    echo -e "${GREEN}[OK]${NC} Found $BACKUP_DIRS backup(s) in backups/"
fi

# Critical partitions warning
CRITICAL_PARTITIONS=("xbl" "xbl_a" "xbl_b" "sbl1" "abl" "abl_a" "abl_b" "tz" "tz_a" "tz_b" "hyp" "hyp_a" "hyp_b" "rpm" "rpm_a" "rpm_b")
for cp in "${CRITICAL_PARTITIONS[@]}"; do
    if [[ "$PARTITION" == "$cp" ]]; then
        echo ""
        echo -e "${RED}[CRITICAL WARNING]${NC} You are about to flash '$PARTITION'!"
        echo "This is a CRITICAL boot chain partition."
        echo "Flashing a bad image here can PERMANENTLY BRICK the device"
        echo "(unrecoverable even via EDL)."
        echo ""
        read -p "Are you ABSOLUTELY SURE? Type 'FLASH CRITICAL': " confirm
        if [[ "$confirm" != "FLASH CRITICAL" ]]; then
            echo "Aborted."
            exit 1
        fi
        break
    fi
done

# --- Final confirmation ---
echo ""
echo -e "${RED}=== FINAL CONFIRMATION ===${NC}"
echo ""
echo "This will OVERWRITE the '$PARTITION' partition on the device."
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would execute: edl w $PARTITION $IMAGE $LOADER_ARG"
    echo "No changes were made."
    exit 0
fi

read -p "Type 'YES' to flash, anything else to abort: " confirm
if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Flash ---
source "$EDL_VENV/bin/activate"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/flash_${PARTITION}_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo -e "${CYAN}[INFO]${NC} Flashing $PARTITION..."
echo "Log: $LOG_FILE"

if edl w "$PARTITION" "$IMAGE" $LOADER_ARG 2>&1 | tee "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Flash complete."
    echo ""
    echo "Next steps:"
    echo "  1. Power cycle the device (unplug USB, wait 10s, then power on)"
    echo "  2. Watch for normal boot vs boot loop"
    echo "  3. If boot loop: re-enter EDL and flash the BACKUP:"
    echo "     ./scripts/edl/flash_partition.sh $PARTITION backups/LATEST/$PARTITION.bin"
else
    echo ""
    echo -e "${RED}[FAIL]${NC} Flash failed. Check log: $LOG_FILE"
    echo "The device should still be in EDL mode — no changes may have been made."
fi
