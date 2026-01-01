# Examples

Ready-to-run examples demonstrating the Bash Production Toolkit libraries.

## Prerequisites

```bash
cd bash-production-toolkit
```

For alerting examples, set Telegram credentials:
```bash
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"
```

## Examples

| Script | Demonstrates | Libraries Used |
|--------|--------------|----------------|
| `01-logging-basics.sh` | Log levels, aliases, structured logging | logging.sh |
| `02-file-operations.sh` | Atomic writes, permissions, path validation | logging.sh, secure-file-utils.sh |
| `03-telegram-alerts.sh` | Alerts, rate limiting, smart deduplication | logging.sh, alerts.sh |
| `04-device-detection.sh` | Device detection, architecture, conditional execution | logging.sh, device-detection.sh |
| `05-error-handling.sh` | Error handlers, safe execution, recovery | logging.sh, error-handling.sh |
| `06-monitoring-script.sh` | Complete monitoring script | All libraries |

## Running Examples

```bash
# Basic examples (no external dependencies)
./examples/01-logging-basics.sh
./examples/02-file-operations.sh
./examples/04-device-detection.sh
./examples/05-error-handling.sh

# Telegram examples (require credentials)
export TELEGRAM_BOT_TOKEN="..."
export TELEGRAM_CHAT_ID="..."
./examples/03-telegram-alerts.sh
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
