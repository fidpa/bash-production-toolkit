#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Smart Alerts Library
# Version: 2.1.0 (Updated: 2026-07-15)
# Changelog v2.1.0 (2026-07-15): Library Flag Hygiene
#   - FIX: Removed file-scope set -uo pipefail (a sourced library must not
#     change the caller's shell options)
# Changelog v2.0.0 (24.02.2026): Aligned with alerts.sh v2.0.0 webhook backend
#   - BREAKING: Uses send_alert() instead of send_telegram_alert()
#   - BREAKING: Uses send_recovery_alert() with new signature (no send_telegram_alert)
#   - IMPROVED: _sa_send_immediate_alert() → uses send_alert() with CRITICAL suffix
#   - IMPROVED: _sa_send_pending_alert() → uses send_alert()
#   - ALIGNED: With alerts.sh v2.0.0 generic webhook backend
# Changelog v1.0.1 (2026-01-01): Dependency Loading Improvements
#   - FIX: Explicit error handling for secure-file-utils.sh dependency
#   - ADDED: Function check (declare -F sfu_write_file) before sourcing
#   - IMPROVED: Clear error messages when dependencies are missing
#   - ALIGNED: With server repo v1.1.1 best practices
# Changelog v1.0.0 (2026-01-01): Initial public release
#
# Purpose:
#   Intelligent alert management to reduce alert fatigue through
#   grace periods, event aggregation, and smart recovery alerts.
#
# Features:
#   - Grace period: Delay alerts to filter transient issues (default: 3min)
#   - Recovery suppression: Only alert if downtime > threshold (default: 5min)
#   - Event aggregation: Collect events and send summary
#   - Critical fast-track: Bypass grace period for critical events
#   - State machine: JSON-based event tracking
#
# Usage:
#   source "/path/to/smart-alerts.sh"
#   sa_register_event "service_down" "nginx" "Service nginx is not responding"
#   sa_check_pending_alerts  # Call periodically to process pending alerts
#
# Dependencies:
#   - alerts.sh v2.0.0+ (for sending via send_alert())
#   - secure-file-utils.sh (for atomic state file operations)
#   - logging.sh (optional)
#   - jq (required for JSON state files)
#
# Configuration (environment variables):
#   SMART_ALERT_GRACE_PERIOD       - Seconds before alerting (default: 180)
#   SMART_ALERT_RECOVERY_THRESHOLD - Minimum downtime for recovery alert (default: 300)
#   SMART_ALERT_AGGREGATION_WINDOW - Seconds to aggregate events (default: 300)
#   SMART_ALERT_STATE_DIR          - State file directory (default: /var/lib/smart-alerts)
#   SMART_ALERT_ENABLED            - Enable/disable smart alerts (default: true)
#   ALERT_WEBHOOK_URL              - Webhook URL (passed through to alerts.sh)

# NOTE: No set -e/-u/pipefail here - a sourced library must not change the
# caller's shell options (this file is written to be set -u clean)

# ============================================================================
# INCLUDE GUARD
# ============================================================================

[[ -n "${SMART_ALERTS_LOADED:-}" ]] && return 0
readonly SMART_ALERTS_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SA_GRACE_PERIOD="${SMART_ALERT_GRACE_PERIOD:-180}"
readonly SA_RECOVERY_THRESHOLD="${SMART_ALERT_RECOVERY_THRESHOLD:-300}"
readonly SA_AGGREGATION_WINDOW="${SMART_ALERT_AGGREGATION_WINDOW:-300}"
readonly SA_STATE_DIR="${SMART_ALERT_STATE_DIR:-/var/lib/smart-alerts}"
readonly SA_ENABLED="${SMART_ALERT_ENABLED:-true}"

# State directories
readonly SA_EVENTS_DIR="${SA_STATE_DIR}/events"
readonly SA_PENDING_DIR="${SA_STATE_DIR}/pending"
readonly SA_AGGREGATION_QUEUE="${SA_STATE_DIR}/aggregation.queue"
readonly SA_DOWNTIME_TRACKING="${SA_STATE_DIR}/downtime_tracking.json"

# Critical events that bypass grace period
readonly SA_CRITICAL_EVENTS=(
    "BOTH_WANS_DOWN"
    "SELF_HEALING_FAILED"
    "CRITICAL_SERVICE_DOWN"
)

# jq filter constants (single quotes are intentional — these are jq expressions, not bash)
# shellcheck disable=SC2016,SC2034
readonly JQ_PARSE_EVENT_STATE='[.first_seen, .last_seen, .alert_sent, .message, .details] | @tsv'
# shellcheck disable=SC2016
readonly JQ_UPDATE_LAST_SEEN='.last_seen = ($timestamp | tonumber)'
# shellcheck disable=SC2016
readonly JQ_MARK_ALERTED='.alert_sent = true | .status = "alerted"'

# ============================================================================
# DEPENDENCIES
# ============================================================================

_SA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for smart-alerts.sh" >&2
    return 1
fi

# Load dependencies
if [[ -f "${_SA_LIB_DIR}/../foundation/logging.sh" ]]; then
    source "${_SA_LIB_DIR}/../foundation/logging.sh" 2>/dev/null || true
fi

# Load secure-file-utils.sh with strict error handling (required for sfu_write_file)
if ! declare -F sfu_write_file >/dev/null 2>&1; then
    if [[ -f "${_SA_LIB_DIR}/../foundation/secure-file-utils.sh" ]]; then
        # shellcheck source=../foundation/secure-file-utils.sh
        source "${_SA_LIB_DIR}/../foundation/secure-file-utils.sh" || {
            echo "ERROR: Failed to source secure-file-utils.sh" >&2
            return 1
        }
    else
        echo "ERROR: secure-file-utils.sh not found at ${_SA_LIB_DIR}/../foundation/secure-file-utils.sh" >&2
        return 1
    fi
fi

if [[ -f "${_SA_LIB_DIR}/alerts.sh" ]]; then
    source "${_SA_LIB_DIR}/alerts.sh" 2>/dev/null || true
fi

# Fallback logging
if ! declare -F log_info >/dev/null 2>&1; then
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { :; }
    log_warning() { echo "[WARNING] $*" >&2; }
fi

# ============================================================================
# INITIALIZATION
# ============================================================================

sa_init() {
    mkdir -p "${SA_EVENTS_DIR}" "${SA_PENDING_DIR}" 2>/dev/null || true

    if [[ ! -f "${SA_DOWNTIME_TRACKING}" ]]; then
        sfu_write_file '{}' "${SA_DOWNTIME_TRACKING}"
    fi

    if [[ ! -f "${SA_AGGREGATION_QUEUE}" ]]; then
        sfu_write_file '[]' "${SA_AGGREGATION_QUEUE}"
    fi
}

# ============================================================================
# PATH SANITIZATION
# ============================================================================

# Sanitize identifier for use in file paths (prevent directory traversal)
_sa_sanitize_id() {
    local input="$1"
    printf '%s' "${input//[^a-zA-Z0-9_.-]/}"
}

# ============================================================================
# EVENT REGISTRATION
# ============================================================================

# Register an event (may or may not trigger immediate alert)
#
# Usage: sa_register_event "event_type" "identifier" "message" ["details"]
#
sa_register_event() {
    local event_type="$1"
    local identifier="$2"
    local message="$3"
    local details="${4:-}"

    [[ "${SA_ENABLED}" != "true" ]] && return 0

    sa_init

    local safe_type safe_id
    safe_type=$(_sa_sanitize_id "$event_type")
    safe_id=$(_sa_sanitize_id "$identifier")
    local event_file="${SA_EVENTS_DIR}/${safe_type}_${safe_id}.json"
    local now
    now=$(date +%s)

    # Check if this is a critical event (bypass grace period)
    local is_critical=false
    for critical in "${SA_CRITICAL_EVENTS[@]}"; do
        if [[ "$event_type" == "$critical" ]]; then
            is_critical=true
            break
        fi
    done

    if [[ -f "$event_file" ]]; then
        # Update existing event (atomic write)
        local updated
        updated=$(jq --arg timestamp "$now" "$JQ_UPDATE_LAST_SEEN" "$event_file")
        sfu_write_file "$updated" "$event_file"
        log_debug "Event updated: $event_type/$identifier"
    else
        # Create new event (jq for proper JSON escaping)
        local new_event
        new_event=$(jq -n \
            --arg event_type "$event_type" \
            --arg identifier "$identifier" \
            --arg message "$message" \
            --arg details "$details" \
            --argjson now "$now" \
            '{
                event_type: $event_type,
                identifier: $identifier,
                message: $message,
                details: $details,
                first_seen: $now,
                last_seen: $now,
                alert_sent: false,
                status: "pending"
            }')
        sfu_write_file "$new_event" "$event_file"
        log_debug "Event registered: $event_type/$identifier"

        # Critical events: immediate alert
        if [[ "$is_critical" == true ]]; then
            _sa_send_immediate_alert "$event_type" "$identifier" "$message"
        fi
    fi
}

# ============================================================================
# ALERT PROCESSING
# ============================================================================

# Check and send pending alerts (call periodically)
#
sa_check_pending_alerts() {
    [[ "${SA_ENABLED}" != "true" ]] && return 0

    sa_init

    local now
    now=$(date +%s)

    # Process all pending events
    for event_file in "${SA_EVENTS_DIR}"/*.json; do
        [[ -f "$event_file" ]] || continue

        local event_data
        event_data=$(cat "$event_file")

        local alert_sent first_seen event_type identifier message
        alert_sent=$(echo "$event_data" | jq -r '.alert_sent')
        first_seen=$(echo "$event_data" | jq -r '.first_seen')
        event_type=$(echo "$event_data" | jq -r '.event_type')
        identifier=$(echo "$event_data" | jq -r '.identifier')
        message=$(echo "$event_data" | jq -r '.message')

        # Skip if already alerted
        [[ "$alert_sent" == "true" ]] && continue

        # Check grace period
        local elapsed=$((now - first_seen))
        if [[ $elapsed -ge $SA_GRACE_PERIOD ]]; then
            _sa_send_pending_alert "$event_type" "$identifier" "$message" "$event_file"
        fi
    done
}

# Register event recovery
#
# Usage: sa_register_recovery "event_type" "identifier" "recovery_message"
#
sa_register_recovery() {
    local event_type="$1"
    local identifier="$2"
    local recovery_message="${3:-Service recovered}"

    [[ "${SA_ENABLED}" != "true" ]] && return 0

    local safe_type safe_id
    safe_type=$(_sa_sanitize_id "$event_type")
    safe_id=$(_sa_sanitize_id "$identifier")
    local event_file="${SA_EVENTS_DIR}/${safe_type}_${safe_id}.json"

    if [[ -f "$event_file" ]]; then
        local first_seen alert_sent
        first_seen=$(jq -r '.first_seen' "$event_file")
        alert_sent=$(jq -r '.alert_sent' "$event_file")

        local now
        now=$(date +%s)
        local downtime=$((now - first_seen))

        # Only send recovery if alert was sent AND downtime > threshold
        if [[ "$alert_sent" == "true" ]] && [[ $downtime -ge $SA_RECOVERY_THRESHOLD ]]; then
            if declare -F send_alert &>/dev/null; then
                send_alert "${event_type}_RECOVERED" "$recovery_message (downtime: ${downtime}s)" "✅" "[Recovery]"
            else
                log_info "Recovery: $event_type/$identifier - $recovery_message (${downtime}s)"
            fi
        fi

        # Clean up event file
        rm -f "$event_file" 2>/dev/null
        log_debug "Event cleared: $event_type/$identifier"
    fi
}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

_sa_send_immediate_alert() {
    local event_type="$1"
    local identifier="$2"
    local message="$3"

    log_info "Critical alert (immediate): $event_type/$identifier"

    if declare -F send_alert &>/dev/null; then
        send_alert "${event_type}_CRITICAL" "🚨 CRITICAL: $message" "🚨"
    else
        log_error "CRITICAL: $message"
    fi

    # Mark as alerted (sanitized path + atomic write)
    local safe_type safe_id
    safe_type=$(_sa_sanitize_id "$event_type")
    safe_id=$(_sa_sanitize_id "$identifier")
    local event_file="${SA_EVENTS_DIR}/${safe_type}_${safe_id}.json"
    if [[ -f "$event_file" ]]; then
        local updated
        updated=$(jq "$JQ_MARK_ALERTED" "$event_file")
        sfu_write_file "$updated" "$event_file"
    fi
}

_sa_send_pending_alert() {
    local event_type="$1"
    local identifier="$2"
    local message="$3"
    local event_file="$4"

    log_info "Sending pending alert: $event_type/$identifier"

    if declare -F send_alert &>/dev/null; then
        send_alert "${event_type}_${identifier}" "$message"
    else
        log_warning "Alert: $message"
    fi

    # Mark as alerted (atomic write)
    local updated
    updated=$(jq "$JQ_MARK_ALERTED" "$event_file")
    sfu_write_file "$updated" "$event_file"
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Smart Alerts Library v2.0.0"
    echo ""
    echo "Required (via alerts.sh):"
    echo "  ALERT_WEBHOOK_URL - Webhook endpoint URL"
    echo ""
    echo "Configuration:"
    echo "  SMART_ALERT_GRACE_PERIOD       = ${SA_GRACE_PERIOD}s"
    echo "  SMART_ALERT_RECOVERY_THRESHOLD = ${SA_RECOVERY_THRESHOLD}s"
    echo "  SMART_ALERT_AGGREGATION_WINDOW = ${SA_AGGREGATION_WINDOW}s"
    echo "  SMART_ALERT_STATE_DIR          = ${SA_STATE_DIR}"
    echo "  SMART_ALERT_ENABLED            = ${SA_ENABLED}"
    echo ""
    echo "Available functions:"
    echo "  - sa_register_event(type, identifier, message, [details])"
    echo "  - sa_check_pending_alerts()"
    echo "  - sa_register_recovery(type, identifier, [message])"
fi
