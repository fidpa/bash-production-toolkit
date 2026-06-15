#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Test runner: discovers and executes all test-*.sh and smoke-*.sh files.
# Returns non-zero if any suite fails. Used by CI and for local runs.
#
# Usage:
#   bash tests/run-all.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
ran=0

for suite in "${TESTS_DIR}"/test-*.sh "${TESTS_DIR}"/smoke-*.sh; do
    [[ -e "$suite" ]] || continue
    ((ran++)) || true
    echo "======================================================================"
    echo "Running $(basename "$suite")"
    echo "======================================================================"
    if bash "$suite"; then
        echo ">>> $(basename "$suite"): OK"
    else
        echo ">>> $(basename "$suite"): FAILED"
        failed=1
    fi
    echo ""
done

echo "======================================================================"
if [[ "$ran" -eq 0 ]]; then
    echo "No test suites found."
    exit 1
fi
if [[ "$failed" -eq 0 ]]; then
    echo "All ${ran} suite(s) passed."
else
    echo "Some suites failed."
fi
exit "$failed"
