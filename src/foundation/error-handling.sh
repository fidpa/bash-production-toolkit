#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Error Handling Library
# Version: 1.0.1
#
# Purpose:
#   Domain-specific error handling with recovery suggestions for
#   network, docker, and systemd service errors.
#
# Features:
#   - Structured error codes (network, docker, filesystem, etc.)
#   - Domain-specific handlers with auto-diagnosis
#   - Recovery suggestions with actionable commands
#   - Error traps with stack traces
#   - Safe execution wrapper
#
# Usage:
#   source "/path/to/error-handling.sh"
#   handle_network_error "eth0" "Interface down"
#   handle_docker_error "nginx" "Container crashed"
#   handle_service_error "myservice" "Failed to start"
#
# Dependencies:
#   - logging.sh (required)
#   - systemd (for service handling)
#   - docker (for container handling)
#
# Error Codes:
#   10 - Network error
#   20 - Docker error
#   30 - Filesystem error
#   40 - Permission error
#   50 - Configuration error
#   60 - Service error
#
# Changelog:
#   v1.0.1 (2026-01-01): Documentation Improvements
#     - IMPROVED: Changelog format for backwards compatibility clarity
#     - ALIGNED: With server repo v2.0.0 best practices
#     - NO CODE CHANGES: Fully backwards compatible
#   v1.0.0 (2026-01-01): Initial public release

# ============================================================================
# DEPENDENCY: logging.sh
# ============================================================================

_EH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${_EH_LIB_DIR}/logging.sh" ]]; then
    if ! declare -F log_info >/dev/null 2>&1; then
        # shellcheck source=./logging.sh
        source "${_EH_LIB_DIR}/logging.sh" || {
            echo "FATAL: Failed to source logging.sh" >&2
            return 1
        }
    fi
else
    echo "FATAL: logging.sh not found" >&2
    return 1
fi

# ============================================================================
# COMPATIBILITY ALIASES
# ============================================================================
# These aliases are maintained for backwards compatibility with calling scripts.
# The actual implementations are provided by logging.sh (log_warn, log_error).
# No additional code needed - this section documents the compatibility layer.

# ============================================================================
# ERROR CODES
# ============================================================================

declare -g -r ERROR_NETWORK=10
declare -g -r ERROR_DOCKER=20
declare -g -r ERROR_FILESYSTEM=30
declare -g -r ERROR_PERMISSION=40
declare -g -r ERROR_CONFIG=50
declare -g -r ERROR_SERVICE=60

# ============================================================================
# GLOBAL STATE
# ============================================================================

declare -g ERROR_COUNT=0
declare -g WARNING_COUNT=0
declare -g RECOVERY_MODE=false

# ============================================================================
# GENERIC ERROR HANDLER
# ============================================================================

handle_error() {
    local exit_code="$1"
    local error_message="$2"
    local component="${3:-unknown}"
    local recovery_action="${4:-}"

    log_error "[$component] $error_message (Exit Code: $exit_code)"
    ((ERROR_COUNT++)) || true

    if [[ -n "$recovery_action" ]]; then
        log_info "Executing recovery action: $recovery_action"
        local recovery_exit_code=0
        eval "$recovery_action" || recovery_exit_code=$?
        if [[ $recovery_exit_code -eq 0 ]]; then
            log_info "Recovery successful"
            return 0
        else
            log_error "Recovery failed"
        fi
    fi

    return "$exit_code"
}

# ============================================================================
# DOMAIN-SPECIFIC HANDLERS
# ============================================================================

handle_network_error() {
    local interface="$1"
    local error_msg="$2"

    log_error "[NETWORK] Interface $interface: $error_msg"
    ((ERROR_COUNT++)) || true

    log_info "Running network diagnostics..."

    if ip link show "$interface" >/dev/null 2>&1; then
        local status
        status=$(ip link show "$interface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
        log_info "Interface $interface status: $status"

        if [[ "$status" == "DOWN" ]]; then
            log_info "Attempting to bring up interface $interface..."
            if sudo ip link set "$interface" up; then
                log_info "Interface $interface activated successfully"
                return 0
            fi
        fi
    else
        log_error "Interface $interface does not exist"
        suggest_network_recovery "$interface"
    fi

    return $ERROR_NETWORK
}

handle_docker_error() {
    local container="$1"
    local error_msg="$2"

    log_error "[DOCKER] Container $container: $error_msg"
    ((ERROR_COUNT++)) || true

    if docker ps -a --format "table {{.Names}}" | grep -q "^$container$"; then
        local status
        status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
        log_info "Container $container status: $status"

        case "$status" in
            "exited")
                log_info "Attempting to restart container $container..."
                if docker start "$container"; then
                    log_info "Container $container started successfully"
                    return 0
                fi
                ;;
            "running")
                log_info "Container is running, checking health..."
                check_container_health "$container"
                ;;
            "dead"|"created")
                log_info "Removing broken container..."
                docker rm "$container" 2>/dev/null
                suggest_docker_recovery "$container"
                ;;
        esac
    else
        log_error "Container $container does not exist"
        suggest_docker_recovery "$container"
    fi

    return $ERROR_DOCKER
}

handle_service_error() {
    local service="$1"
    local error_msg="$2"

    log_error "[SERVICE] $service: $error_msg"
    ((ERROR_COUNT++)) || true

    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        local status
        status=$(systemctl is-active "$service")
        log_info "Service $service status: $status"

        case "$status" in
            "failed")
                log_info "Service failed, showing logs..."
                journalctl -u "$service" --lines=10 --no-pager

                log_info "Attempting to restart service $service..."
                if sudo systemctl restart "$service"; then
                    log_info "Service $service restarted successfully"
                    return 0
                fi
                ;;
            "inactive")
                log_info "Attempting to start service $service..."
                if sudo systemctl start "$service"; then
                    log_info "Service $service started successfully"
                    return 0
                fi
                ;;
        esac
    else
        log_error "Service $service is not configured"
        suggest_service_recovery "$service"
    fi

    return $ERROR_SERVICE
}

# ============================================================================
# RECOVERY SUGGESTIONS
# ============================================================================

suggest_network_recovery() {
    local interface="$1"
    cat << EOF

🔧 NETWORK RECOVERY OPTIONS for $interface:

1. Check hardware:
   - Verify cable connection
   - Test USB adapter power/data connection
   - Check LED status on adapter

2. Check driver status:
   lsmod | grep -E "(ax88179|r8152|asix)"
   dmesg | grep -i "$interface"

3. Manual activation:
   sudo ip link set $interface up
   sudo dhclient $interface

4. Restart network manager:
   sudo systemctl restart NetworkManager

EOF
}

suggest_docker_recovery() {
    local container="$1"
    cat << EOF

🔧 DOCKER RECOVERY OPTIONS for $container:

1. Check container logs:
   docker logs $container --tail=50

2. Recreate compose stack:
   docker-compose down
   docker-compose up -d

3. Update images:
   docker-compose pull
   docker-compose up -d

4. Check volumes:
   docker volume ls
   docker volume inspect <volume_name>

5. Fix network issues:
   docker network ls
   docker network prune

EOF
}

suggest_service_recovery() {
    local service="$1"
    cat << EOF

🔧 SERVICE RECOVERY OPTIONS for $service:

1. Check service status:
   systemctl status $service -l

2. View service logs:
   journalctl -u $service --since "1 hour ago"

3. Reinstall service:
   sudo systemctl disable $service
   sudo systemctl enable $service

4. Check configuration:
   sudo systemctl cat $service

5. Check dependencies:
   systemctl list-dependencies $service

EOF
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

check_container_health() {
    local container="$1"

    local health_status
    health_status=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null)

    case "$health_status" in
        "healthy")
            log_info "Container $container is healthy"
            ;;
        "unhealthy")
            log_warn "Container $container is unhealthy"
            ((WARNING_COUNT++)) || true
            docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' "$container"
            ;;
        "starting")
            log_info "Container $container is still starting..."
            ;;
        "")
            log_info "Container $container has no health checks"
            ;;
    esac
}

# ============================================================================
# ERROR TRAPS
# ============================================================================

error_trap() {
    local exit_code=$?
    local line_number=$1
    local bash_command="$2"

    if [[ $exit_code -ne 0 ]]; then
        log_error "Unexpected error at line $line_number: '$bash_command' (Exit Code: $exit_code)"

        log_error "Call Stack:"
        local i=0
        while caller $i; do
            ((i++)) || true
        done | while read -r line func file; do
            log_error "  $file:$line in $func()"
        done
    fi
}

set_error_traps() {
    set -E
    trap 'error_trap $LINENO "$BASH_COMMAND"' ERR
}

# ============================================================================
# UTILITIES
# ============================================================================

safe_execute() {
    local command="$1"
    local description="$2"
    local recovery_action="${3:-}"

    log_info "Executing: $description"
    log_debug "Command: $command"

    local command_exit_code=0
    eval "$command" || command_exit_code=$?
    if [[ $command_exit_code -eq 0 ]]; then
        log_info "✅ $description successful"
        return 0
    else
        handle_error "$command_exit_code" "$description" "safe_execute" "$recovery_action"
        return $command_exit_code
    fi
}

enable_recovery_mode() {
    RECOVERY_MODE=true
    log_info "Recovery mode enabled - automatic recovery will be attempted"
}

cleanup_and_exit() {
    local exit_code=${1:-0}

    if [[ $ERROR_COUNT -gt 0 ]] || [[ $WARNING_COUNT -gt 0 ]]; then
        echo
        log_info "=== ERROR HANDLING SUMMARY ==="
        log_info "Errors: $ERROR_COUNT"
        log_info "Warnings: $WARNING_COUNT"
    fi

    exit "$exit_code"
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error Handling Library v1.0.0"
    echo ""
    echo "Available functions:"
    echo "  - handle_error(exit_code, message, component, recovery_action)"
    echo "  - handle_network_error(interface, message)"
    echo "  - handle_docker_error(container, message)"
    echo "  - handle_service_error(service, message)"
    echo "  - set_error_traps()"
    echo "  - safe_execute(command, description, recovery_action)"
fi
