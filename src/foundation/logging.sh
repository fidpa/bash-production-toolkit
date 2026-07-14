#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Advanced Logging Library
# Version: 2.1.0 (Updated: 15.07.2026)
# Changelog v2.1.0 (15.07.2026): Robustness fixes (ported from server repo review)
#   - FIX: Removed INT/TERM trap - a trap without re-raise made sourcing scripts
#     SURVIVE SIGTERM/SIGINT (systemd stop then needs SIGKILL after TimeoutStopSec)
#   - FIX: Removed ORIGINAL_PWD machinery - the library only changes directory
#     in subshells, the caller's working directory never needs restoring
#   - FIX: ERROR/CRITICAL now always logged regardless of LOG_LEVEL (matches
#     log_error_structured semantics)
#   - FIX: Exported functions work in fresh child shells (get_log_level_value and
#     log_info_structured were missing from export -f; config variables exported)
#   - FIX: Zero-arg calls (log_info $empty_var) no longer kill set -u callers
#   - FIX: No trailing space in log lines when no context fields are given
#   - FIX: log_to_journald_legacy() closes stdin (prevents journald hang)
#   - NEW: Warning when loaded together with simple-logging.sh (name collision)
# Changelog v2.0.0 (24.02.2026): 6-Level Log System (RFC 5424 aligned)
#   - NEW: LOG_LEVEL_NOTICE=2 - Between INFO and WARNING (syslog-compatible)
#   - NEW: log_notice() wrapper and notice() alias
#   - NEW: log_notice_structured() - Structured logging for NOTICE level
#   - NEW: detect_environment() - prod/dev/test auto-detection
#   - CHANGED: Level values shifted: WARNING=3, ERROR=4, CRITICAL=5 (was 2/3/4)
#   - CHANGED: log_success() now deprecated alias for log_notice()
#   - IMPROVED: journald priority mapping includes NOTICE (<5>=SD_NOTICE)
#   - IMPROVED: Metrics tracking includes notice_count
# Changelog v1.2.0 (17.01.2026): Bug fixes + log_json fields support
#   - FIX: check_log_rotation() now uses LOG_DIR instead of undefined DEFAULT_LOG_DIR
#   - FEATURE: log_json() now supports additional fields (key=value pairs)
#   - DOCS: Removed unimplemented "Prometheus metrics export" claim
#   - DOCS: Clarified log rotation is manual (not automatic)
# Changelog v1.1.0 (01.01.2026): Feature additions from server repo v2.9.0
#   - NEW: time_function() - Function performance measurement
#   - NEW: log_debug_structured(), log_warning_structured(), log_critical_structured()
#   - NEW: extract_script_version() - Auto-extract version from script headers
#   - NEW: check_log_rotation() - Manual size-based log rotation
# Changelog v1.0.1 (01.01.2026): Documentation + dependency improvements
# Changelog v1.0.0 (01.01.2026): Initial public release
#
# Purpose:
#   Enhanced logging with structured output, journald integration,
#   performance metrics, and log rotation for systemd-based Linux systems.
#
# Features:
#   - 6 log levels: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL (RFC 5424 aligned)
#   - Structured logging with KEY=VALUE fields
#   - journald integration (systemd-cat, logger)
#   - JSON output format
#   - Performance metrics tracking
#   - Log rotation (manual via check_log_rotation)
#   - Correlation IDs for distributed tracing
#   - Environment auto-detection (prod/dev/test)
#
# Usage:
#   source "/path/to/logging.sh"
#   log_info "Starting operation"
#   log_notice "Service started successfully"
#   log_error "Failed to connect"
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

# Include guard
if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly _LOGGING_LOADED="true"

# simple-logging.sh defines log_* functions with different semantics - loading
# both in one shell silently redefines them (last one sourced wins)
if [[ "${_SIMPLE_LOGGING_LOADED:-}" == "true" ]]; then
    echo "WARNING: logging.sh loaded after simple-logging.sh - log_* functions are being redefined" >&2
fi

# shellcheck disable=SC2155
_LOGGING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly _LOGGING_LIB_DIR

# NOTE: No INT/TERM trap here - a trap without re-raise makes callers survive
# SIGTERM/SIGINT (systemd stop then needs SIGKILL after TimeoutStopSec). The
# library only changes directory in subshells, so nothing needs restoring.

# Load secure file utilities if available
if [[ -f "${_LOGGING_LIB_DIR}/secure-file-utils.sh" ]]; then
    # shellcheck source=./secure-file-utils.sh
    source "${_LOGGING_LIB_DIR}/secure-file-utils.sh"
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# Log levels (RFC 5424 aligned: 6 levels)
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_NOTICE=2
readonly LOG_LEVEL_WARNING=3
readonly LOG_LEVEL_ERROR=4
readonly LOG_LEVEL_CRITICAL=5

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
    local level="${1-}"
    level="${level^^}"
    case "$level" in
        DEBUG)             echo "$LOG_LEVEL_DEBUG" ;;
        INFO)              echo "$LOG_LEVEL_INFO" ;;
        NOTICE|SUCCESS)    echo "$LOG_LEVEL_NOTICE" ;;
        WARNING|WARN)      echo "$LOG_LEVEL_WARNING" ;;
        ERROR)             echo "$LOG_LEVEL_ERROR" ;;
        CRITICAL|CRIT)     echo "$LOG_LEVEL_CRITICAL" ;;
        *)                 echo "$LOG_LEVEL_INFO" ;;
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
    [notice_count]=0
)

# ============================================================================
# ENVIRONMENT DETECTION
# ============================================================================

# Auto-detect execution environment: prod, dev, or test
# Uses hostname patterns and environment variables as signals
detect_environment() {
    # Explicit override takes priority
    if [[ -n "${APP_ENV:-}" ]]; then
        echo "$APP_ENV"
        return 0
    fi

    # CI/CD environments
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
        echo "test"
        return 0
    fi

    # Hostname patterns (common conventions)
    local hostname_short
    hostname_short=$(hostname -s 2>/dev/null || echo "unknown")

    case "$hostname_short" in
        *dev*|*local*)
            echo "dev" ;;
        *test*|*staging*|*qa*)
            echo "test" ;;
        *)
            echo "prod" ;;
    esac
}

# shellcheck disable=SC2155
SCRIPT_ENV="$(detect_environment)"
readonly SCRIPT_ENV

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
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"
    printf '%s' "$str"
}

# ============================================================================
# JOURNALD INTEGRATION
# ============================================================================

log_to_journald_modern() {
    local level="$1"
    local message="$2"
    local priority_prefix

    # RFC 5424 / SD priorities
    case "$level" in
        DEBUG)    priority_prefix="<7>" ;;
        INFO)     priority_prefix="<6>" ;;
        NOTICE)   priority_prefix="<5>" ;;
        WARNING|WARN) priority_prefix="<4>" ;;
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
        NOTICE)   priority="notice" ;;
        WARNING|WARN) priority="warning" ;;
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
        NOTICE)   priority="notice" ;;
        WARNING|WARN) priority="warning" ;;
        ERROR)    priority="err" ;;
        CRITICAL) priority="crit" ;;
        *)        priority="info" ;;
    esac

    if command -v logger &>/dev/null; then
        # Close stdin to prevent journald hanging (same fix as structured variant)
        logger -t "${SCRIPT_NAME:-script}" -p "daemon.$priority" "$message" </dev/null 2>/dev/null
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
    local message="$1"
    shift

    local timestamp
    timestamp=$(date -Iseconds)
    local hostname
    hostname=$(hostname)

    local escaped_message
    escaped_message=$(json_escape "$message")

    # Parse additional fields (key=value pairs)
    local extra_fields=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == *"="* ]]; then
            local key="${1%%=*}"
            local value="${1#*=}"
            local escaped_value
            escaped_value=$(json_escape "$value")
            extra_fields="${extra_fields},\"${key}\":\"${escaped_value}\""
        fi
        shift
    done

    local json_log
    json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_message\",\"hostname\":\"$hostname\",\"script\":\"${SCRIPT_NAME:-unknown}\",\"env\":\"${SCRIPT_ENV}\",\"pid\":$$${extra_fields}}"

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
    # Defensive ${N-}: 'log_info $var' with empty unquoted var passes zero args -
    # a bare $1 would kill set -u callers (unbound variable is fatal)
    local level="${1:-INFO}"
    local message="${2-}"
    shift $(( $# >= 2 ? 2 : $# ))

    # ERROR/CRITICAL always pass, matching log_error_structured semantics
    local level_value
    level_value=$(get_log_level_value "$level")
    if [[ $level_value -lt $CURRENT_LOG_LEVEL && $level_value -lt $LOG_LEVEL_ERROR ]]; then
        return 0
    fi

    # Metrics are skipped in fresh child shells: SCRIPT_METRICS is an
    # associative array and cannot be exported - increment would be fatal there
    if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
        ((SCRIPT_METRICS[log_count]++)) || true
        case "$level" in
            ERROR|CRITICAL) ((SCRIPT_METRICS[error_count]++)) || true ;;
            WARNING|WARN)   ((SCRIPT_METRICS[warning_count]++)) || true ;;
            NOTICE)         ((SCRIPT_METRICS[notice_count]++)) || true ;;
        esac
    fi

    local context=""
    while [[ $# -gt 0 ]]; do
        context="${context:+$context }$1"
        shift
    done

    # context is intentionally word-split here (space-separated KEY=VALUE pairs);
    # ${context:+ $context} avoids a trailing space when no fields were given
    # shellcheck disable=SC2086
    case "$LOG_FORMAT" in
        json)   log_json "$level" "$message" $context ;;
        compact)
            local timestamp
            timestamp=$(date '+%H:%M:%S')
            echo "[$timestamp] $level: $message${context:+ $context}"
            ;;
        *)      log_with_fallback "$level" "$message${context:+ $context}" ;;
    esac
}

# Structured logging with journald fields
log_info_structured() {
    local message="${1-}"
    shift $(( $# > 0 ? 1 : 0 ))
    local fields=("$@")

    if [[ $LOG_LEVEL_INFO -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi

    # Metrics skipped in child shells - associative arrays are not exportable
    if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
        ((SCRIPT_METRICS[log_count]++)) || true
    fi

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

log_notice_structured() {
    local message="${1-}"
    shift $(( $# > 0 ? 1 : 0 ))
    local fields=("$@")

    if [[ $LOG_LEVEL_NOTICE -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi

    # Metrics skipped in child shells - associative arrays are not exportable
    if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
        ((SCRIPT_METRICS[log_count]++)) || true
        ((SCRIPT_METRICS[notice_count]++)) || true
    fi

    if [[ "$LOG_TO_JOURNAL" == "true" ]]; then
        log_to_journald_structured "NOTICE" "$message" "${fields[@]}"
    fi

    log_to_file "NOTICE" "$message [${fields[*]}]"

    if [[ "${LOG_TO_STDOUT:-true}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        echo "[$timestamp] [NOTICE] $message [${fields[*]}]"
    fi
}

log_error_structured() {
    local message="${1-}"
    shift $(( $# > 0 ? 1 : 0 ))
    local fields=("$@")

    # Metrics skipped in child shells - associative arrays are not exportable
    if [[ "${_LOGGING_LOADED:-}" == "true" ]]; then
        ((SCRIPT_METRICS[log_count]++)) || true
        ((SCRIPT_METRICS[error_count]++)) || true
    fi

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
    perf_msg="$perf_msg | Notices: ${SCRIPT_METRICS[notice_count]}"

    local old_stdout="${LOG_TO_STDOUT:-true}"
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

# ============================================================================
# MODULE MAP — 6 Log Levels + Structured Variants
# ============================================================================
#
# 1. PRIMARY LEVELS (RFC 5424 aligned)
#    log_debug()     DEBUG=0    Diagnostic details
#    log_info()      INFO=1     Normal operations
#    log_notice()    NOTICE=2   Significant events (service started, task complete)
#    log_warning()      WARNING=3     Warnings, degraded state
#    log_error()     ERROR=4    Errors, failed operations
#    log_critical()  CRITICAL=5 Fatal errors, immediate action required
#
# 2. STRUCTURED VARIANTS (KEY=VALUE journald fields)
#    log_info_structured()
#    log_notice_structured()
#    log_error_structured()
#    log_debug_structured()
#    log_warning_structured()
#    log_critical_structured()
#
# 3. PERFORMANCE
#    log_performance()    Script duration + metric summary
#    time_function()      Single function execution time
#
# 4. ENVIRONMENT
#    detect_environment() prod/dev/test auto-detection
#
# 5. UTILITY
#    extract_script_version()  Extract version from script header
#    check_log_rotation()      Size-based log rotation trigger
#
# ============================================================================

log_debug()    { log_structured "DEBUG"    "$@"; }
log_info()     { log_structured "INFO"     "$@"; }
log_notice()   { log_structured "NOTICE"   "$@"; }
log_warning()     { log_structured "WARNING"     "$@"; }
log_error()    { log_structured "ERROR"    "$@"; }
log_critical() { log_structured "CRITICAL" "$@"; }

# Deprecated: log_success() → use log_notice() instead
# Will be removed in v3.0.0
log_success() { log_structured "NOTICE" "$@"; }

# Generic log function
log() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    if [[ "$1" =~ ^(DEBUG|INFO|NOTICE|WARNING|WARN|ERROR|CRITICAL)$ ]]; then
        log_structured "$@"
    else
        log_structured "INFO" "$@"
    fi
}

# Aliases
info()     { log_info     "$@"; }
notice()   { log_notice   "$@"; }
warn()     { log_warning     "$@"; }
warning()  { log_warning     "$@"; }
error()    { log_error    "$@"; }
debug()    { log_debug    "$@"; }
critical() { log_critical "$@"; }
success()  { log_notice   "✓ $*"; }
failure()  { log_error    "✗ $*"; }

# ============================================================================
# INITIALIZATION
# ============================================================================

# Replaces any EXIT trap set BEFORE sourcing; a caller trap set AFTER sourcing
# replaces this one in turn (call log_performance in your own trap if wanted)
_logging_exit_handler() {
    local ret=$?
    log_performance || true
    exit "$ret"
}

if [[ "${LOG_PERFORMANCE:-true}" == "true" ]]; then
    trap '_logging_exit_handler' EXIT
fi

# ============================================================================
# ADDITIONAL FUNCTIONS
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

# Structured logging variants
log_debug_structured()    { log_structured "DEBUG"    "$@"; }
log_warning_structured()     { log_structured "WARNING"     "$@"; }
log_critical_structured() { log_structured "CRITICAL" "$@"; }

# Extract script version from file header
extract_script_version() {
    local script_file="${1:-${SCRIPT_PATH}}"
    if [[ -f "$script_file" ]]; then
        grep -m1 -oP '(?i)(?:^#\s*)?version:\s*\K[\d.]+' "$script_file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
    return 0
}

# Check and rotate log file based on size
check_log_rotation() {
    local log_file="${1:-${LOG_FILE:-${LOG_DIR}/script.log}}"

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

# Export functions for use in fresh child shells (bash -c, xargs bash, ...)
# Limitation: metrics are not tracked there (associative arrays cannot be
# exported) - child *scripts* should source the library themselves instead
export -f get_log_level_value log_structured log_json json_escape log_debug log_info log_notice log_warning log_error log_critical time_function check_log_rotation extract_script_version
export -f log_with_fallback log_to_file log_to_journald_modern log_to_journald_structured log_to_journald_legacy
export -f log_info_structured log_debug_structured log_notice_structured log_warning_structured log_error_structured log_critical_structured
export -f log info notice warn warning error debug critical success failure log_success
export -f detect_environment

# Export configuration/context consumed by the exported functions (export on
# readonly variables is legal - it only adds the attribute)
export CURRENT_LOG_LEVEL LOG_LEVEL_DEBUG LOG_LEVEL_INFO LOG_LEVEL_NOTICE LOG_LEVEL_WARNING LOG_LEVEL_ERROR LOG_LEVEL_CRITICAL
export LOG_FORMAT LOG_TO_JOURNAL LOG_TO_STDOUT LOG_DIR
export CORRELATION_ID SCRIPT_ENV
