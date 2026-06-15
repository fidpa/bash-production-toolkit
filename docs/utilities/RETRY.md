# Retry & Backoff Library (v1.0.0)

Resilient retry primitives for unreliable operations: exponential backoff with optional jitter, and a bounded retry wrapper around an arbitrary command. Useful for network calls, service reconnect loops, and flaky commands.

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/utilities/retry.sh

# Retry a flaky command up to 5 times with exponential backoff
retry_with_backoff 5 curl -fsS https://example.com/health

# Low-level: compute the delay for a given attempt yourself
delay=$(calculate_backoff 3)   # → RETRY_BASE_DELAY * 8 (capped, + jitter)
sleep "$delay"
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/utilities/retry.sh
```

## API Reference

### calculate_backoff

```bash
delay=$(calculate_backoff "attempt")
```

Calculate the exponential backoff delay for a given attempt number.

Delay grows as `RETRY_BASE_DELAY * 2^attempt`, capped at `RETRY_MAX_DELAY`, with up to `RETRY_JITTER` seconds of random jitter added on top. The doubling uses a bounded loop (not the `**` operator) to stay portable and avoid integer overflow on large attempt counts.

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| attempt | `0` | Attempt number, 0-based (0 = first retry) |

**Returns:** Delay in whole seconds (stdout)

**Example:**
```bash
# Defaults: RETRY_BASE_DELAY=1, RETRY_MAX_DELAY=60, RETRY_JITTER=0
calculate_backoff 0   # → 1
calculate_backoff 1   # → 2
calculate_backoff 3   # → 8
calculate_backoff 6   # → 60  (capped)
calculate_backoff 9   # → 60  (capped, no overflow)
```

### retry_with_backoff

```bash
retry_with_backoff "max_attempts" command [args...]
```

Retry a command with exponential backoff until it succeeds or the attempts run out. Sleeps `calculate_backoff` seconds between attempts.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| max_attempts | Maximum number of attempts (>= 1) |
| command [args...] | Command and arguments to execute |

**Returns:**
| Code | Meaning |
|------|---------|
| `0` | The command eventually succeeded |
| command's exit code | All attempts failed (last non-zero exit code is propagated) |
| `2` | Invalid usage (missing attempts or command) |

**Example:**
```bash
# Wait for a database to come up (8 attempts: ~1+2+4+8+16+32+60 = ~123s max)
if retry_with_backoff 8 pg_isready -h db.internal; then
    log_info "Database reachable"
else
    log_error "Database still down after 8 attempts"
    exit 1
fi

# Retry an HTTP health check
retry_with_backoff 5 curl -fsS https://example.com/health
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RETRY_BASE_DELAY` | `1` | Base delay in seconds |
| `RETRY_MAX_DELAY` | `60` | Maximum delay cap in seconds |
| `RETRY_JITTER` | `0` | Max random jitter added in seconds (`0` = off) |
| `RETRY_DISABLE_LOGGING` | (unset) | Disable logging.sh integration |

**Tuning examples:**
```bash
# Aggressive: short delays, no cap creep
export RETRY_BASE_DELAY=1 RETRY_MAX_DELAY=10

# Gentle, anti-thundering-herd (many clients): add jitter
export RETRY_BASE_DELAY=5 RETRY_MAX_DELAY=300 RETRY_JITTER=10
```

### Logging Integration

If `logging.sh` is sourced (and `RETRY_DISABLE_LOGGING` is unset), the library uses `log_info` / `log_warning` from it. Otherwise minimal fallback functions are provided:

```bash
# With logging.sh
source /path/to/logging.sh
source /path/to/retry.sh
# Uses log_info, log_warning from logging.sh

# Without logging.sh (or RETRY_DISABLE_LOGGING=1)
source /path/to/retry.sh
# Uses plain echo fallbacks
```

## Why Jitter?

Without jitter, many clients that fail at the same moment (e.g. after a shared
backend blip) retry in lockstep, hammering the backend in synchronized waves —
the *thundering herd* problem. Adding a random `0..RETRY_JITTER` offset spreads
the retries out. Enable it (`RETRY_JITTER>0`) whenever more than one instance of
your script may back off against the same dependency.

## Examples

### Self-Healing Supervise Loop

`calculate_backoff` is the building block for an unbounded reconnect loop where a
fixed attempt cap does not fit (e.g. a daemon that must keep a connection alive):

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh
source /path/to/utilities/retry.sh

export RETRY_BASE_DELAY=2 RETRY_MAX_DELAY=30 RETRY_JITTER=3

attempt=0
while true; do
    if my_long_running_command; then
        log_notice "Process exited cleanly"
        attempt=0                       # reset backoff after a clean run
    else
        ((attempt++)) || true
        log_warning "Process crashed (consecutive failures: ${attempt})"
    fi

    delay=$(calculate_backoff "$attempt")
    log_info "Restarting in ${delay}s"
    sleep "$delay"
done
```

See [`examples/07-self-healing-daemon.sh`](../../examples/07-self-healing-daemon.sh)
for a complete version with a single-instance lock, a precondition gate, and
optional alerting.

### Bounded Retry of a One-Shot Command

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh
source /path/to/utilities/retry.sh

# Mirror a release artifact, retrying transient network failures
if retry_with_backoff 4 wget -q -O /tmp/release.tar.gz "https://example.com/release.tar.gz"; then
    log_info "Download complete"
else
    log_error "Download failed after 4 attempts"
    exit 1
fi
```

## Technical Notes

### Overflow-Safe Doubling

The exponential growth uses a bounded loop instead of `delay=$((base * 2 ** attempt))`:

```bash
for ((i = 0; i < attempt && i < 30; i++)); do
    delay=$((delay * 2))
    [[ $delay -ge $RETRY_MAX_DELAY ]] && break
done
```

This avoids two pitfalls of the `**` operator: integer overflow on large attempt
counts, and a single huge intermediate value before the cap is applied. The loop
short-circuits as soon as the cap is reached.

### Exit Code Propagation

`retry_with_backoff` captures the command's exit code directly rather than via
`if cmd; then`. A failing `if` condition with no `else` resets `$?` to `0` in
Bash, which would otherwise mask the real failure code.

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [LOGGING.md](../foundation/LOGGING.md) - Optional logging integration
- [Examples README](../../examples/README.md) - Ready-to-run example scripts
