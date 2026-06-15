#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Smoke test: run the dependency-free examples and assert they exit cleanly.
# Examples requiring a webhook (03, 06) are skipped here.
#
# Usage:
#   bash tests/smoke-examples.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "${TESTS_DIR}/../examples" && pwd)"

source "${TESTS_DIR}/lib/assert.sh"

echo "== examples: dependency-free smoke run =="
for ex in 01-logging-basics 02-file-operations 04-device-detection 05-error-handling; do
    bash "${EXAMPLES_DIR}/${ex}.sh" >/dev/null 2>&1
    assert_rc 0 "$?" "${ex}.sh exits cleanly"
done

echo "== example 07: self-healing daemon (fast demo) =="
# Fast settings: zero backoff, isolated lock, terminates after 2 cycles.
DAEMON_LOCK_FILE="$(mktemp -u)" \
RETRY_BASE_DELAY=0 RETRY_MAX_DELAY=0 RETRY_JITTER=0 MAX_RESTARTS=2 \
    bash "${EXAMPLES_DIR}/07-self-healing-daemon.sh" >/dev/null 2>&1
assert_rc 0 "$?" "07-self-healing-daemon.sh exits cleanly"

assert_summary
