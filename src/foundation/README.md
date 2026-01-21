# Foundation Libraries

## ⚡ TL;DR

Core Bash libraries for production scripts: logging.sh (journald/JSON/file rotation), secure-file-utils.sh (atomic writes, race-condition prevention), error-handling.sh (domain-specific error recovery), simple-logging.sh (lightweight for hooks/cross-platform).

---

## Overview

Foundation libraries provide essential functionality for production-grade Bash scripts:

- **Structured Logging** - Multiple backends (journald, files, JSON)
- **Atomic File Operations** - Race-condition prevention, secure temp files
- **Error Handling** - Domain-specific handlers with automatic recovery
- **Lightweight Logging** - Minimal logging for hooks and cross-platform scripts

## Libraries

### logging.sh

**Purpose**: Structured logging with multiple backends

**Key Features**:
- Journald integration via `systemd-cat`
- JSON output for log aggregation
- File-based logging with rotation
- Contextual logging with tags
- Performance: ~0.01s per log call

**Key Functions**:
```bash
log_info "message"              # Info level logging
log_error "message"             # Error level logging
log_success "message"           # Success level logging
log_warn "message"              # Warning level logging
log_debug "message"             # Debug level logging
log_with_context "tag" "msg"    # Contextual logging
```

**Documentation**: [LOGGING.md](../../docs/foundation/LOGGING.md)

---

### simple-logging.sh

**Purpose**: Lightweight logging for hooks and cross-platform scripts

**Key Features**:
- No external dependencies (no systemd-cat, no logger)
- Color-coded output (RED, YELLOW, GREEN, BLUE)
- Timestamp prefixes
- Suitable for Git hooks and portable scripts

**Key Functions**:
```bash
log "message"                   # Info level (blue)
warn "message"                  # Warning level (yellow)
error "message"                 # Error level (red)
success "message"               # Success level (green)
```

**Documentation**: [LOGGING.md § simple-logging.sh](../../docs/foundation/LOGGING.md#simple-loggingsh)

---

### secure-file-utils.sh

**Purpose**: Atomic file operations with race-condition prevention

**Key Features**:
- Atomic writes via temp files + `mv`
- Path validation (symlink resolution, directory traversal prevention)
- Permission management (644, 600, 755)
- Backup creation before overwrites
- Performance: ~0.02s per operation

**Key Functions**:
```bash
sfu_write_file "content" "path" "permissions"   # Atomic write
sfu_atomic_copy "src" "dest"                    # Atomic copy
sfu_validate_path "path"                        # Path validation
sfu_create_backup "path"                        # Backup creation
```

**Documentation**: [SECURE_FILE_UTILS.md](../../docs/foundation/SECURE_FILE_UTILS.md)

---

### error-handling.sh

**Purpose**: Domain-specific error handlers with automatic recovery

**Key Features**:
- Docker error handling (container restart, network issues)
- Network error handling (retry logic, backoff)
- systemd error handling (service restart, dependency resolution)
- File operation error handling (permission fixes, disk space checks)

**Key Functions**:
```bash
handle_docker_error "container_name"            # Docker error recovery
handle_network_error "operation"                # Network retry logic
handle_systemd_error "service_name"             # Service recovery
handle_file_error "path" "operation"            # File operation recovery
```

**Documentation**: [ERROR_HANDLING.md](../../docs/foundation/ERROR_HANDLING.md)

## Usage Example

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source foundation libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"
source "${TOOLKIT}/foundation/error-handling.sh"

# Use logging
log_info "Application started"

# Use secure file operations
if sfu_write_file "config data" "/var/lib/myapp/config.txt" "644"; then
    log_success "Configuration saved"
else
    error_code=$?
    log_error "Failed to write config (exit code: $error_code)"
    handle_file_error "/var/lib/myapp/config.txt" "write"
fi

# Use error handling
if ! docker start my_container; then
    log_warn "Container failed to start, attempting recovery..."
    handle_docker_error "my_container"
fi
```

## Requirements

- **Bash 4.0+** - All libraries require Bash 4.0 or higher
- **Standard Unix utilities** - coreutils (mkdir, chmod, mv, date, mktemp)
- **Optional**: `systemd-cat`, `logger` (for journald integration in logging.sh)
- **Optional**: `jq` (for JSON logging in logging.sh)

## See Also

- [Back to src/](../README.md)
- [Monitoring Libraries](../monitoring/README.md)
- [Utility Libraries](../utilities/README.md)
- [Setup Guide](../../docs/SETUP.md)
- [Examples](../../examples/README.md)
