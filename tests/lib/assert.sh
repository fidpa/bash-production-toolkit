#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Minimal pure-Bash assertion helpers for the toolkit test suite.
#
# Deliberately framework-free (no bats): the toolkit advertises "Bash 4.0+,
# no dependencies", and the tests honor the same contract.
#
# Usage:
#   source "tests/lib/assert.sh"
#   assert_eq "expected" "$actual" "what is checked"
#   assert_rc 0 "$?" "command succeeds"
#   assert_contains "$output" "needle" "output mentions needle"
#   assert_summary   # prints totals, returns 1 if any assertion failed

# Per-process counters (each test file runs in its own process)
ASSERT_PASS=0
ASSERT_FAIL=0

# Colors (disabled when not a TTY, e.g. in CI logs)
if [[ -t 1 ]]; then
    _A_GREEN=$'\033[0;32m'; _A_RED=$'\033[0;31m'; _A_RESET=$'\033[0m'
else
    _A_GREEN=""; _A_RED=""; _A_RESET=""
fi

_assert_pass() {
    ((ASSERT_PASS++)) || true
    echo "  ${_A_GREEN}PASS${_A_RESET}: $1"
}

_assert_fail() {
    ((ASSERT_FAIL++)) || true
    echo "  ${_A_RED}FAIL${_A_RESET}: $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

# assert_eq <expected> <actual> <message>
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        _assert_pass "$msg"
    else
        _assert_fail "$msg" "expected '${expected}', got '${actual}'"
    fi
}

# assert_rc <expected_rc> <actual_rc> <message>
assert_rc() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        _assert_pass "$msg"
    else
        _assert_fail "$msg" "expected exit code ${expected}, got ${actual}"
    fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        _assert_pass "$msg"
    else
        _assert_fail "$msg" "'${needle}' not found in output"
    fi
}

# assert_in_range <value> <min> <max> <message>
assert_in_range() {
    local value="$1" min="$2" max="$3" msg="$4"
    if [[ "$value" -ge "$min" && "$value" -le "$max" ]]; then
        _assert_pass "$msg"
    else
        _assert_fail "$msg" "expected ${min}..${max}, got ${value}"
    fi
}

# assert_summary — print totals; return 1 if any assertion failed
assert_summary() {
    echo ""
    echo "  ${ASSERT_PASS} passed, ${ASSERT_FAIL} failed"
    [[ "$ASSERT_FAIL" -eq 0 ]]
}
