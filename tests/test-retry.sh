#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Unit tests for src/utilities/retry.sh
#
# Usage:
#   bash tests/test-retry.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${TESTS_DIR}/../src"

# Keep retry.sh logging quiet during tests
export RETRY_DISABLE_LOGGING=1

# Config consumed by the sourced retry.sh (export so they read as "used")
export RETRY_BASE_DELAY RETRY_MAX_DELAY RETRY_JITTER

source "${TESTS_DIR}/lib/assert.sh"
source "${TOOLKIT}/utilities/retry.sh"

echo "== calculate_backoff: exponential growth + cap =="
RETRY_BASE_DELAY=1; RETRY_MAX_DELAY=60; RETRY_JITTER=0
assert_eq 1  "$(calculate_backoff 0)" "attempt 0 -> base (1)"
assert_eq 2  "$(calculate_backoff 1)" "attempt 1 -> 2"
assert_eq 4  "$(calculate_backoff 2)" "attempt 2 -> 4"
assert_eq 8  "$(calculate_backoff 3)" "attempt 3 -> 8"
assert_eq 16 "$(calculate_backoff 4)" "attempt 4 -> 16"
assert_eq 32 "$(calculate_backoff 5)" "attempt 5 -> 32"
assert_eq 60 "$(calculate_backoff 6)" "attempt 6 -> capped at 60"
assert_eq 60 "$(calculate_backoff 9)" "attempt 9 -> still capped (no overflow)"
assert_eq 60 "$(calculate_backoff 100)" "attempt 100 -> still capped (bounded loop)"

echo "== calculate_backoff: custom base =="
RETRY_BASE_DELAY=10; RETRY_MAX_DELAY=300; RETRY_JITTER=0
assert_eq 10  "$(calculate_backoff 0)" "base 10 -> 10"
assert_eq 20  "$(calculate_backoff 1)" "base 10 -> 20"
assert_eq 160 "$(calculate_backoff 4)" "base 10 -> 160"
assert_eq 300 "$(calculate_backoff 6)" "base 10 -> capped at 300"

echo "== calculate_backoff: jitter stays within bounds =="
RETRY_BASE_DELAY=5; RETRY_MAX_DELAY=60; RETRY_JITTER=5
jitter_ok=1
for _ in $(seq 1 50); do
    d=$(calculate_backoff 0)            # base 5, + jitter 0..5  => 5..10
    [[ "$d" -ge 5 && "$d" -le 10 ]] || jitter_ok=0
done
assert_eq 1 "$jitter_ok" "jitter keeps attempt-0 delay in 5..10 over 50 samples"

echo "== retry_with_backoff: no real sleeping during tests =="
RETRY_BASE_DELAY=0; RETRY_MAX_DELAY=0; RETRY_JITTER=0

echo "-- success on first attempt --"
CALLS=0
succeed_now() { ((CALLS++)) || true; return 0; }
retry_with_backoff 5 succeed_now
assert_rc 0 "$?" "returns 0 when command succeeds immediately"
assert_eq 1 "$CALLS" "command called exactly once"

echo "-- success after 3 attempts --"
CALLS=0
succeed_on_3() { ((CALLS++)) || true; [[ "$CALLS" -ge 3 ]]; }
retry_with_backoff 5 succeed_on_3
assert_rc 0 "$?" "returns 0 when command eventually succeeds"
assert_eq 3 "$CALLS" "command called exactly 3 times"

echo "-- exhausted: propagates last exit code --"
CALLS=0
always_fail_7() { ((CALLS++)) || true; return 7; }
retry_with_backoff 3 always_fail_7
assert_rc 7 "$?" "propagates command's exit code (7) after exhaustion"
assert_eq 3 "$CALLS" "command called exactly max_attempts (3) times"

echo "-- usage errors --"
retry_with_backoff 0 true
assert_rc 2 "$?" "rc 2 when max_attempts < 1"
retry_with_backoff 3
assert_rc 2 "$?" "rc 2 when no command given"

assert_summary
