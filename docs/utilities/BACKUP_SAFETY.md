# Backup Safety Library

## Overview

`backup-safety.sh` provides critical validation functions for backup scripts to prevent accidentally writing to the root partition. It was created after a real-world incident where a backup script wrote 25GB to an unmounted path, filling the root partition to 100%.

## Key Features

- **Mountpoint Validation**: Detects unmounted paths that would write to root
- **Root Partition Detection**: Warns when backup targets are on root filesystem
- **Disk Space Checks**: Validates available space with large device plausibility
- **Configurable**: Environment variables for customization

## Quick Start

```bash
source backup-safety.sh

# Validate backup target before writing
check_backup_target "/mnt/backup-drive/mydata" 50 || exit 1

# Now safe to write
rsync -av /data/ /mnt/backup-drive/mydata/
```

## Why This Library Exists

### The Problem

Empty mountpoint directories exist on the root partition. If your backup script writes to `/mnt/backup/` when nothing is mounted there, all data goes to the root partition:

```bash
# DANGEROUS - No mount check!
BACKUP_DIR="/mnt/usb-drive/backup"
mkdir -p "$BACKUP_DIR"
rsync -av /important-data/ "$BACKUP_DIR/"
# If USB drive isn't mounted → fills root partition!
```

### The Solution

```bash
source backup-safety.sh

BACKUP_DIR="/mnt/usb-drive/backup"
check_backup_target "$BACKUP_DIR" 50 || {
    echo "Backup target validation failed!"
    exit 1
}
# Now safe - we know the drive is mounted
rsync -av /important-data/ "$BACKUP_DIR/"
```

## Configuration

Set environment variables before sourcing:

```bash
export BACKUP_BASE_DIR="/mnt/backup"    # Default: /opt/backups
export BACKUP_MIN_FREE_GB=100           # Default: 10

source backup-safety.sh
```

## API Reference

### check_backup_target

Full backup target validation with all safety checks.

```bash
check_backup_target <path> [min_gb] [verbose]
```

**Arguments:**
- `path` - Target directory path (required)
- `min_gb` - Minimum free space in GB (default: 10 or `$BACKUP_MIN_FREE_GB`)
- `verbose` - Set to "true" for detailed output (default: "false")

**Returns:**
- `0` - All checks passed, safe to write
- `1` - Validation failed, DO NOT write

**Checks performed:**
1. Mountpoint validation (for `/mnt/*` paths)
2. Root partition detection (warning only)
3. Directory accessibility
4. Write permissions
5. Disk space availability

**Examples:**

```bash
# Silent mode (for automated scripts)
check_backup_target "/mnt/backup/daily" 50 || exit 1

# Verbose mode (for debugging)
check_backup_target "/mnt/backup/daily" 50 "true" || exit 1
# Output:
# === Pre-Backup Safety Checks ===
# Check 1/4: Mountpoint validation (/mnt/backup)...
#   ✓ Mounted
# Check 2/4: Root partition detection...
#   ✓ Not on root partition
# Check 3/4: Directory accessibility...
#   ✓ Accessible and writable
# Check 4/4: Disk space (minimum 50GB)...
#   ✓ 850GB available
# === All Pre-Backup Checks Passed ===
```

### pre_backup_checks

Convenience wrapper that always runs in verbose mode.

```bash
pre_backup_checks <path> [min_gb]
```

**Example:**

```bash
pre_backup_checks "/mnt/backup/weekly" 100 || exit 1
```

### check_mountpoint

Check if a path is a mounted filesystem.

```bash
check_mountpoint <path>
```

**Returns:**
- `0` - Path is mounted
- `1` - Path is NOT mounted (danger!)

**Example:**

```bash
if ! check_mountpoint "/mnt/usb-drive"; then
    echo "USB drive not mounted!"
    exit 1
fi
```

### is_on_root_partition

Check if a path resides on the root partition.

```bash
is_on_root_partition <path>
```

**Returns:**
- `0` - Path IS on root partition
- `1` - Path is NOT on root partition

**Example:**

```bash
if is_on_root_partition "/opt/backup"; then
    echo "Warning: Backup target is on root partition"
fi
```

### require_not_on_root

Strict check that fails if path is on root partition.

```bash
require_not_on_root <path>
```

**Returns:**
- `0` - Path is NOT on root (safe)
- `1` - Path IS on root (FAIL)

**Example:**

```bash
# Fail if trying to write large backup to root
require_not_on_root "/mnt/backup/database-dump" || exit 1
```

### get_backup_base_dir

Get the configured backup base directory.

```bash
BASE=$(get_backup_base_dir)
echo "$BASE"  # /opt/backups (or custom BACKUP_BASE_DIR)
```

### get_backup_path

Construct a path under the backup base directory.

```bash
get_backup_path <subpath>
```

**Example:**

```bash
DAILY_BACKUP=$(get_backup_path "mysql/daily")
echo "$DAILY_BACKUP"  # /opt/backups/mysql/daily
```

## Best Practices

### 1. Always Validate Before Large Writes

```bash
source backup-safety.sh

# ALWAYS validate before rsync/tar/cp of large data
check_backup_target "$BACKUP_DIR" 50 || exit 1
rsync -av /large-data/ "$BACKUP_DIR/"
```

### 2. Use Appropriate Minimum Space

```bash
# Small config backups: 1GB minimum
check_backup_target "$CONFIG_BACKUP" 1 || exit 1

# Database dumps: 50GB minimum
check_backup_target "$DB_BACKUP" 50 || exit 1

# Full system backup: 100GB minimum
check_backup_target "$SYSTEM_BACKUP" 100 || exit 1
```

### 3. Verbose Mode for Debugging

```bash
# During development/debugging
check_backup_target "$BACKUP_DIR" 50 "true" || exit 1

# In production (silent unless error)
check_backup_target "$BACKUP_DIR" 50 || exit 1
```

### 4. Combine with Logging

```bash
source logging.sh
source backup-safety.sh

log_info "Starting backup to $BACKUP_DIR"
if ! check_backup_target "$BACKUP_DIR" 50; then
    log_error "Backup target validation failed"
    exit 1
fi
log_info "Backup target validated, starting rsync"
```

## Real-World Incident

### What Happened

A backup script was configured to write to `/mnt/wd-mybook/admin/backup/`. The external USB drive was not mounted (disconnected for maintenance). The script:

1. Checked if directory exists: `[[ -d "/mnt/wd-mybook/admin" ]]` → TRUE (empty mountpoint exists)
2. Started writing 25GB of backup data
3. Filled root partition to 100%
4. System became unresponsive
5. Required emergency intervention

### The Fix

```bash
# OLD (DANGEROUS)
if [[ ! -d "/mnt/wd-mybook/admin" ]]; then
    echo "Backup directory not found"
    exit 1
fi
rsync -av /data/ /mnt/wd-mybook/admin/backup/

# NEW (SAFE)
source backup-safety.sh
check_backup_target "/mnt/wd-mybook/admin/backup" 50 || exit 1
rsync -av /data/ /mnt/wd-mybook/admin/backup/
```

## Dependencies

- Bash 4.0+
- Standard Unix tools: `df`, `stat`, `mountpoint`, `mkdir`
- No external dependencies

## Integration with Other Libraries

Works well with:
- `logging.sh` - For structured log output
- `alerts.sh` - Send alerts on backup failures
- `secure-file-utils.sh` - For atomic backup metadata files

```bash
source logging.sh
source alerts.sh
source backup-safety.sh

log_info "Starting scheduled backup"

if ! check_backup_target "$BACKUP_DIR" 50; then
    log_error "Backup target validation failed"
    send_alert "Backup Failed" "Target validation failed for $BACKUP_DIR"
    exit 1
fi

# Proceed with backup...
```
