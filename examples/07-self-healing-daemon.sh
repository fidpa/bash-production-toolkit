#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/bash-production-toolkit
#
# Example: Self-Healing Daemon (resilient supervise loop)
# Demonstrates combining retry, logging, secure-file-utils and alerts into a
# crash-resilient supervisor that keeps a long-running command alive with:
#   - exponential backoff between restarts (retry.sh)
#   - a single-instance lock (secure-file-utils.sh, atomic write)
#   - an optional precondition gate (e.g. "wait for VPN/network")
#   - optional alerting once failures pile up (alerts.sh)
#
# This is the generalized, Linux-focused pattern behind a VPN-aware reverse SSH
# tunnel: wait for a precondition, (re)start the process, back off on failure,
# alert when failures accumulate.
#
# Prerequisites: none (runs a bundled demo workload that "crashes" on purpose).
#
# Optional:
#   export SUPERVISE_CMD="ssh -N -R 2222:localhost:22 myhost"  # real workload
#   export PRECONDITION_CMD="ping -c1 -W2 10.0.0.1"            # gate before start
#   export MAX_RESTARTS=0                                       # 0 = unlimited
#   export ALERT_WEBHOOK_URL="https://your-webhook/TOKEN"      # enables alerting
#
# Usage:
#   ./07-self-healing-daemon.sh

set -uo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/../src"

source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"
source "${TOOLKIT}/monitoring/alerts.sh"
source "${TOOLKIT}/utilities/retry.sh"

# Configuration
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export ALERTS_PREFIX="${ALERTS_PREFIX:-[Daemon]}"

# Backoff tuning (consumed by retry.sh)
export RETRY_BASE_DELAY="${RETRY_BASE_DELAY:-2}"
export RETRY_MAX_DELAY="${RETRY_MAX_DELAY:-30}"
export RETRY_JITTER="${RETRY_JITTER:-3}"

# Demo workload: prints, runs briefly, then "crashes" so the loop is visible.
SUPERVISE_CMD="${SUPERVISE_CMD:-echo '  [workload] running...'; sleep 2; false}"
PRECONDITION_CMD="${PRECONDITION_CMD:-}"          # empty = always ready
MAX_RESTARTS="${MAX_RESTARTS:-3}"                 # demo cap; 0 = unlimited (real use)
FAILURE_ALERT_THRESHOLD="${FAILURE_ALERT_THRESHOLD:-3}"

# Own dedicated variable: do not reuse STATE_DIR (owned by alerts.sh).
LOCK_FILE="${DAEMON_LOCK_FILE:-${TMPDIR:-/tmp}/.self-healing-daemon.lock}"

# ─────────────────────────────────────────────────────────────────────────────
# Single-instance lock (atomic write via secure-file-utils)
# ─────────────────────────────────────────────────────────────────────────────
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_error "Another instance is already running (PID ${old_pid})"
            exit 1
        fi
        log_warning "Removing stale lock file (PID ${old_pid} not running)"
    fi
    sfu_write_file "$$" "$LOCK_FILE" 600 || {
        log_error "Could not acquire lock at ${LOCK_FILE}"
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup on exit / signals (guarded against double execution)
# ─────────────────────────────────────────────────────────────────────────────
cleanup() {
    [[ -n "${_cleaned:-}" ]] && return 0
    _cleaned=1
    log_info "Shutting down, releasing lock"
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ─────────────────────────────────────────────────────────────────────────────
# Precondition gate (generalized VPN/network readiness check)
# ─────────────────────────────────────────────────────────────────────────────
wait_for_precondition() {
    [[ -z "$PRECONDITION_CMD" ]] && return 0
    local waited=0
    while ! bash -c "$PRECONDITION_CMD" >/dev/null 2>&1; do
        log_warning "Precondition not met, waiting ${RETRY_MAX_DELAY}s ..."
        sleep "$RETRY_MAX_DELAY"
        ((waited++)) || true
    done
    [[ $waited -gt 0 ]] && log_notice "Precondition satisfied after ${waited} check(s)"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Supervise loop
# ─────────────────────────────────────────────────────────────────────────────
log_info "=== Self-Healing Daemon Demo ==="
log_info "Workload: ${SUPERVISE_CMD}"
log_info "Max restarts: ${MAX_RESTARTS} (0 = unlimited)"

acquire_lock

attempt=0      # consecutive failures, drives backoff; reset after a clean run
restarts=0     # total cycles (used only for the demo cap)

while true; do
    wait_for_precondition

    log_info "Starting workload (cycle #$((restarts + 1)))"
    if bash -c "$SUPERVISE_CMD"; then
        log_notice "Workload exited cleanly"
        attempt=0
    else
        rc=$?
        ((attempt++)) || true
        log_warning "Workload exited with code ${rc} (consecutive failures: ${attempt})"

        # Alert once failures accumulate (only if a webhook is configured)
        if [[ -n "${ALERT_WEBHOOK_URL:-}" && $attempt -eq $FAILURE_ALERT_THRESHOLD ]]; then
            send_alert "WORKLOAD_FAILING" \
                "Workload failed ${attempt}x in a row (last exit ${rc})"
        fi
    fi

    restarts=$((restarts + 1))
    if [[ "$MAX_RESTARTS" -ne 0 && $restarts -ge $MAX_RESTARTS ]]; then
        log_info "Reached MAX_RESTARTS (${MAX_RESTARTS}), stopping demo"
        break
    fi

    delay=$(calculate_backoff "$attempt")
    log_info "Backing off ${delay}s before next start"
    sleep "$delay"
done

log_info "=== Daemon stopped ==="
