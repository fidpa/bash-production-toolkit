#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Simple Logging Library
# Version: 1.0.0
#
# Purpose:
#   Lightweight logging for hooks and automated tasks with file + terminal output.
#   Cross-platform compatible (Linux, macOS).
#
# Features:
#   - Hybrid logging (terminal + file + syslog)
#   - 5 log levels (DEBUG, INFO, SUCCESS, WARN, ERROR)
#   - Emoji icons for visual feedback
#   - Configurable via environment variables
#   - Include guard (single-load protection)
#
# Usage:
#   source "/path/to/simple-logging.sh"
#   log_info "Processing file"
#   log_success "Task completed"
#   log_error "Connection failed"
#   log_warn "Deprecated API used"
#   log_debug "Variable X=$X"
#
# Dependencies:
#   - Bash 4.0+
#   - secure-file-utils.sh (for atomic log writes)
#   - logger (syslog, optional)
#
# Configuration (environment variables, set before sourcing):
#   SCRIPT_NAME - Script name for logging (default: basename)
#   LOG_FILE    - Log file path (default: ~/.cache/bash-toolkit/${SCRIPT_NAME}.log)
#   LOG_TAG     - Tag for logger command (default: ${SCRIPT_NAME})
#   LOG_LEVEL   - Minimum log level (default: INFO, options: DEBUG|INFO|WARN|ERROR)
#
# When to use:
#   - Hooks (background execution)
#   - Automated tasks with file logging
#   - Cross-platform scripts (Linux + macOS)
#
# For systemd services, use logging.sh instead (journald integration).
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

set -uo pipefail  # No -e: Explicit error handling

# ============================================================================
# DEPENDENCIES
# ============================================================================

SIMPLE_LOGGING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SIMPLE_LOGGING_LIB_DIR}/secure-file-utils.sh" ]]; then
    # shellcheck source=./secure-file-utils.sh
    source "${SIMPLE_LOGGING_LIB_DIR}/secure-file-utils.sh"
else
    echo "ERROR: secure-file-utils.sh not found" >&2
    return 1 2>/dev/null || exit 1
fi

# ============================================================================
# INCLUDE GUARD
# ============================================================================

if [[ "${_SIMPLE_LOGGING_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly _SIMPLE_LOGGING_LOADED="true"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Script name: use existing value if set, otherwise derive from $0
if [[ -z "${SCRIPT_NAME:-}" ]]; then
    readonly SCRIPT_NAME="$(basename "$0" .sh)"
fi

# Log tag and level
: "${LOG_TAG:=${SCRIPT_NAME}}"
: "${LOG_LEVEL:=INFO}"
readonly LOG_TAG LOG_LEVEL

# Log file with fallback
LOG_FILE_CANDIDATE="${LOG_FILE:-${HOME}/.cache/bash-toolkit/${SCRIPT_NAME}.log}"
LOG_DIR_CANDIDATE="$(dirname "${LOG_FILE_CANDIDATE}")"

if [[ ! -d "${LOG_DIR_CANDIDATE}" ]]; then
    mkdir -p "${LOG_DIR_CANDIDATE}" 2>/dev/null || {
        echo "Warning: Cannot create log directory ${LOG_DIR_CANDIDATE}" >&2
        LOG_FILE_CANDIDATE="/tmp/${SCRIPT_NAME}.log"
        LOG_DIR_CANDIDATE="/tmp"
    }
fi

readonly LOG_FILE="${LOG_FILE_CANDIDATE}"
readonly LOG_DIR="${LOG_DIR_CANDIDATE}"

# Secure permissions for log file
if [[ -f "${LOG_FILE}" ]]; then
    chmod 600 "${LOG_FILE}" 2>/dev/null || true
fi

# ============================================================================
# LOG LEVEL FILTERING
# ============================================================================

# Log levels: DEBUG(0) < INFO(1) < WARN(2) < ERROR(3)
get_log_level_value() {
    local level="$1"
    case "$level" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

CURRENT_LEVEL=$(get_log_level_value "$LOG_LEVEL")
readonly CURRENT_LEVEL

should_log() {
    local level="${1:-INFO}"
    local level_value
    level_value=$(get_log_level_value "$level") || return 2

    [[ $level_value -ge $CURRENT_LEVEL ]]
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    should_log "INFO" || return 0

    local message="$*"
    [[ -z "$message" ]] && { echo "Warning: log_info called without message" >&2; return 1; }

    echo "ℹ️  ${message}"

    sfu_append_line "${LOG_FILE}" "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${message}" || {
        echo "Warning: Failed to write to log file" >&2
        return 1
    }

    logger -t "${LOG_TAG}" "${message}" 2>/dev/null || true
    return 0
}

log_success() {
    should_log "INFO" || return 0

    local message="$*"
    [[ -z "$message" ]] && { echo "Warning: log_success called without message" >&2; return 1; }

    echo "✅ ${message}"

    sfu_append_line "${LOG_FILE}" "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] ${message}" || {
        echo "Warning: Failed to write to log file" >&2
        return 1
    }

    logger -t "${LOG_TAG}" "${message}" 2>/dev/null || true
    return 0
}

log_error() {
    should_log "ERROR" || return 0

    local message="$*"
    [[ -z "$message" ]] && { echo "Warning: log_error called without message" >&2; return 1; }

    echo "❌ ${message}" >&2

    sfu_append_line "${LOG_FILE}" "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" || {
        echo "Warning: Failed to write to log file" >&2
        return 1
    }

    logger -t "${LOG_TAG}" -p user.error "${message}" 2>/dev/null || true
    return 0
}

log_warn() {
    should_log "WARN" || return 0

    local message="$*"
    [[ -z "$message" ]] && { echo "Warning: log_warn called without message" >&2; return 1; }

    echo "⚠️  ${message}" >&2

    sfu_append_line "${LOG_FILE}" "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${message}" || {
        echo "Warning: Failed to write to log file" >&2
        return 1
    }

    logger -t "${LOG_TAG}" -p user.warning "${message}" 2>/dev/null || true
    return 0
}

log_debug() {
    should_log "DEBUG" || return 0

    local message="$*"
    [[ -z "$message" ]] && { echo "Warning: log_debug called without message" >&2; return 1; }

    echo "🔍 [DEBUG] ${message}"

    sfu_append_line "${LOG_FILE}" "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] ${message}" || {
        echo "Warning: Failed to write to log file" >&2
        return 1
    }

    logger -t "${LOG_TAG}" "DEBUG: ${message}" 2>/dev/null || true
    return 0
}

# ============================================================================
# LIBRARY LOADED
# ============================================================================

if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
    log_debug "Simple Logging Library v1.0.0 loaded (LOG_FILE=${LOG_FILE})"
fi
