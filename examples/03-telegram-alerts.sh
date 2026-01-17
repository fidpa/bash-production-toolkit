#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Telegram Alerts
# Demonstrates alerts.sh features
#
# Prerequisites:
#   export TELEGRAM_BOT_TOKEN="your-bot-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#
# Usage:
#   ./03-telegram-alerts.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

# Configuration
export TELEGRAM_PREFIX="[Demo]"
export RATE_LIMIT_SECONDS=60  # 1 minute for testing

echo "=== Telegram Alerts Demo ==="
echo ""

# Check prerequisites
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "ERROR: Telegram not configured"
    echo ""
    echo "Set environment variables:"
    echo "  export TELEGRAM_BOT_TOKEN='your-token'"
    echo "  export TELEGRAM_CHAT_ID='your-chat-id'"
    exit 1
fi

# Basic alert
log_info "Sending basic alert..."
send_telegram_alert "demo_basic" "Basic alert from toolkit demo"

# Alert with custom emoji
log_info "Sending alert with custom emoji..."
send_telegram_alert "demo_emoji" "Alert with custom emoji" "🎉"

# Alert without prefix
log_info "Sending alert without prefix..."
send_telegram_alert "demo_no_prefix" "Just the message" "💬" ""

# Smart alert (deduplication)
log_info "Sending smart alert..."
send_smart_alert "demo_smart" "test-service" "Service check passed" "✅"

# Rate limiting demonstration
log_info "Demonstrating rate limiting..."
send_telegram_alert "demo_rate" "First alert - should send"
send_telegram_alert "demo_rate" "Second alert - should be rate limited"

echo ""
echo "=== Demo Complete ==="
echo "Check your Telegram for alerts."
