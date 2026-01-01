#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Secure File Utilities Library
# Version: 1.0.0
#
# Purpose:
#   Prevent Bash variable-substitution security vulnerabilities through
#   atomic file operations with secure temp file handling.
#
# Features:
#   - Atomic file writes (mktemp + chmod + mv)
#   - Race-condition prevention
#   - StateDirectory-aware (systemd integration)
#   - Path traversal protection
#   - Automatic temp file cleanup
#
# Usage:
#   source "/path/to/secure-file-utils.sh"
#   sfu_write_file "$content" "/path/to/file" "644"
#   sfu_append_file "$content" "/path/to/file"
#   sfu_heredoc "/path/to/file" <<'EOF'
#   content here
#   EOF
#
# Dependencies:
#   - Bash 4.0+
#   - coreutils (mktemp, realpath, chmod, mv)
#
# Configuration (environment variables):
#   STATE_DIRECTORY - systemd StateDirectory (auto-set by systemd)
#   TMPDIR          - Custom temp directory (default: /tmp)
#
# Error Handling:
#   Libraries use set -uo pipefail (no -e) for explicit error handling.
#   All functions return exit codes - caller handles errors.
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

set -uo pipefail  # No -e: Using explicit error handling

# ============================================================================
# INCLUDE GUARD
# ============================================================================
if [[ -n "${_SECURE_FILE_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly _SECURE_FILE_UTILS_LOADED=1

# Set strict permissions for temp file operations
umask 077

# Global configuration - StateDirectory-aware
# Priority: STATE_DIRECTORY (systemd) > TMPDIR (user) > /tmp (fallback)
readonly SECURE_TEMP_DIR="${STATE_DIRECTORY:-${TMPDIR:-/tmp}}/bash-toolkit-secure-${USER:-$(whoami)}"

# Only set SCRIPT_NAME if not already defined
if [[ -z "${SCRIPT_NAME:-}" ]]; then
    readonly SCRIPT_NAME="${0##*/}"
fi

# PID for potential future use in temp file naming
# shellcheck disable=SC2034
readonly PID="$$"

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

# Internal error helper - adds caller context to error messages
_sfu_error() {
    local msg="$1"

    # Get caller information (1 frame up from this function)
    # shellcheck disable=SC2207
    local caller_info
    caller_info=( $(caller 1) )
    local line="${caller_info[0]:-unknown}"
    local func="${caller_info[1]:-main}"
    local file="${caller_info[2]:-unknown}"

    file="${file##*/}"
    echo "ERROR [$file:$func:$line]: $msg" >&2
}

# Ensure secure temp directory exists
_sfu_init_temp() {
    if [[ -n "${STATE_DIRECTORY:-}" ]]; then
        # StateDirectory mode: systemd created parent
        if [[ ! -d "$STATE_DIRECTORY" ]]; then
            _sfu_error "StateDirectory parent not found: $STATE_DIRECTORY"
            return 1
        fi

        if [[ ! -d "$SECURE_TEMP_DIR" ]]; then
            if mkdir -p "$SECURE_TEMP_DIR" 2>/dev/null; then
                chmod 700 "$SECURE_TEMP_DIR" 2>/dev/null || true
            fi
        fi
        return 0
    fi

    # Traditional /tmp mode
    if [[ ! -d "$SECURE_TEMP_DIR" ]]; then
        if mkdir -p "$SECURE_TEMP_DIR" 2>/dev/null; then
            chmod 700 "$SECURE_TEMP_DIR" 2>/dev/null || true
        fi
    fi
    return 0
}

# ============================================================================
# PUBLIC API
# ============================================================================

# Write content to file atomically
#
# Usage: sfu_write_file "content" "/path/to/target" ["permissions"]
# Returns: 0 on success, 1 on error
#
# Example:
#   sfu_write_file "$config_content" "/etc/app.conf" "644"
#
sfu_write_file() {
    local content="${1-}"
    local target="${2-}"
    local perms="${3:-600}"

    [[ -n "$content" ]] || { _sfu_error "Content cannot be empty"; return 1; }
    [[ -n "$target" ]] || { _sfu_error "Target path cannot be empty"; return 1; }

    local target_dir
    target_dir="$(dirname "$target")"
    [[ -d "$target_dir" ]] || {
        _sfu_error "Target directory '$target_dir' does not exist"
        return 1
    }

    _sfu_init_temp
    local temp_file
    temp_file=$(mktemp "$SECURE_TEMP_DIR/${SCRIPT_NAME}.XXXXXXXXXX") || {
        _sfu_error "Failed to create temp file"
        return 1
    }

    if printf '%s' "$content" > "$temp_file"; then
        if ! chmod "$perms" "$temp_file" 2>/dev/null; then
            _sfu_error "Failed to set permissions $perms"
            rm -f "$temp_file" 2>/dev/null || true
            return 1
        fi

        if [[ -w "$target_dir" ]] || [[ -w "$target" ]]; then
            if mv "$temp_file" "$target"; then
                return 0
            else
                _sfu_error "Failed to move temp file to target"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            fi
        else
            local mv_cmd
            mv_cmd="$(command -v mv)" || {
                _sfu_error "mv command not found"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            }
            if sudo "$mv_cmd" "$temp_file" "$target"; then
                return 0
            else
                _sfu_error "Failed to move temp file (sudo required)"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            fi
        fi
    else
        _sfu_error "Failed to write content to temp file"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
}

# Append content to file atomically
#
# Usage: sfu_append_file "content" "/path/to/target"
# Returns: 0 on success, 1 on error
#
sfu_append_file() {
    local content="${1-}"
    local target="${2-}"

    [[ -n "$content" ]] || { _sfu_error "Content cannot be empty"; return 1; }
    [[ -n "$target" ]] || { _sfu_error "Target path cannot be empty"; return 1; }

    local target_dir
    target_dir="$(dirname "$target")"
    [[ -d "$target_dir" ]] || {
        _sfu_error "Target directory '$target_dir' does not exist"
        return 1
    }

    _sfu_init_temp
    local temp_file
    temp_file=$(mktemp "$SECURE_TEMP_DIR/${SCRIPT_NAME}.XXXXXXXXXX") || {
        _sfu_error "Failed to create temp file"
        return 1
    }

    if [[ -f "$target" ]]; then
        if ! cp "$target" "$temp_file"; then
            _sfu_error "Failed to copy existing file"
            return 1
        fi
    fi

    if printf '%s\n' "$content" >> "$temp_file"; then
        if [[ -w "$target_dir" ]]; then
            if mv "$temp_file" "$target"; then
                return 0
            else
                _sfu_error "Failed to move temp file to target"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            fi
        else
            local mv_cmd
            mv_cmd="$(command -v mv)" || {
                _sfu_error "mv command not found"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            }
            if sudo "$mv_cmd" "$temp_file" "$target"; then
                return 0
            else
                _sfu_error "Failed to move temp file (sudo required)"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            fi
        fi
    else
        _sfu_error "Failed to append content"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
}

# Append single line (reversed parameter order for convenience)
#
# Usage: sfu_append_line "/path/to/file" "content"
#
sfu_append_line() {
    local target="${1-}"
    local content="${2-}"

    [[ -n "$target" ]] || { _sfu_error "Target path cannot be empty"; return 1; }
    [[ -n "$content" ]] || { _sfu_error "Content cannot be empty"; return 1; }

    sfu_append_file "$content" "$target"
}

# Validate path safety - prevents directory traversal attacks
#
# Usage: sfu_validate_path "/path/to/check" "/allowed/base/path"
# Returns: 0 if safe, 1 if unsafe
#
sfu_validate_path() {
    local target_path="$1"
    local allowed_base="${2:-/}"

    command -v realpath >/dev/null || {
        _sfu_error "realpath command not found (install coreutils)"
        return 1
    }

    local resolved_target
    local resolved_base

    resolved_target="$(realpath -m "$target_path" 2>/dev/null)" || {
        _sfu_error "Cannot resolve target path '$target_path'"
        return 1
    }

    resolved_base="$(realpath -m "$allowed_base" 2>/dev/null)" || {
        _sfu_error "Cannot resolve base path '$allowed_base'"
        return 1
    }

    # Boundary-safe check: exact match OR subdirectory
    case "$resolved_target" in
        "$resolved_base" | "$resolved_base"/*) return 0 ;;
        *)
            _sfu_error "Path '$target_path' is outside allowed base '$allowed_base'"
            return 1
            ;;
    esac
}

# Setup working directory protection with cleanup trap
#
# Usage: sfu_setup_wd_protection (call at script start)
#
# Warning: Overwrites existing EXIT/INT/TERM traps
#
sfu_setup_wd_protection() {
    # shellcheck disable=SC2155
    ORIGINAL_PWD="$(pwd)"
    readonly ORIGINAL_PWD

    # shellcheck disable=SC2155
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[1]}")")" && pwd)"
    readonly SCRIPT_DIR

    trap 'sfu_cleanup_wd_protection' EXIT INT TERM

    export ORIGINAL_PWD SCRIPT_DIR
    return 0
}

# Cleanup working directory protection
sfu_cleanup_wd_protection() {
    if [[ -n "${ORIGINAL_PWD:-}" ]]; then
        cd "$ORIGINAL_PWD" 2>/dev/null || true
    fi

    if [[ -d "$SECURE_TEMP_DIR" ]]; then
        find "$SECURE_TEMP_DIR" -name "${SCRIPT_NAME}.*" -type f -delete 2>/dev/null || true

        # Only age-cleanup in /tmp mode (not StateDirectory)
        if [[ -z "${STATE_DIRECTORY:-}" ]]; then
            find "$SECURE_TEMP_DIR" -type f -mmin +60 -delete 2>/dev/null || true
        fi
    fi
    return 0
}

# Write heredoc content to file
#
# Usage:
#   sfu_heredoc "/path/to/file" <<'EOF'
#   content here
#   EOF
#
#   sfu_heredoc --append "/path/to/file" <<'EOF'
#   appended content
#   EOF
#
sfu_heredoc() {
    local target=""
    local mode="write"

    if [[ "$1" == "--append" ]]; then
        mode="append"
        target="$2"
    else
        target="$1"
    fi

    [[ -n "$target" ]] || {
        _sfu_error "Target path cannot be empty"
        echo "Usage: sfu_heredoc [--append] <target_file> <<'MARKER'" >&2
        return 1
    }

    local content
    if ! content="$(cat)"; then
        _sfu_error "Failed to read stdin content"
        return 1
    fi

    case "$mode" in
        write)  sfu_write_file "$content" "$target" ;;
        append) sfu_append_file "$content" "$target" ;;
        *)      _sfu_error "Invalid mode '$mode'"; return 1 ;;
    esac
}

# ============================================================================
# TEST SUITE
# ============================================================================

_sfu_test() {
    local test_dir="/tmp/secure-utils-test"
    local test_file="$test_dir/test.txt"
    local test_content="Test content with \$SHELL and \$(whoami) variables"

    echo "Testing secure file utilities..."

    mkdir -p "$test_dir"

    # Test sfu_write_file
    if sfu_write_file "$test_content" "$test_file"; then
        if [[ "$(cat "$test_file")" == "$test_content" ]]; then
            echo "✅ sfu_write_file: passed"
        else
            echo "❌ sfu_write_file: content mismatch"
            return 1
        fi
    else
        echo "❌ sfu_write_file: write error"
        return 1
    fi

    # Test sfu_append_file
    if sfu_append_file "Appended line" "$test_file"; then
        if grep -q "Appended line" "$test_file"; then
            echo "✅ sfu_append_file: passed"
        else
            echo "❌ sfu_append_file: content not appended"
            return 1
        fi
    else
        echo "❌ sfu_append_file: append error"
        return 1
    fi

    # Test path validation
    if sfu_validate_path "$test_file" "/tmp"; then
        echo "✅ sfu_validate_path: passed"
    else
        echo "❌ sfu_validate_path: failed"
        return 1
    fi

    # Test boundary check
    if sfu_validate_path "/tmpX/evil" "/tmp" 2>/dev/null; then
        echo "❌ sfu_validate_path boundary: security bug (/tmpX matched /tmp)"
        return 1
    else
        echo "✅ sfu_validate_path boundary: passed"
    fi

    # Test heredoc
    local heredoc_file="$test_dir/heredoc.txt"
    if sfu_heredoc "$heredoc_file" <<'EOF'
Line with $SHELL
EOF
    then
        if grep -q '\$SHELL' "$heredoc_file"; then
            echo "✅ sfu_heredoc: passed"
        else
            echo "❌ sfu_heredoc: variable was substituted"
            return 1
        fi
    else
        echo "❌ sfu_heredoc: write failed"
        return 1
    fi

    rm -rf "$test_dir"
    echo "✅ All tests passed"
    return 0
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _sfu_test
fi
