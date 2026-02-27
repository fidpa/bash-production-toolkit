# Utility Libraries

## ⚡ TL;DR

Helper libraries for specialized tasks: backup-safety.sh (mountpoint validation, target checks), device-detection.sh (multi-device routing, hostname-based), path-calculator.sh (relative paths for markdown links). Domain-specific utilities for production scripts.

---

## Overview

Utility libraries provide specialized helper functions for production systems:

- **Backup Safety** - Validate backup targets, prevent data loss
- **Device Detection** - Multi-device support with hostname-based routing
- **Path Utilities** - Relative path calculation for documentation tools

## Libraries

### backup-safety.sh

**Purpose**: Backup target validation and mountpoint checks

**Key Features**:
- Mountpoint validation (prevent backup to unmounted drives)
- Target directory validation (existence, writability)
- Disk space checks (prevent backup failures due to full disk)
- Backup target locking (prevent concurrent backups)
- Performance: ~0.01s per validation

**Key Functions**:
```bash
validate_backup_target "path"                   # Validate backup target
is_mountpoint "path"                            # Check if path is mountpoint
check_disk_space "path" "required_gb"           # Check available disk space
lock_backup_target "path"                       # Lock backup target
unlock_backup_target "path"                     # Unlock backup target
```

**Documentation**: [BACKUP_SAFETY.md](../../docs/utilities/BACKUP_SAFETY.md)

---

### device-detection.sh

**Purpose**: Multi-device identification and routing

**Key Features**:
- Hostname-based device detection
- Device-specific repository root paths
- Architecture detection (x86_64, aarch64, armv7l)
- User detection (current user context)
- Configuration file support (`~/.device-config`)
- Performance: ~0.001s per detection call

**Key Functions**:
```bash
detect_device                                   # Get current device name
get_device_repo_root                            # Get device-specific repo root
get_device_arch                                 # Get device architecture
get_device_user                                 # Get device primary user
is_device "device_name"                         # Check if on specific device
```

**Configuration**:
```bash
# Optional: ~/.device-config
DEVICE_NAME="my-server"
DEVICE_REPO_ROOT="/opt/myapp"
DEVICE_ARCH="x86_64"
DEVICE_USER="admin"
```

**Documentation**: [DEVICE_DETECTION.md](../../docs/utilities/DEVICE_DETECTION.md)

---

### path-calculator.sh

**Purpose**: Relative path calculation for documentation tools

**Key Features**:
- Calculate relative paths between two files
- Markdown-aware (useful for documentation link generation)
- Symlink resolution
- Directory traversal handling
- Performance: ~0.005s per calculation

**Key Functions**:
```bash
calculate_relative_path "from_path" "to_path"   # Calculate relative path
resolve_symlink "path"                          # Resolve symlink to target
normalize_path "path"                           # Normalize path (remove .., .)
```

**Documentation**: [PATH_CALCULATOR.md](../../docs/utilities/PATH_CALCULATOR.md)

## Usage Examples

### Backup Safety Validation

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source utility libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/utilities/backup-safety.sh"

# Validate backup target before starting backup
BACKUP_TARGET="/mnt/backup-drive"

if ! is_mountpoint "$BACKUP_TARGET"; then
    log_error "Backup target $BACKUP_TARGET is not a mountpoint"
    exit 1
fi

if ! validate_backup_target "$BACKUP_TARGET"; then
    log_error "Backup target validation failed"
    exit 1
fi

# Check disk space (require at least 10 GB)
if ! check_disk_space "$BACKUP_TARGET" 10; then
    log_error "Insufficient disk space on $BACKUP_TARGET"
    exit 1
fi

# Lock backup target (prevent concurrent backups)
if ! lock_backup_target "$BACKUP_TARGET"; then
    log_error "Backup already in progress"
    exit 1
fi

# Perform backup...
log_info "Starting backup to $BACKUP_TARGET"
# ... backup operations ...

# Unlock backup target
unlock_backup_target "$BACKUP_TARGET"
log_success "Backup completed successfully"
```

### Multi-Device Detection

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source utility libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/utilities/device-detection.sh"

# Detect current device
DEVICE=$(detect_device)
REPO_ROOT=$(get_device_repo_root)

log_info "Running on device: $DEVICE"
log_info "Repository root: $REPO_ROOT"

# Device-specific logic
case "$DEVICE" in
    pi-router)
        log_info "Running on Pi Router - enabling network monitoring"
        enable_network_monitoring=true
        ;;
    nas)
        log_info "Running on NAS - enabling storage monitoring"
        enable_storage_monitoring=true
        ;;
    *)
        log_warning "Unknown device: $DEVICE - using defaults"
        ;;
esac
```

### Relative Path Calculation

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source utility libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/utilities/path-calculator.sh"

# Calculate relative path for markdown link
FROM_FILE="/home/user/docs/reference/GUIDE.md"
TO_FILE="/home/user/docs/how-to/SETUP.md"

RELATIVE_PATH=$(calculate_relative_path "$FROM_FILE" "$TO_FILE")
echo "Relative path: $RELATIVE_PATH"
# Output: ../how-to/SETUP.md

# Use in markdown link generation
MARKDOWN_LINK="[Setup Guide]($RELATIVE_PATH)"
echo "Markdown link: $MARKDOWN_LINK"
```

## Requirements

- **Bash 4.0+** - All libraries require Bash 4.0 or higher
- **Standard Unix utilities** - coreutils (mkdir, df, mountpoint, realpath)
- **Optional**: Configuration files (`~/.device-config` for device-detection.sh)

## Best Practices

1. **Always validate backup targets** - Prevent data loss via mountpoint checks
2. **Use device detection for multi-host scripts** - Avoid hardcoded paths
3. **Cache device detection results** - Call once per script execution
4. **Normalize paths before comparison** - Use `normalize_path()` for reliable comparisons

## See Also

- [Back to src/](../README.md)
- [Foundation Libraries](../foundation/README.md)
- [Monitoring Libraries](../monitoring/README.md)
- [Setup Guide](../../docs/SETUP.md)
- [Examples](../../examples/README.md)
