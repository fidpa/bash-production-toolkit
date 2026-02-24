# Bash Production Toolkit - Source Libraries

## ⚡ TL;DR

9 production-ready Bash libraries organized in 3 categories: foundation (logging, file utils, error handling), monitoring (alerts, smart-alerts), utilities (device detection, path calculation, backup safety). Source individually or use init.sh.

---

## Library Overview

All libraries are organized into three categories based on their purpose:

| Category | Libraries | Purpose |
|----------|-----------|---------|
| **Foundation** | 4 libraries | Core functionality (logging, file operations, error handling) |
| **Monitoring** | 2 libraries | Alerting and event tracking |
| **Utilities** | 3 libraries | Helper functions (device detection, path utilities, backup validation) |

## Quick Reference

### Foundation Libraries

Located in `src/foundation/`:

| Library | Purpose | Key Functions |
|---------|---------|---------------|
| [logging.sh](../docs/foundation/LOGGING.md) | Structured logging with journald, JSON, file rotation | `log_info()`, `log_error()`, `log_success()` |
| [simple-logging.sh](../docs/foundation/LOGGING.md#simple-loggingsh) | Lightweight logging for hooks and cross-platform scripts | `log()`, `warn()`, `error()` |
| [secure-file-utils.sh](../docs/foundation/SECURE_FILE_UTILS.md) | Atomic file operations, path validation | `sfu_write_file()`, `sfu_atomic_copy()` |
| [error-handling.sh](../docs/foundation/ERROR_HANDLING.md) | Domain-specific error handlers with recovery | `handle_docker_error()`, `handle_network_error()` |

### Monitoring Libraries

Located in `src/monitoring/`:

| Library | Purpose | Key Functions |
|---------|---------|---------------|
| [alerts.sh](../docs/monitoring/ALERTS.md) | Generic webhook alerts with rate limiting (Mattermost/Slack/Discord) | `send_alert()`, `send_recovery_alert()` |
| [smart-alerts.sh](../docs/monitoring/SMART_ALERTS.md) | Event tracking with grace periods and recovery | `track_event()`, `is_in_grace_period()` |

### Utility Libraries

Located in `src/utilities/`:

| Library | Purpose | Key Functions |
|---------|---------|---------------|
| [backup-safety.sh](../docs/utilities/BACKUP_SAFETY.md) | Backup target validation, mountpoint checks | `check_backup_target()`, `check_mountpoint()` |
| [device-detection.sh](../docs/utilities/DEVICE_DETECTION.md) | Multi-device identification and routing | `detect_device()`, `on_device()` |
| [path-calculator.sh](../docs/utilities/PATH_CALCULATOR.md) | Relative path calculation for documentation tools | `calculate_relative_path()` |

## Usage

### Individual Library Sourcing

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source only what you need
source /path/to/bash-production-toolkit/src/foundation/logging.sh
source /path/to/bash-production-toolkit/src/foundation/secure-file-utils.sh

# Use the functions
log_info "Application started"
sfu_write_file "config data" "/var/lib/myapp/config.txt" "644"
```

### Using init.sh (Recommended)

```bash
#!/usr/bin/env bash
set -uo pipefail

# Initialize toolkit
export BASH_PRODUCTION_TOOLKIT="/path/to/bash-production-toolkit"
source "${BASH_PRODUCTION_TOOLKIT}/init.sh"

# Source libraries using BASH_TOOLKIT_LIB
source "${BASH_TOOLKIT_LIB}/foundation/logging.sh"
source "${BASH_TOOLKIT_LIB}/monitoring/alerts.sh"
```

## Subdirectories

- **[foundation/](foundation/)** - Core libraries (logging, file operations, error handling)
- **[monitoring/](monitoring/)** - Alerting and event tracking libraries
- **[utilities/](utilities/)** - Helper libraries (device detection, path utilities, backup safety)

## Requirements

- **Bash 4.0+** - All libraries require Bash 4.0 or higher
- **Standard Unix utilities** - coreutils (mkdir, chmod, mv, date)
- **Optional**: `jq` (for JSON features in logging and smart-alerts)
- **Optional**: `curl` (for webhook alerts)
- **Optional**: `systemd-cat`, `logger` (for journald integration)

## See Also

- [Back to Root README](../README.md)
- [Documentation](../docs/README.md)
- [Setup Guide](../docs/SETUP.md)
- [Examples](../examples/README.md)
- [Architecture](../docs/ARCHITECTURE.md)
