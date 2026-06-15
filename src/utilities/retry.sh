#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Retry & Backoff Library
# Version: 1.0.0
#
# Purpose:
#   Resilient retry primitives for unreliable operations (network calls,
#   service reconnects, flaky commands):
#   - Exponential backoff with optional jitter (overflow-safe)
#   - Bounded retry wrapper around an arbitrary command
#
# Usage:
#   source "/path/to/retry.sh"
#
#   # Bounded retry of a command (up to 5 attempts):
#   retry_with_backoff 5 curl -fsS https://example.com/health
#
#   # Low-level: compute the delay for a given attempt yourself
#   delay=$(calculate_backoff 3)   # → RETRY_BASE_DELAY * 8 (capped, + jitter)
#   sleep "$delay"
#
# Dependencies:
#   - Bash 4.0+
#   - Optional: logging.sh (falls back to plain echo)
#
# Configuration (environment variables):
#   RETRY_BASE_DELAY       - Base delay in seconds (default: 1)
#   RETRY_MAX_DELAY        - Maximum delay cap in seconds (default: 60)
#   RETRY_JITTER           - Max random jitter added in seconds, 0 = off (default: 0)
#   RETRY_DISABLE_LOGGING  - Disable logging.sh integration
#
# Changelog:
#   v1.0.0: Initial public release

# Include guard
[[ -n "${RETRY_LOADED:-}" ]] && return 0
readonly RETRY_LOADED=1

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Optional: use logging.sh if available, otherwise minimal fallbacks
if [[ -f "${BASH_SOURCE[0]%/*}/../foundation/logging.sh" ]] && [[ -z "${RETRY_DISABLE_LOGGING:-}" ]]; then
    source "${BASH_SOURCE[0]%/*}/../foundation/logging.sh" 2>/dev/null || true
fi

if ! declare -F log_info >/dev/null 2>&1; then
    log_info()    { echo "[INFO] $*"; }
fi
if ! declare -F log_warning >/dev/null 2>&1; then
    log_warning() { echo "[WARNING] $*" >&2; }
fi

# ============================================================================
# CONFIGURATION (defaults, override via environment)
# ============================================================================

: "${RETRY_BASE_DELAY:=1}"
: "${RETRY_MAX_DELAY:=60}"
: "${RETRY_JITTER:=0}"

# ============================================================================
# PUBLIC API
# ============================================================================

# Calculate the exponential backoff delay for a given attempt number.
#
# Delay grows as RETRY_BASE_DELAY * 2^attempt, capped at RETRY_MAX_DELAY, with
# up to RETRY_JITTER seconds of random jitter added on top. The doubling uses a
# bounded loop (not the ** operator) to stay portable and avoid integer
# overflow on large attempt counts.
#
# Args:
#   $1 - Attempt number (0-based; 0 = first retry)
#
# Output:
#   Delay in whole seconds (stdout)
#
# Example:
#   delay=$(calculate_backoff 0)   # → RETRY_BASE_DELAY (+ jitter)
#   delay=$(calculate_backoff 3)   # → RETRY_BASE_DELAY * 8 (capped, + jitter)
#
calculate_backoff() {
    local attempt="${1:-0}"
    local delay="$RETRY_BASE_DELAY"
    local i

    # Exponential growth via bounded loop (overflow-safe, max 30 doublings)
    for ((i = 0; i < attempt && i < 30; i++)); do
        delay=$((delay * 2))
        [[ $delay -ge $RETRY_MAX_DELAY ]] && break
    done

    # Cap at maximum
    [[ $delay -gt $RETRY_MAX_DELAY ]] && delay="$RETRY_MAX_DELAY"

    # Add jitter (prevents synchronized retry storms across many clients)
    if [[ "$RETRY_JITTER" -gt 0 ]]; then
        delay=$((delay + (RANDOM % (RETRY_JITTER + 1))))
    fi

    echo "$delay"
}

# Retry a command with exponential backoff until it succeeds or attempts run out.
#
# Args:
#   $1   - Maximum number of attempts (>= 1)
#   $2.. - Command and arguments to execute
#
# Returns:
#   0 if the command eventually succeeds
#   The command's last non-zero exit code if all attempts fail
#   2 on invalid usage
#
# Example:
#   retry_with_backoff 5 curl -fsS https://example.com/health
#
retry_with_backoff() {
    local max_attempts="${1:-0}"
    shift || true

    if [[ "$max_attempts" -lt 1 || $# -eq 0 ]]; then
        log_warning "retry_with_backoff: usage: retry_with_backoff <max_attempts> <command...>"
        return 2
    fi

    local attempt=0
    local rc=0
    local delay

    while [[ $attempt -lt $max_attempts ]]; do
        # Capture rc directly: an `if cmd; then` with no else resets $? to 0
        # when the condition fails, which would mask the command's exit code.
        "$@"
        rc=$?
        if [[ $rc -eq 0 ]]; then
            [[ $attempt -gt 0 ]] && log_info "Command succeeded after $((attempt + 1)) attempt(s)"
            return 0
        fi

        ((attempt++)) || true
        [[ $attempt -ge $max_attempts ]] && break

        delay=$(calculate_backoff $((attempt - 1)))
        log_warning "Attempt ${attempt}/${max_attempts} failed (exit ${rc}), retrying in ${delay}s"
        sleep "$delay"
    done

    log_warning "Command failed after ${max_attempts} attempt(s) (exit ${rc})"
    return "$rc"
}
