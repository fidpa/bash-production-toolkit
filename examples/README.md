# Examples

Ready-to-run examples demonstrating the Bash Production Toolkit libraries.

## Prerequisites

```bash
cd bash-production-toolkit
```

For alerting examples, set webhook URL:
```bash
export ALERT_WEBHOOK_URL="https://your-webhook-endpoint/TOKEN"
```

## Examples

| Script | Demonstrates | Libraries Used |
|--------|--------------|----------------|
| `01-logging-basics.sh` | Log levels, aliases, structured logging | logging.sh |
| `02-file-operations.sh` | Atomic writes, permissions, path validation | logging.sh, secure-file-utils.sh |
| `03-webhook-alerts.sh` | Alerts, rate limiting, severity auto-derivation | logging.sh, alerts.sh |
| `04-device-detection.sh` | Device detection, architecture, conditional execution | logging.sh, device-detection.sh |
| `05-error-handling.sh` | Error handlers, safe execution, recovery | logging.sh, error-handling.sh |
| `06-monitoring-script.sh` | Complete monitoring script | All libraries |
| `07-self-healing-daemon.sh` | Crash-resilient supervise loop: backoff, lock, precondition gate, alerting | retry.sh, logging.sh, secure-file-utils.sh, alerts.sh |

## Running Examples

```bash
# Basic examples (no external dependencies)
./examples/01-logging-basics.sh
./examples/02-file-operations.sh
./examples/04-device-detection.sh
./examples/05-error-handling.sh
./examples/07-self-healing-daemon.sh   # runs a bundled demo workload; ALERT_WEBHOOK_URL optional

# Alerting examples (require webhook URL)
export ALERT_WEBHOOK_URL="https://your-webhook/TOKEN"
./examples/03-webhook-alerts.sh
./examples/06-monitoring-script.sh
```

## Creating Your Own Scripts

Use this template:

```bash
#!/bin/bash
set -uo pipefail

# Define toolkit location
TOOLKIT="/path/to/bash-production-toolkit/src"

# Source libraries you need
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

# Your script logic
log_info "Starting..."

# ... your code ...

log_info "Done"
```

## See Also

- [Back to Root README](../README.md)
- [Documentation](../docs/README.md)
- [Source Libraries](../src/README.md)
- [Setup Guide](../docs/SETUP.md)
- [Troubleshooting](../docs/TROUBLESHOOTING.md)
