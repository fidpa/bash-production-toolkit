#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Basic Logging
# Demonstrates logging.sh features
#
# Usage:
#   ./01-logging-basics.sh

set -uo pipefail

# Get script directory and source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"

# Configuration
export LOG_LEVEL=DEBUG
export LOG_TO_STDOUT=true

echo "=== Logging Basics Demo ==="
echo ""

# Log levels
log_debug "This is a debug message"
log_info "This is an info message"
log_warn "This is a warning"
log_error "This is an error"

echo ""

# Convenience aliases
info "Using info() alias"
warn "Using warn() alias"
error "Using error() alias"

echo ""

# Success/failure helpers
success "Operation completed successfully"
failure "Operation failed"

echo ""

# Structured logging with key-value pairs
log_info_structured "User login" "USER=admin" "IP=192.168.1.100"
log_error_structured "Database error" "DB=postgres" "CODE=ECONNREFUSED"

echo ""
echo "=== Demo Complete ==="
