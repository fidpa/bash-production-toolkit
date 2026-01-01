#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Device Detection Library
# Version: 1.0.0
#
# Purpose:
#   Automatic device identification for multi-device environments.
#   Supports hostname-based, IP-based, and config-file-based detection.
#
# Features:
#   - Multiple detection strategies (hostname, IP, config file)
#   - Caching for performance
#   - Device architecture detection (arm64, x86_64, etc.)
#   - Custom device registration
#
# Usage:
#   source "/path/to/device-detection.sh"
#   DEVICE=$(detect_device)
#   ARCH=$(get_device_architecture)
#
# Dependencies:
#   - Bash 4.0+
#   - Optional: yq (for YAML config parsing)
#
# Configuration:
#   DEVICE_CONFIG_FILE - Path to device config (default: ./devices.yml)
#   DEVICE_OVERRIDE    - Force specific device (for testing)
#
# Changelog:
#   v1.0.0 (2026-01-01): Initial public release

# ============================================================================
# INCLUDE GUARD
# ============================================================================

[[ -n "${DEVICE_DETECTION_LOADED:-}" ]] && return 0
readonly DEVICE_DETECTION_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

: "${DEVICE_CONFIG_FILE:=${BASH_SOURCE[0]%/*}/devices.yml}"
: "${DEVICE_OVERRIDE:=}"

# Cache variables
_DETECTED_DEVICE=""
_DETECTED_ARCH=""

# ============================================================================
# CORE DETECTION
# ============================================================================

# Detect current device
#
# Returns: Device identifier string
#
# Detection priority:
#   1. DEVICE_OVERRIDE environment variable
#   2. Config file mapping (if yq available)
#   3. Hostname-based detection
#   4. IP-based detection
#   5. Default: "unknown"
#
detect_device() {
    # Return cached result
    if [[ -n "$_DETECTED_DEVICE" ]]; then
        echo "$_DETECTED_DEVICE"
        return 0
    fi

    # Priority 1: Override
    if [[ -n "${DEVICE_OVERRIDE}" ]]; then
        _DETECTED_DEVICE="${DEVICE_OVERRIDE}"
        echo "$_DETECTED_DEVICE"
        return 0
    fi

    # Priority 2: Config file (if yq available)
    if command -v yq &>/dev/null && [[ -f "${DEVICE_CONFIG_FILE}" ]]; then
        local hostname_short
        hostname_short=$(hostname -s 2>/dev/null)

        local config_device
        config_device=$(yq -r ".devices[] | select(.hostname == \"$hostname_short\") | .id" "${DEVICE_CONFIG_FILE}" 2>/dev/null)

        if [[ -n "$config_device" ]] && [[ "$config_device" != "null" ]]; then
            _DETECTED_DEVICE="$config_device"
            echo "$_DETECTED_DEVICE"
            return 0
        fi
    fi

    # Priority 3: Hostname-based
    local hostname
    hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null)

    case "$hostname" in
        *router*|*gateway*)
            _DETECTED_DEVICE="router"
            ;;
        *nas*|*storage*|*server*)
            _DETECTED_DEVICE="server"
            ;;
        *pi*|*raspberry*)
            _DETECTED_DEVICE="raspberry-pi"
            ;;
        *laptop*|*notebook*|*dell*|*thinkpad*)
            _DETECTED_DEVICE="laptop"
            ;;
        *desktop*|*workstation*)
            _DETECTED_DEVICE="desktop"
            ;;
        *)
            # Priority 4: IP-based fallback
            _detect_by_ip
            ;;
    esac

    # Priority 5: Default
    if [[ -z "$_DETECTED_DEVICE" ]]; then
        _DETECTED_DEVICE="unknown"
    fi

    echo "$_DETECTED_DEVICE"
    return 0
}

_detect_by_ip() {
    local ip
    ip=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)

    case "$ip" in
        10.0.0.1|192.168.1.1|192.168.0.1)
            _DETECTED_DEVICE="router"
            ;;
        10.0.0.2|192.168.1.2)
            _DETECTED_DEVICE="server"
            ;;
        *)
            # Check subnet for hints
            case "$ip" in
                10.0.0.*)
                    _DETECTED_DEVICE="infrastructure"
                    ;;
                192.168.*.*)
                    _DETECTED_DEVICE="client"
                    ;;
            esac
            ;;
    esac
}

# ============================================================================
# ARCHITECTURE DETECTION
# ============================================================================

# Get device architecture
#
# Returns: Architecture string (arm64, x86_64, armv7l, etc.)
#
get_device_architecture() {
    if [[ -n "$_DETECTED_ARCH" ]]; then
        echo "$_DETECTED_ARCH"
        return 0
    fi

    _DETECTED_ARCH=$(uname -m 2>/dev/null || echo "unknown")

    # Normalize common variants
    case "$_DETECTED_ARCH" in
        aarch64)
            _DETECTED_ARCH="arm64"
            ;;
        amd64)
            _DETECTED_ARCH="x86_64"
            ;;
    esac

    echo "$_DETECTED_ARCH"
}

# Check if device is ARM-based
#
is_arm_device() {
    local arch
    arch=$(get_device_architecture)
    [[ "$arch" == arm* ]] || [[ "$arch" == aarch* ]]
}

# Check if device is x86-based
#
is_x86_device() {
    local arch
    arch=$(get_device_architecture)
    [[ "$arch" == x86* ]] || [[ "$arch" == i?86 ]] || [[ "$arch" == amd64 ]]
}

# ============================================================================
# DEVICE INFORMATION
# ============================================================================

# Get device information
#
# Usage: get_device_info [field]
#
# Fields: hostname, ip, arch, os, kernel
#
get_device_info() {
    local field="${1:-all}"

    case "$field" in
        hostname)
            hostname -f 2>/dev/null || hostname
            ;;
        ip)
            ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1
            ;;
        arch)
            get_device_architecture
            ;;
        os)
            if [[ -f /etc/os-release ]]; then
                grep -oP '^PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null
            else
                uname -s
            fi
            ;;
        kernel)
            uname -r
            ;;
        all)
            echo "Device: $(detect_device)"
            echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
            echo "IP: $(get_device_info ip)"
            echo "Architecture: $(get_device_architecture)"
            echo "OS: $(get_device_info os)"
            echo "Kernel: $(uname -r)"
            ;;
        *)
            echo "Unknown field: $field" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# DEVICE REGISTRATION (Custom devices)
# ============================================================================

# Register custom device mapping
#
# Usage: register_device "hostname_pattern" "device_id"
#
# Example:
#   register_device "myserver" "production-server"
#
declare -gA _CUSTOM_DEVICES=()

register_device() {
    local pattern="$1"
    local device_id="$2"

    _CUSTOM_DEVICES["$pattern"]="$device_id"
}

# Check custom device mappings
#
_check_custom_devices() {
    local hostname
    hostname=$(hostname -s 2>/dev/null)

    for pattern in "${!_CUSTOM_DEVICES[@]}"; do
        if [[ "$hostname" == $pattern ]]; then
            echo "${_CUSTOM_DEVICES[$pattern]}"
            return 0
        fi
    done

    return 1
}

# ============================================================================
# DEVICE-SPECIFIC EXECUTION
# ============================================================================

# Run command only on specific device
#
# Usage: on_device "device_id" "command" [args...]
#
on_device() {
    local target_device="$1"
    shift
    local command="$*"

    local current_device
    current_device=$(detect_device)

    if [[ "$current_device" == "$target_device" ]]; then
        eval "$command"
        return $?
    else
        return 0  # Silently skip
    fi
}

# Run command on all devices except specified
#
# Usage: not_on_device "device_id" "command" [args...]
#
not_on_device() {
    local excluded_device="$1"
    shift
    local command="$*"

    local current_device
    current_device=$(detect_device)

    if [[ "$current_device" != "$excluded_device" ]]; then
        eval "$command"
        return $?
    else
        return 0
    fi
}

# ============================================================================
# SELF-TEST
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Device Detection Library v1.0.0"
    echo ""
    echo "Current device information:"
    get_device_info all
    echo ""
    echo "Available functions:"
    echo "  - detect_device()"
    echo "  - get_device_architecture()"
    echo "  - get_device_info([field])"
    echo "  - is_arm_device() / is_x86_device()"
    echo "  - register_device(pattern, device_id)"
    echo "  - on_device(device_id, command...)"
    echo "  - not_on_device(device_id, command...)"
fi
