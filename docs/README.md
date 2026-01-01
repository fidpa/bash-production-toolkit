# Bash Production Toolkit Documentation

A collection of production-ready Bash libraries for logging, file operations, error handling, alerting, and system detection.

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

# Source the libraries you need
source /path/to/bash-production-toolkit/src/foundation/logging.sh
source /path/to/bash-production-toolkit/src/foundation/secure-file-utils.sh

log_info "Application started"
sfu_write_file "config data" "/var/lib/myapp/config.txt" "644"
log_success "Configuration saved"
```

## Installation

Clone the repository:

```bash
git clone https://github.com/fidpa/bash-production-toolkit.git
cd bash-production-toolkit
```

Source libraries in your scripts:

```bash
TOOLKIT_DIR="/path/to/bash-production-toolkit/src"
source "${TOOLKIT_DIR}/foundation/logging.sh"
```

## Library Overview

| Library | Purpose | Use When |
|---------|---------|----------|
| [logging.sh](foundation/LOGGING.md) | Structured logging with journald, JSON, file rotation | Production daemons, systemd services |
| [simple-logging.sh](foundation/LOGGING.md#simple-loggingsh) | Lightweight logging with emoji | Git hooks, simple scripts, cross-platform |
| [secure-file-utils.sh](foundation/SECURE_FILE_UTILS.md) | Atomic file operations | Writing config files, state files, metrics |
| [error-handling.sh](foundation/ERROR_HANDLING.md) | Domain-specific error handlers | Docker, network, systemd error recovery |
| [alerts.sh](monitoring/ALERTS.md) | Telegram alerts with rate limiting | Monitoring, alerting systems |
| [smart-alerts.sh](monitoring/SMART_ALERTS.md) | Event tracking with grace periods | Flap prevention, intelligent alerting |
| [device-detection.sh](utilities/DEVICE_DETECTION.md) | Multi-device detection | Scripts running on multiple hosts |
| [path-calculator.sh](utilities/PATH_CALCULATOR.md) | Path utilities for documentation | Link validation, markdown tools |

## Library Selection Guide

### I need to...

**Log messages from a systemd service**
→ Use [logging.sh](foundation/LOGGING.md) with `LOG_TO_JOURNAL=true`

**Write a simple git hook**
→ Use [simple-logging.sh](foundation/LOGGING.md#simple-loggingsh) (lightweight, cross-platform)

**Write files atomically (prevent corruption)**
→ Use [secure-file-utils.sh](foundation/SECURE_FILE_UTILS.md)

**Handle Docker container failures**
→ Use [error-handling.sh](foundation/ERROR_HANDLING.md) with `handle_docker_error`

**Send Telegram alerts without spam**
→ Use [alerts.sh](monitoring/ALERTS.md) with rate limiting

**Avoid alert flapping (brief outages)**
→ Use [smart-alerts.sh](monitoring/SMART_ALERTS.md) with grace periods

**Detect which server my script runs on**
→ Use [device-detection.sh](utilities/DEVICE_DETECTION.md)

**Calculate relative paths between files**
→ Use [path-calculator.sh](utilities/PATH_CALCULATOR.md)

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for:
- Dependency graph between libraries
- Include guard patterns
- Error handling philosophy
- State management patterns

## Directory Structure

```
src/
├── foundation/           # Core libraries (no external dependencies)
│   ├── logging.sh        # Structured logging (v1.0.0)
│   ├── simple-logging.sh # Lightweight logging (v1.0.0)
│   ├── secure-file-utils.sh  # Atomic file ops (v1.0.0)
│   └── error-handling.sh # Error handlers (v1.0.0)
├── monitoring/           # Alerting libraries
│   ├── alerts.sh         # Telegram alerts (v1.0.0)
│   └── smart-alerts.sh   # Event tracking (v1.0.0)
└── utilities/            # Helper libraries
    ├── device-detection.sh   # Device detection (v1.0.0)
    └── path-calculator.sh    # Path utilities (v1.0.0)
```

## Requirements

- Bash 4.0+ (for associative arrays)
- Standard Unix utilities: `date`, `mkdir`, `chmod`, `mv`
- Optional: `jq` (for JSON logging and smart-alerts)
- Optional: `curl` (for Telegram alerts)
- Optional: `systemd-cat`, `logger` (for journald integration)

## Compatibility

- Linux (primary target)
- macOS (simple-logging.sh, path-calculator.sh)
- Works with `set -euo pipefail` (strict mode safe)

## License

MIT License - See [LICENSE](../LICENSE) for details.

## Documentation Index

### Getting Started
- [SETUP.md](SETUP.md) - Installation, configuration, systemd integration
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [ARCHITECTURE.md](ARCHITECTURE.md) - Library dependencies and patterns

### Foundation Libraries
- [LOGGING.md](foundation/LOGGING.md) - logging.sh and simple-logging.sh
- [SECURE_FILE_UTILS.md](foundation/SECURE_FILE_UTILS.md) - Atomic file operations
- [ERROR_HANDLING.md](foundation/ERROR_HANDLING.md) - Domain error handlers

### Monitoring Libraries
- [ALERTS.md](monitoring/ALERTS.md) - Telegram alerts with rate limiting
- [SMART_ALERTS.md](monitoring/SMART_ALERTS.md) - Event tracking with grace periods

### Utility Libraries
- [DEVICE_DETECTION.md](utilities/DEVICE_DETECTION.md) - Multi-device detection
- [PATH_CALCULATOR.md](utilities/PATH_CALCULATOR.md) - Path calculation utilities

### Examples
- [Examples README](../examples/README.md) - Ready-to-run example scripts
