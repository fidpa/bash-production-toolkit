#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Smart Alerts Library
# Version: 1.0.0
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
#   - alerts.sh (for sending)
#   - secure-file-utils.sh (for atomic state file operations)
#   - logging.sh (optional)
#   - jq (required for JSON state files)
#
# Configuration (environment variables):
#   SMART_ALERT_GRACE_PERIOD     - Seconds before alerting (default: 180)
#   SMART_ALERT_RECOVERY_THRESHOLD - Minimum downtime for recovery alert (default: 300)
#   SMART_ALERT_AGGREGATION_WINDOW - Seconds to aggregate events (default: 300)
#   SMART_ALERT_STATE_DIR        - State file directory (default: /var/lib/smart-alerts)
#   SMART_ALERT_ENABLED          - Enable/disable smart alerts (default: true)
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

set -uo pipefail

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

# jq filter constants
readonly JQ_PARSE_EVENT_STATE='[.first_seen, .last_seen, .alert_sent, .message, .details] | @tsv'
readonly JQ_UPDATE_LAST_SEEN='.last_seen = ($timestamp | tonumber)'
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

if [[ -f "${_SA_LIB_DIR}/../foundation/secure-file-utils.sh" ]]; then
    source "${_SA_LIB_DIR}/../foundation/secure-file-utils.sh" 2>/dev/null || true
fi

if [[ -f "${_SA_LIB_DIR}/alerts.sh" ]]; then
    source "${_SA_LIB_DIR}/alerts.sh" 2>/dev/null || true
fi

# Fallback logging
if ! declare -F log_info >/dev/null 2>&1; then
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { :; }
    log_warn() { echo "[WARN] $*" >&2; }
fi

# ============================================================================
# INITIALIZATION
# ============================================================================

sa_init() {
    mkdir -p "${SA_EVENTS_DIR}" "${SA_PENDING_DIR}" 2>/dev/null || true

    if [[ ! -f "${SA_DOWNTIME_TRACKING}" ]]; then
        echo '{}' > "${SA_DOWNTIME_TRACKING}"
    fi

    if [[ ! -f "${SA_AGGREGATION_QUEUE}" ]]; then
        echo '[]' > "${SA_AGGREGATION_QUEUE}"
    fi
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

    local event_file="${SA_EVENTS_DIR}/${event_type}_${identifier}.json"
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
        # Update existing event
        local updated
        updated=$(jq --arg timestamp "$now" "$JQ_UPDATE_LAST_SEEN" "$event_file")
        echo "$updated" > "$event_file"
        log_debug "Event updated: $event_type/$identifier"
    else
        # Create new event
        cat > "$event_file" << EOF
{
    "event_type": "$event_type",
    "identifier": "$identifier",
    "message": "$message",
    "details": "$details",
    "first_seen": $now,
    "last_seen": $now,
    "alert_sent": false,
    "status": "pending"
}
EOF
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

    local event_file="${SA_EVENTS_DIR}/${event_type}_${identifier}.json"

    if [[ -f "$event_file" ]]; then
        local first_seen alert_sent
        first_seen=$(jq -r '.first_seen' "$event_file")
        alert_sent=$(jq -r '.alert_sent' "$event_file")

        local now
        now=$(date +%s)
        local downtime=$((now - first_seen))

        # Only send recovery if alert was sent AND downtime > threshold
        if [[ "$alert_sent" == "true" ]] && [[ $downtime -ge $SA_RECOVERY_THRESHOLD ]]; then
            if declare -F send_recovery_alert &>/dev/null; then
                send_recovery_alert "$event_type" "$identifier" "$recovery_message (downtime: ${downtime}s)"
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

    if declare -F send_telegram_alert &>/dev/null; then
        send_telegram_alert "${event_type}_${identifier}" "🚨 CRITICAL: $message" "🚨"
    else
        log_error "CRITICAL: $message"
    fi

    # Mark as alerted
    local event_file="${SA_EVENTS_DIR}/${event_type}_${identifier}.json"
    if [[ -f "$event_file" ]]; then
        local updated
        updated=$(jq "$JQ_MARK_ALERTED" "$event_file")
        echo "$updated" > "$event_file"
    fi
}

_sa_send_pending_alert() {
    local event_type="$1"
    local identifier="$2"
    local message="$3"
    local event_file="$4"

    log_info "Sending pending alert: $event_type/$identifier"

    if declare -F send_smart_alert &>/dev/null; then
        send_smart_alert "$event_type" "$identifier" "$message"
    else
        log_warn "Alert: $message"
    fi

    # Mark as alerted
    local updated
    updated=$(jq "$JQ_MARK_ALERTED" "$event_file")
    echo "$updated" > "$event_file"
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Smart Alerts Library v1.0.0"
    echo ""
    echo "Configuration:"
    echo "  SMART_ALERT_GRACE_PERIOD     = ${SA_GRACE_PERIOD}s"
    echo "  SMART_ALERT_RECOVERY_THRESHOLD = ${SA_RECOVERY_THRESHOLD}s"
    echo "  SMART_ALERT_AGGREGATION_WINDOW = ${SA_AGGREGATION_WINDOW}s"
    echo "  SMART_ALERT_STATE_DIR        = ${SA_STATE_DIR}"
    echo "  SMART_ALERT_ENABLED          = ${SA_ENABLED}"
    echo ""
    echo "Available functions:"
    echo "  - sa_register_event(type, identifier, message, [details])"
    echo "  - sa_check_pending_alerts()"
    echo "  - sa_register_recovery(type, identifier, [message])"
fi
