# Bash Production Toolkit

![CI](https://github.com/fidpa/bash-production-toolkit/actions/workflows/ci.yml/badge.svg)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen?logo=gnu-bash)
![Release](https://img.shields.io/github/v/release/fidpa/bash-production-toolkit)
![Maintained](https://img.shields.io/badge/Maintained-yes-brightgreen.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Bash 4.0+](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![Libraries](https://img.shields.io/badge/Libraries-10-orange)
![Last Commit](https://img.shields.io/github/last-commit/fidpa/bash-production-toolkit)

Production-ready Bash libraries for logging, file operations, error handling, alerting, and system detection.

## Features

- **Structured Logging** - journald integration, JSON output, log rotation
- **Atomic File Operations** - Race-condition prevention, secure temp files
- **Domain Error Handlers** - Docker, network, systemd error recovery
- **Alert System** - Generic webhook alerts (Mattermost/Slack/Discord) with rate limiting
- **Device Detection** - Multi-device support with architecture detection
- **Path Utilities** - Relative path calculation, markdown-aware operations
- **Retry & Backoff** - Exponential backoff with jitter, bounded retries

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

# Source the libraries
source /path/to/bash-production-toolkit/src/foundation/logging.sh
source /path/to/bash-production-toolkit/src/foundation/secure-file-utils.sh

# Use them
log_info "Application started"
sfu_write_file "config data" "/var/lib/myapp/config.txt"
log_notice "Configuration saved"
```

## Installation

```bash
git clone https://github.com/fidpa/bash-production-toolkit.git
```

Then source the libraries you need in your scripts:

```bash
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
```

## Libraries

### Foundation

| Library | Purpose |
|---------|---------|
| [logging.sh](docs/foundation/LOGGING.md) | Structured logging with journald, JSON, file rotation |
| [simple-logging.sh](docs/foundation/LOGGING.md#simple-loggingsh) | Lightweight logging for hooks and cross-platform scripts |
| [secure-file-utils.sh](docs/foundation/SECURE_FILE_UTILS.md) | Atomic file operations, path validation |
| [error-handling.sh](docs/foundation/ERROR_HANDLING.md) | Domain-specific error handlers with recovery |

### Monitoring

| Library | Purpose |
|---------|---------|
| [alerts.sh](docs/monitoring/ALERTS.md) | Generic webhook alerts with rate limiting (Mattermost/Slack/Discord) |
| [smart-alerts.sh](docs/monitoring/SMART_ALERTS.md) | Event tracking with grace periods |

### Utilities

| Library | Purpose |
|---------|---------|
| [backup-safety.sh](docs/utilities/BACKUP_SAFETY.md) | Backup target validation, mountpoint checks |
| [device-detection.sh](docs/utilities/DEVICE_DETECTION.md) | Multi-device identification and routing |
| [path-calculator.sh](docs/utilities/PATH_CALCULATOR.md) | Path manipulation for documentation tools |
| [retry.sh](docs/utilities/RETRY.md) | Exponential backoff and bounded retry for unreliable operations |

## Requirements

- Bash 4.0+
- Standard Unix utilities (coreutils)
- Optional: `jq` (for JSON features), `curl` (for webhook alerts)

## Documentation

Full documentation is available in the [docs/](docs/) directory:

- [Overview](docs/README.md)
- [Setup Guide](docs/SETUP.md) - Installation, configuration, systemd integration
- [Architecture](docs/ARCHITECTURE.md) - Library dependencies and patterns
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

### Library Documentation
- [Foundation Libraries](docs/foundation/) - Logging, file operations, error handling
- [Monitoring Libraries](docs/monitoring/) - Webhook alerts, smart alerts
- [Utility Libraries](docs/utilities/) - Device detection, path utilities

## Examples

See the [examples/](examples/) directory for ready-to-run scripts:

```bash
./examples/01-logging-basics.sh
./examples/02-file-operations.sh
./examples/03-webhook-alerts.sh
./examples/07-self-healing-daemon.sh   # resilient supervise loop (retry + lock + alerts)
```

## Testing

The repository ships a dependency-free test suite (pure Bash, no `bats`):

```bash
bash tests/run-all.sh
```

It runs unit tests for `retry.sh` and a smoke test that executes the
dependency-free examples. CI (`ci.yml`) runs ShellCheck, a Bash syntax check,
and this suite on every push and pull request.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- 🐛 **Bug Reports**: [Open an issue](https://github.com/fidpa/bash-production-toolkit/issues/new?template=bug_report.md)
- 💡 **Feature Requests**: [Request a feature](https://github.com/fidpa/bash-production-toolkit/issues/new?template=feature_request.md)
- 🔧 **Pull Requests**: Fork, make changes, submit PR

## Support

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/fidpa/bash-production-toolkit/issues)
- 🔒 **Security**: See [SECURITY.md](SECURITY.md)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))
