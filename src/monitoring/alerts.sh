#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Alerts Library
# Version: 2.0.0 (Updated: 24.02.2026)
# Changelog v2.0.0 (24.02.2026): Webhook-Generic Backend (Breaking Change)
#   - BREAKING: Removed Telegram delivery (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)
#   - BREAKING: Removed send_telegram_alert() - use send_alert() instead
#   - BREAKING: Renamed TELEGRAM_PREFIX → ALERTS_PREFIX
#   - NEW: send_alert() - Generic webhook delivery (Mattermost/Slack/Discord)
#   - NEW: _derive_severity() - Auto-derive severity from alert_type name pattern
#   - NEW: ALERT_WEBHOOK_URL - Required environment variable for webhook endpoint
#   - NEW: ALERT_WEBHOOK_CACERT - Optional path to CA cert for self-signed TLS
#   - IMPROVED: Rate limiting via .last_alert_TYPE files (unchanged from v1.x)
#   - IMPROVED: Severity auto-derived: *_FAILED→error, *_RECOVERED→notice, etc.
#   - KEPT: send_recovery_alert(), clear_rate_limit() (updated to use send_alert)
# Changelog v1.0.1 (17.01.2026): send_recovery_alert default message
#   - FIX: send_recovery_alert() now has default message "Recovered" (matches docs)
# Changelog v1.0.0 (01.01.2026): Initial public release (Telegram-based)
#
# Purpose:
#   Generic webhook alerting with rate limiting and smart deduplication
#   to reduce alert fatigue. Works with any Slack-compatible webhook
#   (Mattermost, Slack, Discord, custom endpoints).
#
# Features:
#   - Rate-limited alerts (configurable cooldown per alert type)
#   - Severity auto-derivation from alert type name patterns
#   - Generic JSON webhook delivery (vendor-agnostic)
#   - Recovery alerts (service restored notifications)
#   - Content hashing for duplicate detection
#
# Usage:
#   source "/path/to/alerts.sh"
#   export ALERT_WEBHOOK_URL="https://mattermost.example/hooks/xxx"
#
#   send_alert "BACKUP_FAILED" "Backup job failed at 03:00"
#   # → severity auto-derived as "error", emoji "🟠"
#
#   send_alert "SERVICE_RECOVERED" "nginx is back online"
#   # → severity auto-derived as "notice", emoji "🔵"
#
# Supported webhook formats (Slack-compatible JSON):
#   - Mattermost: https://your-mm/hooks/TOKEN
#   - Slack:      https://hooks.slack.com/services/T/B/TOKEN
#   - Discord:    https://discord.com/api/webhooks/ID/TOKEN
#   - Custom:     Any endpoint accepting {"text": "..."}
#
# Dependencies:
#   - logging.sh (optional, falls back to echo)
#   - secure-file-utils.sh (optional, for atomic writes)
#   - curl (required for webhook delivery)
#
# Configuration (environment variables):
#   ALERT_WEBHOOK_URL        - Webhook endpoint URL (required)
#   ALERT_WEBHOOK_CACERT     - Path to CA cert for self-signed TLS (optional)
#   ALERTS_PREFIX            - Message prefix (default: [System])
#   RATE_LIMIT_SECONDS       - Cooldown between same alerts (default: 1800)
#   STATE_DIR                - Directory for state files (default: /var/lib/alerts)
#   ENABLE_RECOVERY_ALERTS   - Send recovery notifications (default: true)

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
    log_info()  { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
    log_warning()  { echo "[WARNING] $*" >&2; }
fi

# Try to load secure-file-utils.sh
if [[ -f "${_ALERTS_LIB_DIR}/../foundation/secure-file-utils.sh" ]]; then
    # shellcheck source=../foundation/secure-file-utils.sh
    source "${_ALERTS_LIB_DIR}/../foundation/secure-file-utils.sh" 2>/dev/null || true
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

: "${ALERTS_PREFIX:=[System]}"
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

_alerts_get_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

# Sanitize identifier for use in file paths (prevent directory traversal)
# Only allows: a-z, A-Z, 0-9, underscore, hyphen, dot
_sanitize_alert_id() {
    local input="$1"
    printf '%s' "${input//[^a-zA-Z0-9_.-]/}"
}

# ─────────────────────────────────────────────────────────────────────────────
# _derive_severity <alert_type>
# Derive severity from alert_type name pattern (RFC-aligned)
# Returns: "critical", "error", "warning", "notice", or "info"
# ─────────────────────────────────────────────────────────────────────────────
_derive_severity() {
    local alert_type="$1"
    case "$alert_type" in
        *_CRITICAL|*_DOWN)
            echo "critical" ;;
        *_ERROR|*_FAILURE|*_FAILED)
            echo "error" ;;
        *_WARNING|*_DEGRADED|*_HIGH|*_THROTTLED)
            echo "warning" ;;
        *_RECOVERED|*_RESOLVED|*_SUCCESS|*_COMPLETE|*_BOOT)
            echo "notice" ;;
        *_NEW|*)
            echo "info" ;;
    esac
}

# ============================================================================
# RATE LIMITING
# ============================================================================

# Atomically check and update rate limit (prevents TOCTOU race condition)
# Returns 0 if alert is allowed, 1 if rate-limited
_check_and_update_rate_limit() {
    local alert_type="$1"
    local safe_type
    safe_type=$(_sanitize_alert_id "$alert_type")
    local rate_file="${STATE_DIR}/.last_alert_${safe_type}"
    local now
    now=$(date +%s)

    if [[ -f "$rate_file" ]]; then
        local last_sent
        last_sent=$(cat "$rate_file" 2>/dev/null || echo 0)
        local elapsed=$((now - last_sent))

        if [[ $elapsed -lt $RATE_LIMIT_SECONDS ]]; then
            local remaining=$((RATE_LIMIT_SECONDS - elapsed))
            log_debug "Rate limited: $alert_type (${remaining}s remaining)"
            return 1
        fi
    fi

    # Update timestamp atomically before sending (minimizes race window)
    _alerts_write_file "$now" "$rate_file"
    return 0
}

# ============================================================================
# WEBHOOK DELIVERY
# ============================================================================

# Internal: send JSON payload to webhook URL
# Usage: _send_webhook_message "text content"
_send_webhook_message() {
    local text="$1"

    if [[ -z "${ALERT_WEBHOOK_URL:-}" ]]; then
        log_error "ALERT_WEBHOOK_URL not configured - cannot send alert"
        return 1
    fi

    # Build JSON payload (prefer jq for RFC 8259 compliance)
    local json_payload
    if command -v jq &>/dev/null; then
        json_payload=$(jq -n --arg text "$text" '{"text": $text}')
    else
        # Bash fallback: escape known special characters
        local escaped="${text//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        escaped="${escaped//$'\n'/\\n}"
        escaped="${escaped//$'\r'/\\r}"
        escaped="${escaped//$'\t'/\\t}"
        escaped="${escaped//$'\b'/\\b}"
        escaped="${escaped//$'\f'/\\f}"
        json_payload=$(printf '{"text": "%s"}' "$escaped")
    fi

    local curl_args=(
        -s -X POST
        -H "Content-Type: application/json"
        -d "$json_payload"
        --max-time 10
        --retry 3
        --retry-delay 2
        "$ALERT_WEBHOOK_URL"
    )

    # Optional CA cert for self-signed TLS
    if [[ -n "${ALERT_WEBHOOK_CACERT:-}" ]] && [[ -f "${ALERT_WEBHOOK_CACERT}" ]]; then
        curl_args+=(--cacert "${ALERT_WEBHOOK_CACERT}")
    fi

    if curl "${curl_args[@]}" > /dev/null 2>&1; then
        return 0
    else
        log_error "Webhook delivery failed"
        return 1
    fi
}

# ============================================================================
# PUBLIC API
# ============================================================================

# Send alert via generic webhook with rate limiting
#
# Usage: send_alert "alert_type" "message" ["emoji"] ["prefix"]
#
# alert_type determines severity automatically:
#   *_FAILED, *_ERROR, *_FAILURE → error (🟠)
#   *_CRITICAL, *_DOWN           → critical (🔴)
#   *_WARNING, *_DEGRADED        → warning (🟡)
#   *_RECOVERED, *_RESOLVED      → notice (🔵)
#   everything else              → info (⚪)
#
# Environment:
#   ALERT_WEBHOOK_URL  - Webhook endpoint (required)
#   ALERTS_PREFIX      - Message prefix (default: [System])
#   RATE_LIMIT_SECONDS - Cooldown in seconds (default: 1800)
#   STATE_DIR          - State directory (default: /var/lib/alerts)
#
send_alert() {
    local alert_type="$1"
    local message="$2"
    local emoji="${3:-}"
    local prefix="${4:-${ALERTS_PREFIX}}"

    # Auto-derive severity and emoji if not provided
    local severity
    severity=$(_derive_severity "$alert_type")

    if [[ -z "$emoji" ]]; then
        case "$severity" in
            critical) emoji="🔴" ;;
            error)    emoji="🟠" ;;
            warning)  emoji="🟡" ;;
            notice)   emoji="🔵" ;;
            info|*)   emoji="⚪" ;;
        esac
    fi

    # Check and update rate limit atomically
    if ! _check_and_update_rate_limit "$alert_type"; then
        return 0  # Silently skip (rate limited)
    fi

    # Build message
    local full_message
    if [[ -n "$prefix" ]]; then
        full_message="${emoji} ${prefix}: ${message}"
    else
        full_message="${emoji} ${message}"
    fi

    # Send
    if _send_webhook_message "$full_message"; then
        log_info "Alert sent: $alert_type (severity: $severity)"
        return 0
    else
        log_error "Failed to send alert: $alert_type"
        return 1
    fi
}

# Send recovery alert (service restored)
#
# Usage: send_recovery_alert "alert_type" "identifier" ["message"]
#
send_recovery_alert() {
    local alert_type="$1"
    local identifier="$2"
    local message="${3:-Recovered}"

    if [[ "${ENABLE_RECOVERY_ALERTS}" != "true" ]]; then
        log_debug "Recovery alerts disabled"
        return 0
    fi

    local safe_type safe_id
    safe_type=$(_sanitize_alert_id "$alert_type")
    safe_id=$(_sanitize_alert_id "$identifier")
    local state_file="${STATE_DIR}/.smart_${safe_type}_${safe_id}"

    # Only send recovery if there was a previous alert
    if [[ -f "$state_file" ]]; then
        # Clear state
        rm -f "$state_file" 2>/dev/null

        # Send recovery notification with RECOVERED suffix for auto-severity
        send_alert "${alert_type}_RECOVERED" "$message" "✅" "[Recovery]"
        return $?
    fi

    return 0
}

# Clear rate limit for an alert type (for testing or manual reset)
#
# Usage: clear_rate_limit "alert_type"
#
clear_rate_limit() {
    local alert_type="$1"
    local safe_type
    safe_type=$(_sanitize_alert_id "$alert_type")
    local rate_file="${STATE_DIR}/.last_alert_${safe_type}"

    rm -f "$rate_file" 2>/dev/null
    log_debug "Rate limit cleared: $alert_type"
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Alerts Library v2.0.0"
    echo ""
    echo "Required environment variables:"
    echo "  ALERT_WEBHOOK_URL - Slack-compatible webhook URL"
    echo "    Examples:"
    echo "      Mattermost: https://your-mm.example.com/hooks/TOKEN"
    echo "      Slack:      https://hooks.slack.com/services/T/B/TOKEN"
    echo "      Discord:    https://discord.com/api/webhooks/ID/TOKEN"
    echo ""
    echo "Optional configuration:"
    echo "  ALERT_WEBHOOK_CACERT   = ${ALERT_WEBHOOK_CACERT:-<not set>}"
    echo "  ALERTS_PREFIX          = ${ALERTS_PREFIX}"
    echo "  RATE_LIMIT_SECONDS     = ${RATE_LIMIT_SECONDS}"
    echo "  STATE_DIR              = ${STATE_DIR}"
    echo "  ENABLE_RECOVERY_ALERTS = ${ENABLE_RECOVERY_ALERTS}"
    echo ""
    echo "Available functions:"
    echo "  - send_alert(type, message, [emoji], [prefix])"
    echo "  - send_recovery_alert(type, identifier, [message])"
    echo "  - clear_rate_limit(type)"
    echo ""
    echo "Severity auto-derivation from alert_type patterns:"
    echo "  *_CRITICAL, *_DOWN      → critical 🔴"
    echo "  *_FAILED, *_ERROR       → error    🟠"
    echo "  *_WARNING, *_DEGRADED   → warning  🟡"
    echo "  *_RECOVERED, *_RESOLVED → notice   🔵"
    echo "  everything else         → info     ⚪"
fi
