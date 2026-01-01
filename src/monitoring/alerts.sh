#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Alerts Library
# Version: 1.0.0
#
# Purpose:
#   Telegram alerting with rate limiting and smart deduplication
#   to reduce alert fatigue.
#
# Features:
#   - Rate-limited Telegram alerts (configurable cooldown)
#   - Smart deduplication (only alert on state changes)
#   - Recovery alerts (service restored notifications)
#   - Content hashing for duplicate detection
#
# Usage:
#   source "/path/to/alerts.sh"
#   send_telegram_alert "disk_full" "Disk usage at 95%"
#   send_smart_alert "service_down" "nginx" "Service nginx is down"
#
# Dependencies:
#   - logging.sh (optional, falls back to echo)
#   - secure-file-utils.sh (optional, for atomic writes)
#   - curl (for Telegram API)
#
# Configuration (environment variables):
#   TELEGRAM_BOT_TOKEN   - Telegram bot token (required)
#   TELEGRAM_CHAT_ID     - Telegram chat ID (required)
#   TELEGRAM_PREFIX      - Message prefix (default: [System])
#   RATE_LIMIT_SECONDS   - Cooldown between same alerts (default: 1800)
#   STATE_DIR            - Directory for state files (default: /var/lib/alerts)
#   ENABLE_RECOVERY_ALERTS - Send recovery notifications (default: true)
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

# ============================================================================
# INCLUDE GUARD
# ============================================================================

[[ -n "${MONITORING_ALERTS_LOADED:-}" ]] && return 0
readonly MONITORING_ALERTS_LOADED=1

# ============================================================================
# DEPENDENCIES
# ============================================================================

_ALERTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to load logging.sh
if [[ -f "${_ALERTS_LIB_DIR}/../foundation/logging.sh" ]]; then
    # shellcheck source=../foundation/logging.sh
    source "${_ALERTS_LIB_DIR}/../foundation/logging.sh" 2>/dev/null || true
fi

# Fallback logging if not available
if ! declare -F log_info >/dev/null 2>&1; then
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
    log_warn() { echo "[WARN] $*" >&2; }
fi

# Try to load secure-file-utils.sh
if [[ -f "${_ALERTS_LIB_DIR}/../foundation/secure-file-utils.sh" ]]; then
    # shellcheck source=../foundation/secure-file-utils.sh
    source "${_ALERTS_LIB_DIR}/../foundation/secure-file-utils.sh" 2>/dev/null || true
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

: "${TELEGRAM_PREFIX:=[System]}"
: "${RATE_LIMIT_SECONDS:=1800}"
: "${STATE_DIR:=/var/lib/alerts}"
: "${ENABLE_RECOVERY_ALERTS:=true}"

# Ensure state directory exists
mkdir -p "${STATE_DIR}" 2>/dev/null || true

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

_alerts_write_file() {
    local content="$1"
    local target="$2"

    if command -v sfu_write_file &>/dev/null; then
        sfu_write_file "$content" "$target"
    else
        echo "$content" > "$target"
    fi
}

_alerts_count_lines() {
    local file="$1"
    [[ -f "$file" ]] && wc -l < "$file" || echo 0
}

_alerts_get_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

# ============================================================================
# TELEGRAM API
# ============================================================================

_send_telegram_message() {
    local message="$1"

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "Telegram credentials not configured"
        return 1
    fi

    local response
    response=$(curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        2>/dev/null)

    if echo "$response" | grep -q '"ok":true'; then
        return 0
    else
        log_error "Telegram API error: $response"
        return 1
    fi
}

# ============================================================================
# RATE LIMITING
# ============================================================================

_check_rate_limit() {
    local alert_type="$1"
    local rate_file="${STATE_DIR}/.rate_limit_${alert_type}"

    if [[ -f "$rate_file" ]]; then
        local last_sent
        last_sent=$(cat "$rate_file" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local elapsed=$((now - last_sent))

        if [[ $elapsed -lt $RATE_LIMIT_SECONDS ]]; then
            local remaining=$((RATE_LIMIT_SECONDS - elapsed))
            log_debug "Rate limited: $alert_type (${remaining}s remaining)"
            return 1
        fi
    fi

    return 0
}

_update_rate_limit() {
    local alert_type="$1"
    local rate_file="${STATE_DIR}/.rate_limit_${alert_type}"

    _alerts_write_file "$(date +%s)" "$rate_file"
}

# ============================================================================
# PUBLIC API
# ============================================================================

# Send Telegram alert with rate limiting
#
# Usage: send_telegram_alert "alert_type" "message" ["emoji"] ["prefix"]
#
send_telegram_alert() {
    local alert_type="$1"
    local message="$2"
    local emoji="${3:-📟}"
    local prefix="${4:-${TELEGRAM_PREFIX}}"

    # Check rate limit
    if ! _check_rate_limit "$alert_type"; then
        return 0  # Silently skip (rate limited)
    fi

    # Build message
    local full_message="${emoji} ${prefix} ${message}"

    # Send
    if _send_telegram_message "$full_message"; then
        _update_rate_limit "$alert_type"
        log_info "Alert sent: $alert_type"
        return 0
    else
        log_error "Failed to send alert: $alert_type"
        return 1
    fi
}

# Send smart alert with deduplication (only on state change)
#
# Usage: send_smart_alert "alert_type" "identifier" "message" ["emoji"]
#
# Only sends alert if:
#   - This is the first occurrence of this alert type + identifier
#   - The message content has changed since last alert
#
send_smart_alert() {
    local alert_type="$1"
    local identifier="$2"
    local message="$3"
    local emoji="${4:-🔔}"

    local state_file="${STATE_DIR}/.smart_${alert_type}_${identifier}"
    local content_hash
    content_hash=$(_alerts_get_hash "$message")

    # Check if state changed
    if [[ -f "$state_file" ]]; then
        local last_hash
        last_hash=$(cat "$state_file" 2>/dev/null)

        if [[ "$last_hash" == "$content_hash" ]]; then
            log_debug "Smart alert suppressed (no change): $alert_type/$identifier"
            return 0
        fi
    fi

    # State changed - send alert
    if send_telegram_alert "${alert_type}_${identifier}" "$message" "$emoji"; then
        _alerts_write_file "$content_hash" "$state_file"
        return 0
    fi

    return 1
}

# Send recovery alert (service restored)
#
# Usage: send_recovery_alert "alert_type" "identifier" "message"
#
send_recovery_alert() {
    local alert_type="$1"
    local identifier="$2"
    local message="$3"

    if [[ "${ENABLE_RECOVERY_ALERTS}" != "true" ]]; then
        log_debug "Recovery alerts disabled"
        return 0
    fi

    local state_file="${STATE_DIR}/.smart_${alert_type}_${identifier}"

    # Only send recovery if there was a previous alert
    if [[ -f "$state_file" ]]; then
        # Clear state
        rm -f "$state_file" 2>/dev/null

        # Send recovery notification
        send_telegram_alert "${alert_type}_${identifier}_recovered" "$message" "✅" "[Recovery]"
        return $?
    fi

    return 0
}

# Clear rate limit for an alert type (for testing)
#
# Usage: clear_rate_limit "alert_type"
#
clear_rate_limit() {
    local alert_type="$1"
    local rate_file="${STATE_DIR}/.rate_limit_${alert_type}"

    rm -f "$rate_file" 2>/dev/null
    log_debug "Rate limit cleared: $alert_type"
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Alerts Library v1.0.0"
    echo ""
    echo "Required environment variables:"
    echo "  TELEGRAM_BOT_TOKEN - Your Telegram bot token"
    echo "  TELEGRAM_CHAT_ID   - Target chat ID"
    echo ""
    echo "Optional configuration:"
    echo "  TELEGRAM_PREFIX      = ${TELEGRAM_PREFIX}"
    echo "  RATE_LIMIT_SECONDS   = ${RATE_LIMIT_SECONDS}"
    echo "  STATE_DIR            = ${STATE_DIR}"
    echo "  ENABLE_RECOVERY_ALERTS = ${ENABLE_RECOVERY_ALERTS}"
    echo ""
    echo "Available functions:"
    echo "  - send_telegram_alert(type, message, [emoji], [prefix])"
    echo "  - send_smart_alert(type, identifier, message, [emoji])"
    echo "  - send_recovery_alert(type, identifier, message)"
    echo "  - clear_rate_limit(type)"
fi
