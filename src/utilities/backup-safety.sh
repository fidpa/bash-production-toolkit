#!/bin/bash
# =============================================================================
# backup-safety.sh - Backup Target Validation Library
# =============================================================================
# Version: 1.1.0
# License: MIT
# Repository: https://github.com/fidpa/bash-production-toolkit
#
# Purpose:
#   Prevents backup scripts from accidentally writing to root partition.
#   Provides mountpoint validation, root partition detection, and disk space
#   checks with plausibility validation for large devices.
#
# Origin:
#   Created after a real-world incident where a backup script wrote 25GB to
#   an unmounted path, filling the root partition to 100%.
#
# Features:
#   - Mountpoint validation (CRITICAL: prevents root partition writes)
#   - Root partition detection (works even if path doesn't exist yet)
#   - Disk space checks with device-aware plausibility
#   - Configurable backup base directory
#
# Changelog:
#   v1.1.0 (02.01.2026): Robustness improvements
#     - is_on_root_partition: Probe parent path if target doesn't exist
#     - check_mountpoint: command -v guard + /proc/self/mounts fallback
#     - _bs_extract_base_mount: Handle edge case /mnt or /mnt/
#     - min_free_gb: Numeric validation
#   v1.0.0 (02.01.2026): Initial release
#
# Usage:
#   source backup-safety.sh
#   check_backup_target "/mnt/backup-drive/mybackup" 50 || exit 1
#
# Configuration (Environment Variables):
#   BACKUP_BASE_DIR     - Default backup directory (default: /opt/backups)
#   BACKUP_MIN_FREE_GB  - Minimum free space in GB (default: 10)
#
# Dependencies:
#   - Bash 4.0+
#   - Standard Unix tools: df, stat, mountpoint (optional), mkdir
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_BACKUP_SAFETY_LOADED:-}" ]] && return 0
readonly _BACKUP_SAFETY_LOADED=1

# Configuration with sensible defaults
readonly BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/opt/backups}"
readonly BACKUP_MIN_FREE_GB="${BACKUP_MIN_FREE_GB:-10}"

# =============================================================================
# Internal Helpers
# =============================================================================

_bs_err() { printf 'ERROR: %s\n' "$*" >&2; }
_bs_warn() { printf 'WARNING: %s\n' "$*" >&2; }
_bs_info() { printf '%s\n' "$*" >&2; }

# Extract base mount point from path (e.g., /mnt/backup/data → /mnt/backup)
# Uses Bash parameter expansion (no subprocesses)
_bs_extract_base_mount() {
    local path="$1"
    [[ "$path" != /mnt/* ]] && return 1

    local rest="${path#/mnt/}"          # backup/data
    local first_component="${rest%%/*}" # backup

    # Handle edge case: /mnt or /mnt/ → empty component
    [[ -z "$first_component" ]] && return 1

    printf '/mnt/%s' "$first_component"
}

# Get disk space info in one df call (efficiency)
# Returns: "total_gb available_gb" or empty on error
_bs_get_disk_space() {
    local path="$1"
    df -P -BG "$path" 2>/dev/null | awk 'NR==2{gsub("G",""); print $2, $4}'
}

# =============================================================================
# § 1. Mountpoint Validation (CRITICAL)
# =============================================================================

# Check if a path is a valid mounted filesystem
#
# CRITICAL: This prevents writing to empty mountpoint directories that exist
# on the root partition. If /mnt/backup exists but nothing is mounted there,
# writing to it would fill up the root partition!
#
# Usage:
#   check_mountpoint "/mnt/backup" || exit 1
#
# Returns:
#   0 - Path is a mounted filesystem
#   1 - Path is NOT mounted (DANGER: would write to root!)
#
check_mountpoint() {
    local mount_path="$1"
    [[ -z "$mount_path" ]] && { _bs_err "check_mountpoint: Missing argument"; return 1; }

    # Method 1: mountpoint command (most reliable, if available)
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$mount_path" && return 0
        return 1
    fi

    # Method 2: Fallback - Check /proc/self/mounts (more accurate than stat)
    [[ -d "$mount_path" ]] || return 1
    # shellcheck disable=SC1003
    grep -qsE "[[:space:]]${mount_path//\//\\/}[[:space:]]" /proc/self/mounts
}

# =============================================================================
# § 2. Main Validation Function
# =============================================================================

# Full backup target validation
#
# Performs comprehensive checks before allowing backup writes:
# 1. Mountpoint validation (for /mnt/* paths)
# 2. Directory accessibility (create if needed)
# 3. Root partition detection (warning)
# 4. Write permissions
# 5. Disk space (with large device plausibility check)
#
# Usage:
#   check_backup_target "/mnt/backup/mydata" [min_gb] [verbose]
#
# Arguments:
#   $1 - target path (required)
#   $2 - minimum free GB (default: $BACKUP_MIN_FREE_GB or 10, must be numeric)
#   $3 - verbose mode: "true" for detailed output (default: "false")
#
# Returns:
#   0 - All checks passed, safe to write
#   1 - One or more checks failed, DO NOT write
#
# Example:
#   # Silent mode (for scripts)
#   check_backup_target "/mnt/usb-drive/backup" 50 || exit 1
#
#   # Verbose mode (for interactive use)
#   check_backup_target "/mnt/usb-drive/backup" 50 "true" || exit 1
#
check_backup_target() {
    local target_path="$1"
    local min_free_gb="${2:-${BACKUP_MIN_FREE_GB}}"
    local verbose="${3:-false}"

    [[ -z "$target_path" ]] && { _bs_err "check_backup_target: Missing argument: path"; return 1; }

    # Validate min_free_gb is numeric
    [[ "$min_free_gb" =~ ^[0-9]+$ ]] || { _bs_err "min_free_gb must be numeric, got: $min_free_gb"; return 1; }

    # Helper for verbose output
    _log() { [[ "$verbose" == "true" ]] && _bs_info "$@"; }

    [[ "$verbose" == "true" ]] && _bs_info "=== Pre-Backup Safety Checks ==="

    # Check 1: Mountpoint validation for /mnt/* paths
    if [[ "$target_path" == /mnt/* ]]; then
        local base_mount
        base_mount=$(_bs_extract_base_mount "$target_path")

        _log "Check 1/4: Mountpoint validation ($base_mount)..."

        if [[ -z "$base_mount" ]]; then
            _bs_err "Cannot extract mount point from $target_path"
            return 1
        fi

        if ! check_mountpoint "$base_mount"; then
            _bs_err "CRITICAL: $base_mount is NOT mounted!"
            _bs_err "Writing to $target_path would fill root partition!"
            _bs_err "Check: lsblk | grep sd"
            return 1
        fi
        _log "  ✓ Mounted"
    else
        _log "Check 1/4: Mountpoint (skipped - not /mnt/* path)"
    fi

    # Check 2: Directory exists or can be created (BEFORE root check!)
    _log "Check 2/4: Directory accessibility..."
    if [[ ! -d "$target_path" ]]; then
        if ! mkdir -p "$target_path" 2>/dev/null; then
            _bs_err "Cannot create directory $target_path"
            return 1
        fi
    fi
    if [[ ! -w "$target_path" ]]; then
        _bs_err "$target_path is not writable"
        return 1
    fi
    _log "  ✓ Accessible and writable"

    # Check 3: Root partition detection (AFTER mkdir, so path exists)
    _log "Check 3/4: Root partition detection..."
    if is_on_root_partition "$target_path"; then
        _bs_warn "$target_path is on root partition"
        [[ "$verbose" == "true" ]] && _bs_info "  ⚠ WARNING: On root partition"
    else
        _log "  ✓ Not on root partition"
    fi

    # Check 4: Disk space (single df call for efficiency)
    _log "Check 4/4: Disk space (minimum ${min_free_gb}GB)..."
    local disk_info total_gb available_gb
    disk_info=$(_bs_get_disk_space "$target_path")

    if [[ -z "$disk_info" ]]; then
        _bs_err "Cannot determine disk space for $target_path"
        return 1
    fi

    read -r total_gb available_gb <<< "$disk_info"

    if [[ "${available_gb:-0}" -lt "$min_free_gb" ]]; then
        _bs_err "Insufficient space: ${available_gb}GB free (need ${min_free_gb}GB)"
        return 1
    fi

    # Plausibility check for large devices (>1TB)
    # If a 12TB drive shows only 50GB free, something might be wrong
    if [[ "${total_gb:-0}" -gt 1000 && "${available_gb:-0}" -lt 100 ]]; then
        _bs_warn "Large device (${total_gb}GB) showing low free space: ${available_gb}GB"
        _bs_warn "Expected >100GB free for 1TB+ device - verify this is correct"
    fi

    _log "  ✓ ${available_gb}GB available"
    [[ "$verbose" == "true" ]] && _bs_info "=== All Pre-Backup Checks Passed ==="

    return 0
}

# Verbose wrapper for check_backup_target
#
# Convenience function that always runs in verbose mode.
# Useful for interactive scripts or debugging.
#
# Usage:
#   pre_backup_checks "/mnt/backup/data" 50 || exit 1
#
pre_backup_checks() {
    check_backup_target "$1" "$2" "true"
}

# =============================================================================
# § 3. Root Partition Detection
# =============================================================================

# Check if a path is on the root partition
# Robust: If path doesn't exist, probe nearest existing parent
#
# Usage:
#   if is_on_root_partition "/opt/backup"; then
#       echo "WARNING: Backup target is on root partition!"
#   fi
#
# Returns:
#   0 - Path IS on root partition
#   1 - Path is NOT on root partition
#
is_on_root_partition() {
    local path="$1"
    [[ -z "$path" ]] && { _bs_err "is_on_root_partition: Missing argument"; return 1; }

    # If target doesn't exist, find nearest existing parent
    local probe="$path"
    while [[ ! -e "$probe" && "$probe" != "/" ]]; do
        probe="${probe%/*}"
        [[ -z "$probe" ]] && probe="/"
    done

    local path_dev root_dev
    path_dev=$(df -P "$probe" 2>/dev/null | awk 'NR==2{print $1}')
    root_dev=$(df -P "/" 2>/dev/null | awk 'NR==2{print $1}')

    [[ -n "$path_dev" && "$path_dev" == "$root_dev" ]]
}

# Strict check: Fail if path is on root partition
#
# Use this when you absolutely must NOT write to root partition.
#
# Usage:
#   require_not_on_root "/mnt/backup/data" || exit 1
#
# Returns:
#   0 - Path is NOT on root (safe)
#   1 - Path IS on root (FAIL)
#
require_not_on_root() {
    local path="$1"
    [[ -z "$path" ]] && { _bs_err "require_not_on_root: Missing argument"; return 1; }

    if is_on_root_partition "$path"; then
        _bs_err "CRITICAL: $path is on root partition!"
        _bs_err "Large backups must use a separate volume"
        _bs_err "Recommended: Mount a dedicated backup volume at /mnt/backup"
        return 1
    fi

    return 0
}

# =============================================================================
# § 4. Utility Functions
# =============================================================================

# Get the configured backup base directory
#
# Returns the value of BACKUP_BASE_DIR (default: /opt/backups)
# Useful for scripts that want to use a consistent backup location.
#
# Usage:
#   BACKUP_DIR="$(get_backup_base_dir)/my-service"
#   check_backup_target "$BACKUP_DIR" || exit 1
#
get_backup_base_dir() {
    printf '%s' "$BACKUP_BASE_DIR"
}

# Construct a backup path under the base directory
#
# Usage:
#   BACKUP_PATH=$(get_backup_path "my-service/daily")
#   # Returns: /opt/backups/my-service/daily (or custom BACKUP_BASE_DIR)
#
get_backup_path() {
    local subpath="$1"
    [[ -z "$subpath" ]] && { _bs_err "get_backup_path: Missing argument"; return 1; }

    printf '%s/%s' "$BACKUP_BASE_DIR" "$subpath"
}
