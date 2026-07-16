# Logging Libraries

This document covers two logging libraries:
- **logging.sh** (v2.0.0) - Full-featured structured logging (6-level, RFC 5424 aligned)
- **simple-logging.sh** (v1.1.1) - Lightweight logging for simple scripts

## Quick Decision Guide

| Use Case | Library |
|----------|---------|
| systemd services / daemons | logging.sh |
| Production monitoring scripts | logging.sh |
| JSON log aggregation | logging.sh |
| Git hooks | simple-logging.sh |
| Cross-platform scripts (Linux + macOS) | simple-logging.sh |
| Quick utility scripts | simple-logging.sh |

---

# logging.sh (v2.0.0)

Full-featured structured logging with journald integration, JSON output, file rotation, and performance metrics.
6 log levels aligned with RFC 5424 syslog priorities (DEBUG through CRITICAL).

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh

export LOG_LEVEL="INFO"
export LOG_TO_JOURNAL="true"

log_info "Application started"
log_notice "Service ready and accepting connections"  # Significant positive event
log_warning "Configuration not found, using defaults"
log_error "Failed to connect to database"
log_critical "Data corruption detected, halting"
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/foundation/logging.sh
```

## API Reference

### Primary Functions

#### log_info
```bash
log_info "message" [context...]
```
Log an INFO level message with optional KEY=VALUE context.

**Parameters:**
- `message` - The log message
- `context...` - Optional KEY=VALUE pairs

**Example:**
```bash
log_info "User logged in" "USER=alice" "IP=192.168.1.100"
```

#### log_warning
```bash
log_warning "message" [context...]
```
Log a WARNING level message.

#### log_error
```bash
log_error "message" [context...]
```
Log an ERROR level message. Does NOT exit the script.

#### log_debug
```bash
log_debug "message" [context...]
```
Log a DEBUG level message. Only outputs when `LOG_LEVEL=DEBUG`.

#### log_critical
```bash
log_critical "message" [context...]
```
Log a CRITICAL level message for severe errors.

#### log_notice
```bash
log_notice "message" [context...]
```
Log a NOTICE level message. Use for significant but non-warning events:
service started, task completed, configuration loaded, failover successful.

#### log_success _(deprecated)_
```bash
log_success "message" [context...]
```
Deprecated alias for `log_notice()`. Will be removed in v3.0.0.

### Structured Logging Functions

#### log_info_structured
```bash
log_info_structured "message" "FIELD1=value1" "FIELD2=value2"
```
Log with journald-compatible structured fields.

**Example:**
```bash
log_info_structured "Failover completed" \
    "FROM_INTERFACE=eth0" \
    "TO_INTERFACE=lte1" \
    "DURATION_MS=234"
```

Similar functions: `log_notice_structured`, `log_error_structured`, `log_warning_structured`, `log_debug_structured`, `log_critical_structured`

### JSON Logging

#### log_json
```bash
log_json "level" "message" [fields...]
```
Output log as JSON object.

**Example:**
```bash
log_json "INFO" "Request completed" "status=200" "duration=45ms"
# Output: {"timestamp":"2025-01-01T12:00:00Z","level":"INFO","message":"Request completed","status":"200","duration":"45ms"}
```

### Convenience Aliases

For backward compatibility:
- `log()` - Generic log (auto-detects level from message prefix)
- `info()` - Alias for log_info
- `notice()` - Alias for log_notice
- `warn()` / `warning()` - Alias for log_warning
- `error()` - Alias for log_error
- `debug()` - Alias for log_debug
- `critical()` - Alias for log_critical
- `success()` - Alias for log_notice with ✓ prefix (was log_info in v1.x)
- `failure()` - Wrapper with ✗ prefix

### Utility Functions

#### rotate_log
```bash
rotate_log "/path/to/logfile.log"
```
Manually trigger log rotation with gzip compression.

#### json_escape
```bash
escaped=$(json_escape "string with \"quotes\"")
```
Escape a string for safe JSON embedding.

#### get_log_level_value
```bash
value=$(get_log_level_value "WARNING")  # Returns 3
```
Convert level string to numeric value for comparison.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL |
| `LOG_FORMAT` | `standard` | Output format: standard, json, compact |
| `LOG_TO_JOURNAL` | `false` | Enable journald integration |
| `LOG_TO_STDOUT` | `true` | Output to terminal |
| `LOG_FILE` | `${LOG_DIR}/${SCRIPT_NAME}.log` | Custom log file path |
| `LOG_DIR` | `/var/log` | Log directory |
| `LOG_ROTATE_SIZE` | `10M` | Rotation trigger size |
| `LOG_ROTATE_COUNT` | `5` | Number of rotated logs to keep |
| `LOG_PERFORMANCE` | `true` | Enable performance metrics on exit |
| `APP_ENV` | (auto-detected) | Override environment: prod, dev, test |
| `CORRELATION_ID` | (auto-generated) | Request tracking ID |
| `SCRIPT_NAME` | (auto-detected) | Script identifier for logs |

> **Source-time initialization**: These defaults are applied with `:=` when
> `logging.sh` is **sourced**. Set your overrides *before* the `source` line —
> assignments like `LOG_TO_STDOUT="${LOG_TO_STDOUT:-false}"` placed *after*
> sourcing are dead code, because the variable is already set.

### ⚠️ Pitfall: `log_*` inside command-substituted functions

With `LOG_TO_STDOUT=true` (the default), every `log_*` call prints to
**stdout**. If a function that logs is called via command substitution, the log
line becomes part of the captured value:

```bash
get_wan_ip() {
    local ip
    ip=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
    if [[ -z "$ip" ]]; then
        log_warning "eth0 has no IP — using cached value"   # ❌ goes to stdout!
        cat /var/cache/last-ip
    fi
    echo "$ip"
}

wan_ip=$(get_wan_ip)   # wan_ip now contains the WARNING line + the IP
sed -i "s|^ip=.*|ip=${wan_ip}|" app.conf   # multi-line value breaks sed
```

The failure is latent: it only triggers when the logging branch actually runs
(often an error path that tests never hit). In functions whose stdout is
captured, always redirect log calls to stderr:

```bash
log_warning "eth0 has no IP — using cached value" >&2   # ✅ stdout stays clean
```

### Log Levels (RFC 5424 aligned)

| Level | Value | syslog Priority | Use For |
|-------|-------|-----------------|---------|
| DEBUG | 0 | debug (7) | Detailed debugging information |
| INFO | 1 | informational (6) | General operational messages |
| NOTICE | 2 | notice (5) | Significant events, milestones |
| WARNING | 3 | warning (4) | Warning conditions, degraded state |
| ERROR | 4 | error (3) | Error conditions, failed operations |
| CRITICAL | 5 | critical (2) | Critical failures, immediate action required |

**When to use NOTICE vs INFO:**
- `log_info` → routine operations (loop iterations, file reads, checks)
- `log_notice` → significant events (service started, task completed, failover succeeded)

### Level Filtering

```bash
export LOG_LEVEL="WARNING"  # Only WARNING, ERROR, CRITICAL will be logged
log_debug "This won't appear"
log_info "This won't appear"
log_warning "This will appear"
log_error "This will appear"
```

## Examples

### systemd Service Logging

```bash
#!/bin/bash
set -uo pipefail

source /opt/toolkit/foundation/logging.sh

export SCRIPT_NAME="my-service"
export LOG_TO_JOURNAL="true"
export LOG_LEVEL="INFO"

log_info "Service starting"

# Your service logic here

log_success "Service ready"
```

View logs:
```bash
journalctl -t my-service -f
```

### JSON Log Aggregation

```bash
#!/bin/bash
source /path/to/logging.sh

export LOG_FORMAT="json"
export LOG_FILE="/var/log/app/events.json"

log_info "Event processed" "event_id=12345" "type=order"
# {"timestamp":"...","level":"INFO","message":"Event processed","event_id":"12345","type":"order"}
```

### Correlation ID Tracking

```bash
#!/bin/bash
source /path/to/logging.sh

# Auto-generated or set explicitly
export CORRELATION_ID="req-$(uuidgen)"

log_info "Request started"
# ... processing ...
log_info "Request completed"
# Both logs share the same CORRELATION_ID for tracing
```

### Performance Metrics

```bash
#!/bin/bash
source /path/to/logging.sh

export LOG_PERFORMANCE="true"

log_info "Starting batch job"
# ... work ...
log_info "Batch complete"

# On exit, automatically logs:
# [PERF] Script completed in 45.2s | logs=12 errors=0 warnings=2
```

---

# simple-logging.sh (v1.0.0)

Lightweight logging library for git hooks, simple scripts, and cross-platform use.

## Quick Start

```bash
#!/bin/bash

SCRIPT_NAME="my-hook"  # MUST be set BEFORE sourcing (no readonly!)
source /path/to/foundation/simple-logging.sh

log_info "Hook started"
log_success "All checks passed"
```

## Installation

```bash
# IMPORTANT: Set SCRIPT_NAME before sourcing
SCRIPT_NAME="my-script"
source /path/to/bash-production-toolkit/src/foundation/simple-logging.sh
```

**Critical:** Do NOT use `readonly SCRIPT_NAME` before sourcing - the library modifies this variable.

## API Reference

### log_info
```bash
log_info "message"
```
Log INFO level message with ℹ️ emoji.

### log_success
```bash
log_success "message"
```
Log SUCCESS message with ✅ emoji.

### log_warning
```bash
log_warning "message"
```
Log WARNING message with ⚠️ emoji.

### log_error
```bash
log_error "message"
```
Log ERROR message with ❌ emoji.

### log_debug
```bash
log_debug "message"
```
Log DEBUG message with 🔍 emoji. Only shown when `LOG_LEVEL=DEBUG`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SCRIPT_NAME` | basename of script | Script identifier |
| `LOG_FILE` | `~/.cache/bash-toolkit/${SCRIPT_NAME}.log` | Log file path |
| `LOG_TAG` | `${SCRIPT_NAME}` | Tag for syslog |
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, WARNING, ERROR |

## Examples

### Git Pre-commit Hook

```bash
#!/bin/bash

SCRIPT_NAME="pre-commit"
source /path/to/simple-logging.sh

log_info "Running pre-commit checks"

if ! shellcheck scripts/*.sh; then
    log_error "ShellCheck found issues"
    exit 1
fi

log_success "All checks passed"
```

### Cross-Platform Script

```bash
#!/bin/bash
# Works on Linux and macOS

SCRIPT_NAME="backup"
source /path/to/simple-logging.sh

log_info "Starting backup"

if [[ "$(uname)" == "Darwin" ]]; then
    log_debug "Running on macOS"
else
    log_debug "Running on Linux"
fi

log_success "Backup complete"
```

## Comparison: logging.sh vs simple-logging.sh

| Feature | logging.sh | simple-logging.sh |
|---------|------------|-------------------|
| Size | ~350 lines | ~230 lines |
| journald integration | ✅ | ❌ |
| JSON output | ✅ | ❌ |
| Log rotation | ✅ | ❌ |
| Performance metrics | ✅ | ❌ |
| Structured fields | ✅ | ❌ |
| Emoji output | ❌ | ✅ |
| Cross-platform | Linux only | Linux + macOS |
| Dependencies | optional jq, systemd-cat | secure-file-utils.sh |
| Best for | Daemons, services | Hooks, utilities |

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [SECURE_FILE_UTILS.md](SECURE_FILE_UTILS.md) - Used by simple-logging.sh
- [ERROR_HANDLING.md](ERROR_HANDLING.md) - Uses logging.sh
