# ADR-006: Risk Tolerance and Safety Protocol

**Status:** Accepted
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

The user is a **beginner** to Android device hacking, Qualcomm internals, and low-level firmware operations. The target device (Facebook Portal Gen 1) has a replacement cost under $50, but the goal is to minimize brick risk and maximize learning.

Bricking scenarios for Qualcomm devices range from recoverable to permanent:

| Brick Level | Description | Recovery |
|---|---|---|
| Soft brick | Boot loop, corrupt system partition | Fastboot flash or EDL restore |
| Medium brick | Corrupt boot/recovery, no fastboot | EDL restore (requires firehose) |
| Hard brick | Corrupt partition table, blown fuses | EDL restore or hardware ISP |
| Dead brick | Damaged eMMC, blown critical fuses | Hardware replacement or unrecoverable |

Without a verified Gen 1 firehose programmer, recovery from medium/hard brick is uncertain. This makes caution especially important.

## Decision

All operations follow a **strict safety hierarchy**:

### Safety Tier 1: ZERO RISK (Offline Analysis)
- Download and analyze firmware files on the host computer
- Extract partition tables, examine file structures, identify signing schemes
- No device connection required
- **No possibility of device damage**

### Safety Tier 2: READ-ONLY Device Operations
- Connect device via USB
- Probe EDL mode (Sahara handshake, device identification)
- Enumerate fastboot commands (`fastboot getvar all`, `fastboot oem device-info`)
- Read partition contents (if accessible)
- **Device state is not modified**

### Safety Tier 3: REVERSIBLE WRITE Operations
- Flash partitions that can be restored from backup
- Modify boot image (with original backed up)
- **Only performed after full backup of all accessible partitions**
- **Only performed after backup integrity verification (SHA-256 checksums)**

### Safety Tier 4: IRREVERSIBLE Operations
- Bootloader unlock (may trip fuse or wipe device)
- Anti-rollback fuse operations
- **Only with explicit user confirmation**
- **Only with community validation of the approach**

### Script Safety Requirements

Every script that performs device operations must implement:

1. **`--dry-run` flag:** Default mode that shows what would happen without executing.
2. **Explicit confirmation:** Destructive operations require typing `YES` (not just `y`).
3. **Backup verification:** Scripts that write to device must check for backup existence and verify checksums before proceeding.
4. **Comprehensive logging:** All device communication is logged with timestamps to `journal/` directory.
5. **Rollback instructions:** Every write operation includes documented steps to reverse it.
6. **Pre-flight checks:** Scripts verify USB connection, device mode, available space, and tool versions before operating.

### Example Script Safety Pattern

```bash
#!/bin/bash
set -euo pipefail

DRY_RUN=true
BACKUP_DIR="./backups"
LOG_FILE="./journal/$(date +%Y%m%d_%H%M%S)_operation.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-dry-run) DRY_RUN=false; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Pre-flight checks
check_backup_exists() {
    if [[ ! -f "$BACKUP_DIR/boot.img" ]]; then
        echo "ERROR: No backup found. Run backup script first."
        exit 1
    fi
}

check_backup_integrity() {
    echo "Verifying backup checksums..."
    sha256sum -c "$BACKUP_DIR/checksums.sha256" || {
        echo "ERROR: Backup integrity check failed."
        exit 1
    }
}

confirm_destructive_action() {
    echo ""
    echo "WARNING: This operation will modify the device."
    echo "Type YES to proceed, anything else to abort:"
    read -r confirmation
    if [[ "$confirmation" != "YES" ]]; then
        echo "Aborted."
        exit 0
    fi
}

# Main operation
if $DRY_RUN; then
    echo "[DRY RUN] Would perform: $OPERATION"
    echo "[DRY RUN] No changes made to device."
else
    check_backup_exists
    check_backup_integrity
    confirm_destructive_action
    # ... perform actual operation with logging ...
fi
```

## Consequences

- **Positive:** Minimizes brick risk. Builds confidence progressively. Creates a comprehensive audit trail. Dry-run mode allows safe experimentation. Beginner-friendly with guardrails.
- **Negative:** Slower overall progress. More scripting overhead. May feel overly cautious for experienced users.
- **Accepted trade-off:** Speed is sacrificed for safety. A bricked device with no recovery path ends the project entirely. The extra time spent on safety is an investment in project continuity.

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| YOLO approach (just try things) | Unacceptable brick risk for a beginner without verified recovery tools. |
| Safety for writes only | Read operations can still cause issues (e.g., reading from certain memory regions can trigger watchdog resets on some Qualcomm devices). |
| Manual safety (no scripted checks) | Human error is the primary risk. Automated checks are more reliable. |

## References

- Qualcomm EDL brick recovery procedures
- Android OEM unlocking documentation
- bkerler/edl safety considerations
- Community brick recovery stories (XDA Forums)
