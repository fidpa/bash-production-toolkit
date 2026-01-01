#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Advanced Logging Library
# Version: 1.1.0 (Updated: 01.01.2026 - Feature: 6 new functions)
# Changelog v1.1.0 (01.01.2026): Feature additions from server repo v2.9.0
#   - NEW: time_function() - Function performance measurement
#   - NEW: log_debug_structured(), log_warn_structured(), log_critical_structured()
#   - NEW: extract_script_version() - Auto-extract version from script headers
#   - NEW: check_log_rotation() - Automatic size-based log rotation
#   - TOTAL: +6 functions, +74 lines, 100% generic (no internal dependencies)
# Changelog v1.0.1 (01.01.2026): Documentation + dependency improvements
# Changelog v1.0.0 (01.01.2026): Initial public release
#
# Purpose:
#   Enhanced logging with structured output, journald integration,
#   performance metrics, and log rotation for systemd-based Linux systems.
#
# Features:
#   - Multiple log levels (DEBUG, INFO, WARN, ERROR, CRITICAL)
#   - Structured logging with KEY=VALUE fields
#   - journald integration (systemd-cat, logger)
#   - JSON output format
#   - Performance metrics tracking
#   - Log rotation
#   - Prometheus metrics export
#   - Correlation IDs for distributed tracing
#
# Usage:
#   source "/path/to/logging.sh"
#   log_info "Starting operation"
#   log_error "Failed to connect"
#   log_info_structured "Event" "KEY1=value1" "KEY2=value2"
#
# Dependencies:
#   - Bash 4.0+
#   - Optional: secure-file-utils.sh (for atomic writes)
#   - Optional: systemd (for journald)
#   - Optional: uuidgen (for correlation IDs)
#
# Configuration (environment variables):
#   LOG_LEVEL        - Minimum level (default: INFO)
#   LOG_FORMAT       - Output format: standard, json, compact
#   LOG_TO_JOURNAL   - Enable journald (default: false)
#   LOG_TO_STDOUT    - Output to terminal (default: true)
#   LOG_FILE         - Custom log file path
#   LOG_DIR          - Log directory (default: /var/log)
#   LOG_ROTATE_SIZE  - Rotation size (default: 10M)
#   LOG_ROTATE_COUNT - Keep N rotated logs (default: 5)
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

# Include guard
if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly _LOGGING_LOADED="true"

# Working directory protection
# shellcheck disable=SC2155
ORIGINAL_PWD="$(pwd)"
readonly ORIGINAL_PWD

# shellcheck disable=SC2155
_LOGGING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly _LOGGING_LIB_DIR

trap 'cd "$ORIGINAL_PWD" 2>/dev/null || true' INT TERM

# Load secure file utilities if available
if [[ -f "${_LOGGING_LIB_DIR}/secure-file-utils.sh" ]]; then
    # shellcheck source=./secure-file-utils.sh
    source "${_LOGGING_LIB_DIR}/secure-file-utils.sh"
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=4

# Defaults
: "${LOG_LEVEL:=INFO}"
: "${LOG_FORMAT:=standard}"
: "${LOG_TO_JOURNAL:=false}"
: "${LOG_TO_STDOUT:=true}"
: "${LOG_ROTATE_SIZE:=10M}"
: "${LOG_ROTATE_COUNT:=5}"
: "${LOG_DIR:=/var/log}"

# Convert log level string to numeric
get_log_level_value() {
    local level="${1^^}"
    case "$level" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO) echo $LOG_LEVEL_INFO ;;
        WARN|WARNING) echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        CRITICAL|CRIT) echo $LOG_LEVEL_CRITICAL ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

# shellcheck disable=SC2155
CURRENT_LOG_LEVEL=$(get_log_level_value "$LOG_LEVEL")
readonly CURRENT_LOG_LEVEL

# Performance tracking
declare -gA SCRIPT_METRICS=(
    [start_time]=$(date +%s%N)
    [log_count]=0
    [error_count]=0
    [warning_count]=0
)

# ============================================================================
# CORRELATION ID
# ============================================================================

if [[ -z "${CORRELATION_ID:-}" ]]; then
    if command -v uuidgen &>/dev/null; then
        # shellcheck disable=SC2155
        CORRELATION_ID="$(uuidgen)"
        readonly CORRELATION_ID
    else
        # shellcheck disable=SC2155
        CORRELATION_ID="$(date +%s%N)-$$"
        readonly CORRELATION_ID
    fi
    export CORRELATION_ID
else
    readonly CORRELATION_ID="${CORRELATION_ID}"
fi

# Auto-detect script info
if [[ -z "${SCRIPT_PATH:-}" ]]; then
    SCRIPT_PATH="${BASH_SOURCE[1]:-${0}}"
    readonly SCRIPT_PATH
fi

if [[ -z "${SCRIPT_NAME:-}" ]]; then
    SCRIPT_NAME="${SCRIPT_PATH##*/}"
    SCRIPT_NAME="${SCRIPT_NAME%.sh}"
fi

# ============================================================================
# JSON UTILITIES
# ============================================================================

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# ============================================================================
# JOURNALD INTEGRATION
# ============================================================================

log_to_journald_modern() {
    local level="$1"
    local message="$2"
    local priority_prefix

    case "$level" in
        DEBUG)    priority_prefix="<7>" ;;
        INFO)     priority_prefix="<6>" ;;
        WARN)     priority_prefix="<4>" ;;
        ERROR)    priority_prefix="<3>" ;;
        CRITICAL) priority_prefix="<2>" ;;
        *)        priority_prefix="<6>" ;;
    esac

    if command -v systemd-cat &>/dev/null; then
        echo "${priority_prefix}${message}" | systemd-cat -t "${SCRIPT_NAME:-script}"
        return 0
    fi
    return 1
}

log_to_journald_structured() {
    local level="$1"
    shift
    local message="$1"
    shift
    local fields=("$@")

    local priority
    case "$level" in
        DEBUG)    priority="debug" ;;
        INFO)     priority="info" ;;
        WARN)     priority="warning" ;;
        ERROR)    priority="err" ;;
        CRITICAL) priority="crit" ;;
        *)        priority="info" ;;
    esac

    if command -v logger &>/dev/null; then
        local logger_args=(
            "--journald"
            "MESSAGE=${message}"
            "SYSLOG_IDENTIFIER=${SCRIPT_NAME:-script}"
            "PRIORITY=${priority}"
            "CORRELATION_ID=${CORRELATION_ID}"
        )

        for field in "${fields[@]}"; do
            if [[ "$field" =~ ^[A-Z_][A-Z0-9_]*=.+$ ]]; then
                logger_args+=("$field")
            fi
        done

        logger "${logger_args[@]}" </dev/null 2>/dev/null
        return 0
    fi

    log_to_journald_modern "$level" "$message"
}

log_to_journald_legacy() {
    local level="$1"
    local message="$2"
    local priority

    case "$level" in
        DEBUG)    priority="debug" ;;
        INFO)     priority="info" ;;
        WARN)     priority="warning" ;;
        ERROR)    priority="err" ;;
        CRITICAL) priority="crit" ;;
        *)        priority="info" ;;
    esac

    if command -v logger &>/dev/null; then
        logger -t "${SCRIPT_NAME:-script}" -p "daemon.$priority" "$message"
        return 0
    fi
    return 1
}

# ============================================================================
# FILE LOGGING
# ============================================================================

log_to_file() {
    local level="$1"
    local message="$2"
    local log_file="${LOG_FILE:-${LOG_DIR}/script.log}"

    local log_dir
    log_dir=$(dirname "$log_file")
    [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir" 2>/dev/null

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if command -v sfu_append_file &>/dev/null; then
        sfu_append_file "[$timestamp] [$level] $message" "$log_file" 2>/dev/null || true
    else
        echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
    fi
}

log_with_fallback() {
    local level="$1"
    shift
    local message="$*"

    if [[ "$LOG_TO_JOURNAL" == "true" ]]; then
        log_to_journald_modern "$level" "$message" || \
        log_to_journald_legacy "$level" "$message" || true
    fi

    log_to_file "$level" "$message"

    if [[ "${LOG_TO_STDOUT:-true}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] [$level] $message"
    fi
}

# ============================================================================
# JSON LOGGING
# ============================================================================

log_json() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds)
    local hostname
    hostname=$(hostname)

    local escaped_message
    escaped_message=$(json_escape "$message")

    local json_log
    json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_message\",\"hostname\":\"$hostname\",\"script\":\"${SCRIPT_NAME:-unknown}\",\"pid\":$$}"

    if [[ "${LOG_TO_STDOUT:-true}" == "true" ]]; then
        echo "$json_log"
    fi

    if command -v sfu_append_file &>/dev/null; then
        sfu_append_file "$json_log" "${LOG_FILE:-${LOG_DIR}/script.json}" 2>/dev/null || true
    fi
}

# ============================================================================
# STRUCTURED LOGGING
# ============================================================================

log_structured() {
    local level="$1"
    shift
    local message="$1"
    shift

    local level_value
    level_value=$(get_log_level_value "$level")
    if [[ $level_value -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi

    ((SCRIPT_METRICS[log_count]++)) || true
    case "$level" in
        ERROR|CRITICAL) ((SCRIPT_METRICS[error_count]++)) || true ;;
        WARN|WARNING) ((SCRIPT_METRICS[warning_count]++)) || true ;;
    esac

    local context=""
    while [[ $# -gt 0 ]]; do
        context="$context $1"
        shift
    done

    case "$LOG_FORMAT" in
        json)   log_json "$level" "$message" $context ;;
        compact)
            local timestamp
            timestamp=$(date '+%H:%M:%S')
            echo "[$timestamp] $level: $message $context"
            ;;
        *)      log_with_fallback "$level" "$message $context" ;;
    esac
}

# Structured logging with journald fields
log_info_structured() {
    local message="$1"
    shift
    local fields=("$@")

    if [[ $LOG_LEVEL_INFO -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi

    ((SCRIPT_METRICS[log_count]++)) || true

    if [[ "$LOG_TO_JOURNAL" == "true" ]]; then
        log_to_journald_structured "INFO" "$message" "${fields[@]}"
    fi

    log_to_file "INFO" "$message [${fields[*]}]"

    if [[ "${LOG_TO_STDOUT:-true}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] [INFO] $message [${fields[*]}]"
    fi
}

log_error_structured() {
    local message="$1"
    shift
    local fields=("$@")

    ((SCRIPT_METRICS[log_count]++)) || true
    ((SCRIPT_METRICS[error_count]++)) || true

    if [[ "$LOG_TO_JOURNAL" == "true" ]]; then
        log_to_journald_structured "ERROR" "$message" "${fields[@]}"
    fi

    log_to_file "ERROR" "$message [${fields[*]}]"

    if [[ "${LOG_TO_STDOUT:-true}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] [ERROR] $message [${fields[*]}]" >&2
    fi
}

# ============================================================================
# PERFORMANCE LOGGING
# ============================================================================

log_performance() {
    local end_time
    end_time=$(date +%s%N)
    local start_time=${SCRIPT_METRICS[start_time]}
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    local duration_s=$((duration_ms / 1000))

    local perf_msg="Script completed | Duration: ${duration_s}s (${duration_ms}ms)"
    perf_msg="$perf_msg | Logs: ${SCRIPT_METRICS[log_count]}"
    perf_msg="$perf_msg | Errors: ${SCRIPT_METRICS[error_count]}"
    perf_msg="$perf_msg | Warnings: ${SCRIPT_METRICS[warning_count]}"

    local old_stdout="${LOG_TO_STDOUT}"
    LOG_TO_STDOUT=false
    log_structured "INFO" "$perf_msg"
    LOG_TO_STDOUT="$old_stdout"
}

# ============================================================================
# LOG ROTATION
# ============================================================================

rotate_log() {
    local log_file="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local rotated_file="${log_file}.${timestamp}"

    if [[ ! -w "$(dirname "$log_file")" ]]; then
        return 1
    fi

    mv "$log_file" "$rotated_file" 2>/dev/null || return 1

    if command -v gzip &>/dev/null; then
        gzip "$rotated_file" 2>/dev/null && rotated_file="${rotated_file}.gz"
    fi

    # Remove old logs
    local log_dir log_base count=0
    log_dir=$(dirname "$log_file")
    log_base=$(basename "$log_file")

    while IFS= read -r -d '' old_log; do
        ((count++)) || true
        if [[ $count -gt $LOG_ROTATE_COUNT ]]; then
            rm -f "$old_log" 2>/dev/null || true
        fi
    done < <(find "$log_dir" -name "${log_base}.*" -type f -print0 2>/dev/null | sort -rz)
}

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

log_debug() { log_structured "DEBUG" "$@"; }
log_info() { log_structured "INFO" "$@"; }
log_success() { log_structured "INFO" "$@"; }
log_warn() { log_structured "WARN" "$@"; }
log_error() { log_structured "ERROR" "$@"; }
log_critical() { log_structured "CRITICAL" "$@"; }

# Generic log function
log() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    if [[ "$1" =~ ^(DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL)$ ]]; then
        log_structured "$@"
    else
        log_structured "INFO" "$@"
    fi
}

# Aliases
info() { log_info "$@"; }
warn() { log_warn "$@"; }
warning() { log_warn "$@"; }
error() { log_error "$@"; }
debug() { log_debug "$@"; }
critical() { log_critical "$@"; }
success() { log_info "✓ $*"; }
failure() { log_error "✗ $*"; }

# ============================================================================
# INITIALIZATION
# ============================================================================

if [[ "${LOG_PERFORMANCE:-true}" == "true" ]]; then
    trap 'ret=$?; log_performance || true; cd "$ORIGINAL_PWD" 2>/dev/null || true; exit "$ret"' EXIT
else
    trap 'cd "$ORIGINAL_PWD" 2>/dev/null || true' EXIT
fi

# Export functions

# ============================================================================
# ADDITIONAL FUNCTIONS (v1.1.0)
# ============================================================================

# ============================================================================
# ADDITIONAL FUNCTIONS FOR bash-production-toolkit v1.1.0
# Ported from server repo logging.sh v2.9.0
# ============================================================================

# Log function execution time
time_function() {
    local func_name="$1"
    shift

    local start
    start=$(date +%s%N)
    "$func_name" "$@"
    local result=$?
    local end
    end=$(date +%s%N)

    local duration_ms
    duration_ms=$(( (end - start) / 1000000 ))
    log_structured "DEBUG" "Function execution" "function=$func_name" "duration_ms=$duration_ms" "exit_code=$result"

    return $result
}

# Structured logging variants (missing in v1.0.0)
log_debug_structured() {
    log_structured "DEBUG" "$@"
}

log_warn_structured() {
    log_structured "WARN" "$@"
}

log_critical_structured() {
    log_structured "CRITICAL" "$@"
}

# Extract script version from file header
extract_script_version() {
    local script_file="${1:-${SCRIPT_PATH}}"
    if [[ -f "$script_file" ]]; then
        # Search for "Version: X.Y.Z" or "# Version: X.Y.Z" in first 50 lines
        grep -m1 -oP '(?i)(?:^#\s*)?version:\s*\K[\d.]+' "$script_file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
    return 0
}

# Check and rotate log file based on size
check_log_rotation() {
    local log_file="${1:-${LOG_FILE:-${DEFAULT_LOG_DIR}/script.log}}"

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    local size
    size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    local max_size_bytes

    # Convert human-readable size to bytes
    case "${LOG_ROTATE_SIZE: -1}" in
        K) max_size_bytes=$(( ${LOG_ROTATE_SIZE%K} * 1024 )) ;;
        M) max_size_bytes=$(( ${LOG_ROTATE_SIZE%M} * 1024 * 1024 )) ;;
        G) max_size_bytes=$(( ${LOG_ROTATE_SIZE%G} * 1024 * 1024 * 1024 )) ;;
        *) max_size_bytes=$LOG_ROTATE_SIZE ;;
    esac

    if [[ $size -gt $max_size_bytes ]]; then
        rotate_log "$log_file"
    fi
    return 0
}

export -f log_structured log_json log_debug log_info log_warn log_error log_critical time_function check_log_rotation extract_script_version
export -f log_with_fallback log_to_file log_debug_structured log_warn_structured log_critical_structured
export -f log info warn warning error debug critical success failure
