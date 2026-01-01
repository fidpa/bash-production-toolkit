# Logging Libraries

This document covers two logging libraries:
- **logging.sh** (v2.8.1) - Full-featured structured logging
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

# logging.sh (v2.8.1)

Full-featured structured logging with journald integration, JSON output, file rotation, and performance metrics.

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh

export LOG_LEVEL="INFO"
export LOG_TO_JOURNAL="true"

log_info "Application started"
log_warn "Configuration not found, using defaults"
log_error "Failed to connect to database"
log_success "Migration completed"
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

#### log_warn
```bash
log_warn "message" [context...]
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

#### log_success
```bash
log_success "message" [context...]
```
Log a success message (alias for log_info with success semantics).

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

Similar functions: `log_error_structured`, `log_warn_structured`, `log_debug_structured`, `log_critical_structured`

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
- `warn()` / `warning()` - Alias for log_warn
- `error()` - Alias for log_error
- `debug()` - Alias for log_debug
- `critical()` - Alias for log_critical
- `success()` - Wrapper with ✓ prefix
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
value=$(get_log_level_value "WARN")  # Returns 30
```
Convert level string to numeric value for comparison.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, WARN, ERROR, CRITICAL |
| `LOG_FORMAT` | `standard` | Output format: standard, json, compact |
| `LOG_TO_JOURNAL` | `false` | Enable journald integration |
| `LOG_TO_STDOUT` | `true` | Output to terminal |
| `LOG_FILE` | `${LOG_DIR}/${SCRIPT_NAME}.log` | Custom log file path |
| `LOG_DIR` | `/var/log` | Log directory |
| `LOG_ROTATE_SIZE` | `10M` | Rotation trigger size |
| `LOG_ROTATE_COUNT` | `5` | Number of rotated logs to keep |
| `LOG_PERFORMANCE` | `true` | Enable performance metrics on exit |
| `CORRELATION_ID` | (auto-generated) | Request tracking ID |
| `SCRIPT_NAME` | (auto-detected) | Script identifier for logs |

### Log Levels

| Level | Value | Use For |
|-------|-------|---------|
| DEBUG | 10 | Detailed debugging information |
| INFO | 20 | General operational messages |
| WARN | 30 | Warning conditions |
| ERROR | 40 | Error conditions |
| CRITICAL | 50 | Critical failures |

### Level Filtering

```bash
export LOG_LEVEL="WARN"  # Only WARN, ERROR, CRITICAL will be logged
log_debug "This won't appear"
log_info "This won't appear"
log_warn "This will appear"
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

# simple-logging.sh (v1.1.1)

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

### log_warn
```bash
log_warn "message"
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
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, WARN, ERROR |

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
