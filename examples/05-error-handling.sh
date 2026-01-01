#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Error Handling
# Demonstrates error-handling.sh features
#
# Usage:
#   ./05-error-handling.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/error-handling.sh"

echo "=== Error Handling Demo ==="
echo ""

# Generic error handling
log_info "Testing generic error handler..."
handle_error 1 "Example error message" "demo-component" || true
echo ""

# Safe execution wrapper
log_info "Testing safe_execute..."
safe_execute "echo 'Hello from safe_execute'" "Print hello message" || true
safe_execute "false" "Command that fails" "echo 'Recovery action executed'" || true
echo ""

# Error summary
log_info "Error counts..."
echo "Errors: $ERROR_COUNT"
echo "Warnings: $WARNING_COUNT"
echo ""

# Domain-specific handlers (require actual services)
log_info "Domain handlers available:"
echo "  - handle_network_error interface message"
echo "  - handle_docker_error container message"
echo "  - handle_service_error service message"
echo ""
echo "(Run with actual services to see full functionality)"

echo ""
echo "=== Demo Complete ==="
