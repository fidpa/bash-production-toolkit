#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Complete Monitoring Script
# Demonstrates combining multiple libraries for production monitoring
#
# Prerequisites:
#   export TELEGRAM_BOT_TOKEN="your-bot-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#
# Usage:
#   ./06-monitoring-script.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"
source "${TOOLKIT}/monitoring/alerts.sh"
source "${TOOLKIT}/utilities/device-detection.sh"

# Configuration
export LOG_LEVEL=INFO
export TELEGRAM_PREFIX="[Monitor]"
STATE_FILE="${STATE_DIR:-/tmp}/.monitor-demo.state"

# Thresholds
DISK_WARN=80
DISK_CRIT=90

log_info "=== System Monitor Demo ==="
log_info "Device: $(detect_device)"
log_info "Architecture: $(get_device_architecture)"

# Check disk usage
check_disk() {
    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    log_info "Disk usage: ${usage}%"

    if [[ $usage -ge $DISK_CRIT ]]; then
        send_telegram_alert "disk_critical" "Disk usage critical: ${usage}%" "🔴"
        return 1
    elif [[ $usage -ge $DISK_WARN ]]; then
        send_telegram_alert "disk_warning" "Disk usage high: ${usage}%" "⚠️"
        return 0
    fi

    log_info "Disk usage OK"
    return 0
}

# Check memory usage
check_memory() {
    local usage
    usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')

    log_info "Memory usage: ${usage}%"

    if [[ $usage -ge 90 ]]; then
        send_telegram_alert "memory_critical" "Memory usage critical: ${usage}%" "🔴"
        return 1
    fi

    return 0
}

# Check load average
check_load() {
    local load
    load=$(awk '{print $1}' /proc/loadavg)
    local cpus
    cpus=$(nproc)

    log_info "Load average: $load (CPUs: $cpus)"

    # Alert if load > 2x CPUs
    if (( $(echo "$load > $cpus * 2" | bc -l) )); then
        send_telegram_alert "load_high" "Load average high: $load" "⚠️"
        return 1
    fi

    return 0
}

# Run checks
main() {
    local status=0

    check_disk || status=1
    check_memory || status=1
    check_load || status=1

    # Save state
    sfu_write_file "$(date +%s)" "$STATE_FILE"

    if [[ $status -eq 0 ]]; then
        log_info "All checks passed"
    else
        log_warn "Some checks failed"
    fi

    return $status
}

main "$@"
