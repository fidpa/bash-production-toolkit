# Architecture

This document describes the design patterns, dependencies, and conventions used across the bash-production-toolkit libraries.

## Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                      YOUR SCRIPT                            │
└─────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  smart-alerts   │  │ error-handling  │  │ device-detection│
│    (v1.1.0)     │  │    (v2.0.0)     │  │    (v1.2.0)     │
└────────┬────────┘  └────────┬────────┘  └─────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│     alerts      │  │    logging      │◄─────────────────────┐
│    (v1.1.0)     │  │    (v2.8.1)     │                      │
└────────┬────────┘  └────────┬────────┘                      │
         │                    │                               │
         ▼                    ▼                               │
┌─────────────────────────────────────────┐          ┌────────┴────────┐
│         secure-file-utils (v1.6.1)      │          │ path-calculator │
│              (FOUNDATION)               │          │    (v1.1)       │
└─────────────────────────────────────────┘          └─────────────────┘
```

### Dependency Matrix

| Library | Required Dependencies | Optional Dependencies |
|---------|----------------------|----------------------|
| **secure-file-utils.sh** | (none) | - |
| **logging.sh** | (none) | secure-file-utils.sh |
| **simple-logging.sh** | secure-file-utils.sh | - |
| **error-handling.sh** | logging.sh | - |
| **alerts.sh** | (none) | logging.sh, secure-file-utils.sh |
| **smart-alerts.sh** | jq, alerts.sh | logging.sh, secure-file-utils.sh |
| **device-detection.sh** | (none) | yq |
| **path-calculator.sh** | (none) | logging.sh |

## Include Guard Pattern

All libraries use include guards to prevent double-sourcing:

```bash
# At the top of each library
[[ -n "${_LIBRARY_NAME_LOADED:-}" ]] && return 0
readonly _LIBRARY_NAME_LOADED=true
```

This allows safe multiple sourcing:

```bash
# Both files source logging.sh - no conflict
source /path/to/logging.sh
source /path/to/error-handling.sh  # Also sources logging.sh internally
```

### Guard Variables

| Library | Guard Variable |
|---------|---------------|
| logging.sh | `_LOGGING_LOADED` |
| simple-logging.sh | `_SIMPLE_LOGGING_LOADED` |
| secure-file-utils.sh | `_SECURE_FILE_UTILS_LOADED` |
| error-handling.sh | `_ERROR_HANDLING_LOADED` |
| alerts.sh | `MONITORING_ALERTS_LOADED` |
| smart-alerts.sh | `SMART_ALERTS_LOADED` |
| device-detection.sh | `DEVICE_DETECTION_LOADED` |
| path-calculator.sh | `PATH_CALCULATOR_LOADED` |

## Error Handling Philosophy

### Libraries vs Scripts

**Libraries** (this toolkit):
- Use `set -uo pipefail` (NOT `-e`)
- Return error codes instead of exiting
- Never call `exit` directly
- Provide error messages via dedicated error functions

**Scripts** (your code):
- Can use `set -euo pipefail` safely
- Handle library return codes appropriately
- Decide when to exit

### Return Code Convention

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error / invalid input |
| 10 | Network error |
| 20 | Docker error |
| 30 | Filesystem error |
| 40 | Permission error |
| 50 | Configuration error |
| 60 | Service error |

## State Management

### State Directories

Libraries that maintain state use these patterns:

```bash
# Prefer systemd StateDirectory if available
STATE_DIR="${STATE_DIRECTORY:-/var/lib/myapp}"

# Ensure directory exists
mkdir -p "${STATE_DIR}"
```

### Atomic State Updates

All state file writes use atomic patterns via `secure-file-utils.sh`:

```bash
# Atomic write: temp file → chmod → mv
sfu_write_file "${new_state}" "${STATE_DIR}/state.json"
```

This prevents:
- Partial writes during crash
- Race conditions between readers/writers
- Corrupted state files

## Logging Integration

### Fallback Pattern

Libraries that optionally use logging.sh provide fallbacks:

```bash
# Check if logging.sh is loaded
if [[ -n "${_LOGGING_LOADED:-}" ]]; then
    log_info "Message using logging.sh"
else
    echo "[INFO] Message using echo fallback" >&2
fi
```

### Common Pattern

```bash
# Define fallback functions if logging.sh not loaded
if ! declare -f log_info >/dev/null 2>&1; then
    log_info() { echo "[INFO] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${VERBOSE:-}" == "true" ]] && echo "[DEBUG] $*" >&2; }
fi
```

## Configuration Pattern

### Environment Variables

All configuration uses environment variables with sensible defaults:

```bash
# Pattern: ${VAR:-default}
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_DIR="${LOG_DIR:-/var/log}"
STATE_DIR="${STATE_DIR:-/var/lib/myapp}"
```

### Configuration Precedence

1. Environment variable (highest priority)
2. Config file (if supported)
3. Built-in default (lowest priority)

## External Dependencies

### Required System Utilities

All libraries assume these are available:
- `date`, `mkdir`, `chmod`, `mv`, `rm`
- `basename`, `dirname`, `realpath`
- `cat`, `grep`, `sed`

### Optional External Tools

| Tool | Used By | Purpose |
|------|---------|---------|
| `jq` | smart-alerts.sh, logging.sh | JSON processing |
| `curl` | alerts.sh | HTTP requests (Telegram API) |
| `yq` | device-detection.sh | YAML parsing |
| `systemd-cat` | logging.sh | journald integration |
| `logger` | logging.sh, simple-logging.sh | syslog integration |
| `uuidgen` | logging.sh | Correlation ID generation |
| `md5sum` | alerts.sh | Content hashing |
| `gzip` | logging.sh | Log rotation compression |

## Source Order

When using multiple libraries, source in dependency order:

```bash
#!/bin/bash
set -euo pipefail

TOOLKIT="/path/to/bash-production-toolkit/src"

# 1. Foundation (no dependencies)
source "${TOOLKIT}/foundation/secure-file-utils.sh"
source "${TOOLKIT}/foundation/logging.sh"

# 2. Libraries that depend on foundation
source "${TOOLKIT}/foundation/error-handling.sh"

# 3. Monitoring (depends on foundation)
source "${TOOLKIT}/monitoring/alerts.sh"
source "${TOOLKIT}/monitoring/smart-alerts.sh"

# 4. Utilities (mostly independent)
source "${TOOLKIT}/utilities/device-detection.sh"
source "${TOOLKIT}/utilities/path-calculator.sh"
```

Note: Include guards make the order less critical, but sourcing in dependency order is cleaner.

## Naming Conventions

### Functions

| Library | Prefix | Example |
|---------|--------|---------|
| secure-file-utils.sh | `sfu_` | `sfu_write_file` |
| alerts.sh | `send_` | `send_telegram_alert` |
| smart-alerts.sh | `sa_` | `sa_register_event` |
| path-calculator.sh | `pc_` (internal) | `calculate_relative_path` |
| device-detection.sh | (none) | `detect_device` |
| logging.sh | `log_` | `log_info` |

### Internal Functions

Internal functions use underscore prefix:

```bash
_sfu_error()           # Internal to secure-file-utils.sh
_send_telegram_message()  # Internal to alerts.sh
_detect_by_ip()        # Internal to device-detection.sh
```

## Testing

### Self-Test Pattern

Some libraries include self-tests when run directly:

```bash
# Run library self-test
bash /path/to/path-calculator.sh

# With verbose output
VERBOSE=true bash /path/to/path-calculator.sh
```

### Test Your Integration

```bash
#!/bin/bash
set -euo pipefail

source /path/to/logging.sh

# Test logging
log_info "Test message"
log_error "Test error"
log_debug "Debug (only shown if LOG_LEVEL=DEBUG)"
```

## Performance Considerations

### Function Export

Only `logging.sh` exports functions for subprocess visibility:

```bash
export -f log_info log_error log_warn log_debug
```

Other libraries expect to be sourced in the same shell.

### Caching

- `device-detection.sh` caches detection results in `_DETECTED_DEVICE`
- `logging.sh` caches `CORRELATION_ID` for the session

### File I/O

- Atomic writes add ~5ms overhead vs direct echo
- Worth it for data integrity
- Use direct writes only for truly temporary data
