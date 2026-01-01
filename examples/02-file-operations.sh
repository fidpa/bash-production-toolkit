#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Secure File Operations
# Demonstrates secure-file-utils.sh features
#
# Usage:
#   ./02-file-operations.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"

# Create temp directory for demo
DEMO_DIR=$(mktemp -d)
trap 'rm -rf "$DEMO_DIR"' EXIT

echo "=== Secure File Operations Demo ==="
echo "Demo directory: $DEMO_DIR"
echo ""

# Atomic file write
log_info "Writing file atomically..."
sfu_write_file "Hello, World!" "${DEMO_DIR}/hello.txt"
cat "${DEMO_DIR}/hello.txt"
echo ""

# Write with specific permissions
log_info "Writing file with permissions 600..."
sfu_write_file "Secret data" "${DEMO_DIR}/secret.txt" "600"
ls -la "${DEMO_DIR}/secret.txt"
echo ""

# Append to file
log_info "Appending to file..."
sfu_append_file "Line 1" "${DEMO_DIR}/append.txt"
sfu_append_file "Line 2" "${DEMO_DIR}/append.txt"
sfu_append_file "Line 3" "${DEMO_DIR}/append.txt"
cat "${DEMO_DIR}/append.txt"
echo ""

# Path validation
log_info "Validating paths..."
if sfu_validate_path "${DEMO_DIR}/hello.txt"; then
    echo "Path is valid"
fi

# Count lines
log_info "Counting lines..."
echo "Lines in append.txt: $(sfu_count_lines "${DEMO_DIR}/append.txt")"

echo ""
echo "=== Demo Complete ==="
