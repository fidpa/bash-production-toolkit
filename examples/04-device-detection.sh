#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Device Detection
# Demonstrates device-detection.sh features
#
# Usage:
#   ./04-device-detection.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/utilities/device-detection.sh"

echo "=== Device Detection Demo ==="
echo ""

# Detect current device
log_info "Detecting device..."
DEVICE=$(detect_device)
echo "Detected device: $DEVICE"
echo ""

# Get device info
log_info "Getting device info..."
get_device_info all
echo ""

# Architecture detection
log_info "Checking architecture..."
ARCH=$(get_device_architecture)
echo "Architecture: $ARCH"

if is_arm_device; then
    echo "This is an ARM device"
elif is_x86_device; then
    echo "This is an x86 device"
fi
echo ""

# Device-conditional execution
log_info "Device-conditional execution..."
on_device "server" "echo 'Running on server'"
on_device "router" "echo 'Running on router'"
on_device "unknown" "echo 'Running on unknown device'"

echo ""

# Override demonstration
log_info "Testing override..."
export DEVICE_OVERRIDE="test-server"
# Clear cache
_DETECTED_DEVICE=""
echo "With DEVICE_OVERRIDE=test-server: $(detect_device)"
unset DEVICE_OVERRIDE

echo ""
echo "=== Demo Complete ==="
