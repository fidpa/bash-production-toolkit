#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Webhook Alerts (v2.0.0)
# Demonstrates alerts.sh v2.0.0 features with generic webhook backend.
# Compatible with Mattermost, Slack, Discord, or any Slack-compatible endpoint.
#
# Prerequisites:
#   export ALERT_WEBHOOK_URL="https://your-webhook-endpoint/TOKEN"
#
# Optional:
#   export ALERTS_PREFIX="[Demo]"
#   export ALERT_WEBHOOK_CACERT="/path/to/ca.crt"  # For self-signed TLS
#
# Usage:
#   ./03-webhook-alerts.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

# Configuration
export ALERTS_PREFIX="[Demo]"
export RATE_LIMIT_SECONDS=60  # 1 minute for testing

echo "=== Webhook Alerts Demo (v2.0.0) ==="
echo ""

# Check prerequisites
if [[ -z "${ALERT_WEBHOOK_URL:-}" ]]; then
    echo "ERROR: Webhook not configured"
    echo ""
    echo "Set environment variable:"
    echo "  export ALERT_WEBHOOK_URL='https://your-webhook/TOKEN'"
    echo ""
    echo "Supported webhook formats:"
    echo "  Mattermost: https://your-mm.example.com/hooks/TOKEN"
    echo "  Slack:      https://hooks.slack.com/services/T/B/TOKEN"
    echo "  Discord:    https://discord.com/api/webhooks/ID/TOKEN"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1. Severity auto-derivation from alert type name
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Severity auto-derivation..."

send_alert "SERVICE_DOWN"      "nginx not responding"          # → 🔴 critical
send_alert "BACKUP_FAILED"     "Backup job failed at 03:00"    # → 🟠 error
send_alert "DISK_HIGH"         "Disk usage at 85%"             # → 🟡 warning
send_alert "SERVICE_RECOVERED" "nginx is back online"          # → 🔵 notice
send_alert "SYSTEM_BOOT"       "Server restarted"              # → ⚪ info

# ─────────────────────────────────────────────────────────────────────────────
# 2. Custom emoji (overrides auto-derivation)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Custom emoji..."
send_alert "DEPLOY_COMPLETE" "v2.0.0 deployed successfully" "🚀"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Custom prefix per alert
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Custom prefix..."
send_alert "BACKUP_COMPLETE" "Daily backup finished" "" "[Backup]"

# ─────────────────────────────────────────────────────────────────────────────
# 4. No prefix (empty string suppresses prefix)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: No prefix..."
send_alert "HEARTBEAT" "All systems nominal" "💚" ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Rate limiting demonstration
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Rate limiting..."
send_alert "DEMO_RATE_TEST" "First alert - should send"
send_alert "DEMO_RATE_TEST" "Second alert - rate limited (60s cooldown)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Recovery alerts
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Recovery alerts..."
send_recovery_alert "service_down" "nginx" "nginx is back online"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Clear rate limit (for testing)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Demo: Clearing rate limit..."
clear_rate_limit "DEMO_RATE_TEST"
send_alert "DEMO_RATE_TEST" "Alert after clearing rate limit - should send again"

echo ""
echo "=== Demo Complete ==="
echo "Check your webhook destination for alerts."
