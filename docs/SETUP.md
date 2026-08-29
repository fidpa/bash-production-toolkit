# Setup Guide

## ⚡ TL;DR

Clone repo → Source libraries → Set ALERT_WEBHOOK_URL → Create state dirs (/var/lib/alerts) → Integrate with systemd. Prerequisites: Bash 4.0+, optional jq/curl.

---

Complete installation and configuration guide for the Bash Production Toolkit.

## Prerequisites

- **Bash 4.0+** (check with `bash --version`)
- **Standard Unix utilities** (coreutils: `mkdir`, `chmod`, `mv`, `date`)
- **Optional**: `jq` (for JSON logging and smart-alerts)
- **Optional**: `curl` (for webhook alerts)
- **Optional**: `systemd-cat`, `logger` (for journald integration)

## Installation

### Option 1: Clone Repository

```bash
git clone https://github.com/fidpa/bash-production-toolkit.git
cd bash-production-toolkit
```

### Option 2: Download Specific Libraries

```bash
# Download only what you need
curl -O https://raw.githubusercontent.com/fidpa/bash-production-toolkit/main/src/foundation/logging.sh
curl -O https://raw.githubusercontent.com/fidpa/bash-production-toolkit/main/src/foundation/secure-file-utils.sh
```

### Option 3: System-Wide Installation

```bash
sudo mkdir -p /usr/local/lib/bash-production-toolkit
sudo cp -r src/* /usr/local/lib/bash-production-toolkit/
sudo chmod -R 644 /usr/local/lib/bash-production-toolkit/
sudo chmod 755 /usr/local/lib/bash-production-toolkit/*/
```

## Basic Usage

```bash
#!/bin/bash
set -uo pipefail

# Define toolkit location
TOOLKIT="${TOOLKIT:-/path/to/bash-production-toolkit/src}"

# Source libraries
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/foundation/secure-file-utils.sh"

# Use them
log_info "Script started"
sfu_write_file "data" "/var/lib/myapp/state.txt"
```

## Webhook Alerts Setup

The alerting libraries (`alerts.sh`, `smart-alerts.sh`) require a webhook URL.
Compatible with any Slack-compatible webhook: Mattermost, Slack, Discord, or custom endpoints.

### 1. Get a Webhook URL

**Mattermost**: System Console → Integrations → Incoming Webhooks → Add Incoming Webhook

**Slack**: api.slack.com/apps → Incoming Webhooks → Add New Webhook to Workspace

**Discord**: Server Settings → Integrations → Webhooks → New Webhook
(Append `/slack` to Discord webhook URLs for Slack-compatible format)

### 2. Configure Environment

```bash
export ALERT_WEBHOOK_URL="https://your-service/hooks/TOKEN"
```

Optional settings:
```bash
export ALERTS_PREFIX="[MyServer]"          # Message prefix (default: [System])
export ALERT_WEBHOOK_CACERT="/path/to/ca.crt"  # For self-signed TLS
```

### 3. Test Alert

```bash
source "${TOOLKIT}/monitoring/alerts.sh"
send_alert "SYSTEM_TEST" "Hello from bash-production-toolkit!" "🧪"
```

## Configuration Options

### Logging (logging.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL |
| `LOG_FORMAT` | `standard` | Output format: standard, json, compact |
| `LOG_TO_JOURNAL` | `false` | Enable journald integration |
| `LOG_TO_STDOUT` | `true` | Output to terminal |
| `LOG_FILE` | - | Custom log file path |
| `LOG_DIR` | `/var/log` | Log directory |
| `LOG_ROTATE_SIZE` | `10M` | Rotation threshold |
| `LOG_ROTATE_COUNT` | `5` | Number of rotated logs to keep |

### Alerting (alerts.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `ALERT_WEBHOOK_URL` | (required) | Slack-compatible webhook endpoint URL |
| `ALERT_WEBHOOK_CACERT` | `<not set>` | CA cert path for self-signed TLS |
| `ALERTS_PREFIX` | `[System]` | Message prefix |
| `RATE_LIMIT_SECONDS` | `1800` | Cooldown between same alerts |
| `STATE_DIR` | `/var/lib/alerts` | State file directory |
| `ENABLE_RECOVERY_ALERTS` | `true` | Send recovery notifications |

### Smart Alerts (smart-alerts.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `SMART_ALERT_GRACE_PERIOD` | `180` | Seconds before alerting |
| `SMART_ALERT_RECOVERY_THRESHOLD` | `300` | Minimum downtime for recovery alert |
| `SMART_ALERT_AGGREGATION_WINDOW` | `300` | Seconds in which events are aggregated |
| `SMART_ALERT_STATE_DIR` | `/var/lib/smart-alerts` | State directory |
| `SMART_ALERT_ENABLED` | `true` | Any other value makes the event functions return without acting |

### Device Detection (device-detection.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVICE_CONFIG_FILE` | `devices.yml` next to the library | Device config path, read with yq |
| `DEVICE_OVERRIDE` | - | Force specific device (testing) |

### Retry & Backoff (retry.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `RETRY_BASE_DELAY` | `1` | First delay in seconds, doubled per attempt |
| `RETRY_MAX_DELAY` | `60` | Cap on the delay |
| `RETRY_JITTER` | `0` | Random seconds added on top, 0 turns jitter off |
| `RETRY_DISABLE_LOGGING` | - | Set to any value to skip the logging.sh integration |

### Backup Safety (backup-safety.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_BASE_DIR` | `/opt/backups` | Base directory for `get_backup_path` |
| `BACKUP_MIN_FREE_GB` | `10` | Free space a backup target must have |

All of these are also listed with their defaults in
[config/toolkit.env.example](../config/toolkit.env.example).

## State Directories

Several libraries store state files for rate limiting and event tracking:

```bash
# Create state directories
sudo mkdir -p /var/lib/alerts /var/lib/smart-alerts
sudo chmod 755 /var/lib/alerts /var/lib/smart-alerts

# Or use custom locations
export STATE_DIR="$HOME/.alerts-state"
export SMART_ALERT_STATE_DIR="$HOME/.smart-alerts-state"
mkdir -p "$STATE_DIR" "$SMART_ALERT_STATE_DIR"
```

## systemd Integration

### Service with Logging

```ini
# /etc/systemd/system/my-monitor.service
[Unit]
Description=My Monitoring Script
After=network.target

[Service]
Type=oneshot
Environment=LOG_TO_JOURNAL=true
Environment=LOG_LEVEL=INFO
ExecStart=/usr/local/bin/my-monitor.sh
StateDirectory=alerts

[Install]
WantedBy=multi-user.target
```

Using `StateDirectory=alerts` automatically creates `/var/lib/alerts` with correct permissions.

### Timer for Periodic Checks

```ini
# /etc/systemd/system/my-monitor.timer
[Unit]
Description=Run monitoring every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
```

## Configuration File Pattern

Create a reusable configuration file:

```bash
# /etc/bash-toolkit.conf
TOOLKIT="/usr/local/lib/bash-production-toolkit"

# Logging
LOG_LEVEL=INFO
LOG_TO_JOURNAL=true

# Alerting (webhook-generic: works with Mattermost, Slack, Discord, etc.)
ALERT_WEBHOOK_URL="https://your-webhook-endpoint/TOKEN"
ALERTS_PREFIX="[MyServer]"
RATE_LIMIT_SECONDS=1800

# State directories
STATE_DIR="/var/lib/alerts"
SMART_ALERT_STATE_DIR="/var/lib/smart-alerts"
```

Load in your scripts:

```bash
source /etc/bash-toolkit.conf
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"
```

## Cron Integration

```bash
# /etc/cron.d/my-monitor
TOOLKIT=/usr/local/lib/bash-production-toolkit
ALERT_WEBHOOK_URL=https://your-webhook-endpoint/TOKEN
STATE_DIR=/var/lib/alerts

*/5 * * * * root /usr/local/bin/my-monitor.sh 2>&1 | logger -t my-monitor
```

## Verify Installation

```bash
#!/bin/bash
set -uo pipefail

TOOLKIT="${1:-./src}"

echo "=== Bash Production Toolkit Verification ==="

# Test logging
source "${TOOLKIT}/foundation/logging.sh"
log_info "Logging works"

# Test secure file utils
source "${TOOLKIT}/foundation/secure-file-utils.sh"
TEST_FILE=$(mktemp)
sfu_write_file "test" "$TEST_FILE" && echo "Secure file utils works"
rm -f "$TEST_FILE"

# Test device detection
source "${TOOLKIT}/utilities/device-detection.sh"
echo "Detected device: $(detect_device)"
echo "Architecture: $(get_device_architecture)"

echo "=== All tests passed ==="
```

## Next Steps

- [Architecture Overview](ARCHITECTURE.md) - Library dependencies
- [Foundation Libraries](foundation/) - Logging, file operations
- [Monitoring Libraries](monitoring/) - Webhook alerting
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
