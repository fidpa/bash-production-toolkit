#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Path Calculator Library
# Version: 1.0.0
#
# Purpose:
#   Utilities for path manipulation in documentation and file management:
#   - Relative path calculation between files
#   - Path validation and existence checks
#   - Depth-aware path manipulation
#
# Usage:
#   source "/path/to/path-calculator.sh"
#   rel_path=$(calculate_relative_path "/docs/a/file.md" "/docs/b/other.md")
#   validate_path_exists "/path/to/file" "file"
#
# Dependencies:
#   - Bash 4.0+
#   - coreutils (realpath)
#   - Optional: logging.sh (falls back to simple echo)
#
# Configuration:
#   VERBOSE        - Enable debug output (default: false)
#   PROJECT_ROOT   - Project root for relative path calculation
#   PC_DISABLE_LOGGING - Disable logging.sh integration
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

# Include guard
[[ -n "${PATH_CALCULATOR_LOADED:-}" ]] && return 0
readonly PATH_CALCULATOR_LOADED=true

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Optional: Use logging.sh if available
if [[ -f "${BASH_SOURCE[0]%/*}/../foundation/logging.sh" ]] && [[ -z "${PC_DISABLE_LOGGING:-}" ]]; then
    source "${BASH_SOURCE[0]%/*}/../foundation/logging.sh" 2>/dev/null || true
    readonly PC_HAS_LOGGING=true
else
    readonly PC_HAS_LOGGING=false
    pc_log_debug() { [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $*" >&2; }
    pc_log_error() { echo "[ERROR] $*" >&2; }
fi

# ============================================================================
# PUBLIC API
# ============================================================================

# Calculate relative path from source file to target file
#
# Args:
#   $1 - Source file path (absolute or relative)
#   $2 - Target file path (absolute or relative)
#
# Returns:
#   Relative path from source to target
#   Exit code 0 on success, 1 on error
#
# Example:
#   calculate_relative_path "/docs/how-to/guide.md" "/docs/reference/api.md"
#   # Output: ../reference/api.md
#
calculate_relative_path() {
    local source="$1"
    local target="$2"

    if [[ -z "$source" ]] || [[ -z "$target" ]]; then
        pc_log_error "calculate_relative_path: source and target required"
        return 1
    fi

    # Ensure absolute paths
    if [[ "$source" != /* ]]; then
        source="$(realpath -m "$source" 2>/dev/null)" || {
            pc_log_error "Cannot resolve source path: $1"
            return 1
        }
    fi

    if [[ "$target" != /* ]]; then
        target="$(realpath -m "$target" 2>/dev/null)" || {
            pc_log_error "Cannot resolve target path: $2"
            return 1
        }
    fi

    local source_dir
    source_dir="$(dirname "$source")"

    local rel_path
    rel_path=$(realpath -m --relative-to="$source_dir" "$target" 2>/dev/null) || {
        pc_log_error "Failed to calculate relative path"
        return 1
    }

    pc_log_debug "Calculated: $source → $target = $rel_path"
    echo "$rel_path"
    return 0
}

# Validate that a path exists and is accessible
#
# Args:
#   $1 - Path to validate
#   $2 - Expected type: "file", "dir", or "any" (default: any)
#
# Returns:
#   Exit code 0 if valid, 1 otherwise
#
validate_path_exists() {
    local path="$1"
    local expected_type="${2:-any}"

    if [[ -z "$path" ]]; then
        pc_log_error "validate_path_exists: path required"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        pc_log_debug "Path does not exist: $path"
        return 1
    fi

    case "$expected_type" in
        file)
            [[ -f "$path" ]] || { pc_log_debug "Not a file: $path"; return 1; }
            ;;
        dir)
            [[ -d "$path" ]] || { pc_log_debug "Not a directory: $path"; return 1; }
            [[ -r "$path" && -x "$path" ]] || { pc_log_debug "Directory not accessible: $path"; return 1; }
            ;;
        any)
            ;;
        *)
            pc_log_error "Invalid expected_type: $expected_type"
            return 1
            ;;
    esac

    [[ -r "$path" ]] || { pc_log_debug "Not readable: $path"; return 1; }

    pc_log_debug "Path validated: $path"
    return 0
}

# Normalize markdown path (ensure .md extension, handle anchors)
#
# Args:
#   $1 - Markdown path (may or may not have .md extension)
#
# Returns:
#   Normalized path (with .md, without anchor)
#   Anchor part (if present) to stderr
#
normalize_markdown_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        pc_log_error "normalize_markdown_path: path required"
        return 1
    fi

    local base_path="$path"
    local anchor=""

    # Extract anchor if present
    if [[ "$path" == *"#"* ]]; then
        base_path="${path%%#*}"
        anchor="${path#*#}"
        pc_log_debug "Extracted anchor: #$anchor"
        echo "$anchor" >&2
    fi

    # Add .md extension if missing
    if [[ "$base_path" != *.md ]] && [[ "$base_path" != */ ]]; then
        base_path="${base_path}.md"
    fi

    echo "$base_path"
    return 0
}

# Calculate path depth (number of directory components)
#
# Args:
#   $1 - Path to analyze
#
# Returns:
#   Depth as integer (0 for root, 1 for single dir, etc.)
#
calculate_path_depth() {
    local path="$1"

    [[ -z "$path" ]] && { pc_log_error "calculate_path_depth: path required"; return 1; }

    # Normalize: remove leading/trailing slashes
    path="${path#/}"
    path="${path%/}"
    [[ -z "$path" ]] && { echo 0; return 0; }

    # IFS-Split for counting
    local -a parts
    IFS='/' read -r -a parts <<< "$path"

    # Depth = directory count (parts - 1 for filename)
    local n=${#parts[@]}
    (( n > 0 )) && echo $((n - 1)) || echo 0
}

# Convert absolute path to project-relative path
#
# Args:
#   $1 - Absolute path
#   $2 - Project root (default: auto-detect via .git)
#
# Returns:
#   Project-relative path (without leading /)
#
to_project_relative() {
    local abs_path="$1"
    local project_root="${2:-}"

    if [[ -z "$abs_path" ]]; then
        pc_log_error "to_project_relative: absolute path required"
        return 1
    fi

    # Auto-detect project root if not provided
    if [[ -z "$project_root" ]]; then
        if [[ -n "${PROJECT_ROOT:-}" ]]; then
            project_root="$PROJECT_ROOT"
        else
            # Search for .git directory
            local search_dir="$abs_path"
            [[ -f "$abs_path" ]] && search_dir="$(dirname "$abs_path")"
            while [[ "$search_dir" != "/" ]]; do
                if [[ -d "$search_dir/.git" ]]; then
                    project_root="$search_dir"
                    break
                fi
                search_dir="$(dirname "$search_dir")"
            done
        fi
    fi

    if [[ -z "$project_root" ]]; then
        pc_log_error "Cannot determine project root"
        return 1
    fi

    project_root="${project_root%/}"
    local rel_path="${abs_path#"$project_root"/}"

    if [[ "$rel_path" == "$abs_path" ]]; then
        pc_log_error "Path is outside project root: $abs_path"
        return 1
    fi

    echo "$rel_path"
    return 0
}

# Check if path is inside documentation directory
#
# Args:
#   $1 - Path to check
#   $2 - Docs directory (default: ${PROJECT_ROOT}/docs)
#
# Returns:
#   Exit code 0 if inside docs, 1 otherwise
#
is_docs_path() {
    local path="$1"
    local docs_dir="${2:-${PROJECT_ROOT:-}/docs}"

    if [[ -z "$path" ]]; then
        pc_log_error "is_docs_path: path required"
        return 1
    fi

    local abs_path
    abs_path="$(realpath -m "$path" 2>/dev/null)" || return 1

    local abs_docs
    abs_docs="$(realpath -m "$docs_dir" 2>/dev/null)" || return 1

    # Check exact match or subpath
    if [[ "$abs_path" == "$abs_docs" || "$abs_path" == "$abs_docs/"* ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== Path Calculator Library Self-Test ==="
    echo ""

    echo "Test 1: calculate_relative_path"
    result=$(calculate_relative_path "/docs/how-to/guide.md" "/docs/reference/api.md")
    echo "  Result: $result"
    echo "  Expected: ../reference/api.md"
    echo ""

    echo "Test 2: calculate_path_depth"
    result=$(calculate_path_depth "docs/how-to/network/failover.md")
    echo "  Result: $result"
    echo "  Expected: 3"
    echo ""

    echo "Test 3: normalize_markdown_path"
    result=$(normalize_markdown_path "README#section" 2>&1)
    echo "  Result: $result"
    echo ""

    echo "=== Self-Test Complete ==="
fi
