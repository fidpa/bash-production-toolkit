# Setup Guide

Complete installation and configuration guide for the Bash Production Toolkit.

## Prerequisites

- **Bash 4.0+** (check with `bash --version`)
- **Standard Unix utilities** (coreutils: `mkdir`, `chmod`, `mv`, `date`)
- **Optional**: `jq` (for JSON logging and smart-alerts)
- **Optional**: `curl` (for Telegram alerts)
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

## Telegram Alerts Setup

The alerting libraries (`alerts.sh`, `smart-alerts.sh`) require Telegram configuration.

### 1. Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Save the **API token** (format: `123456789:ABCdef...`)

### 2. Get Your Chat ID

1. Add your bot to a group or start a chat with it
2. Send a message to the bot
3. Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
4. Find `"chat":{"id":123456789}` in the response

### 3. Configure Environment

```bash
export TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_CHAT_ID="-1001234567890"
```

### 4. Test Alert

```bash
source "${TOOLKIT}/monitoring/alerts.sh"
send_telegram_alert "test" "Hello from bash-production-toolkit!" "🧪"
```

## Configuration Options

### Logging (logging.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, WARN, ERROR, CRITICAL |
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
| `TELEGRAM_BOT_TOKEN` | (required) | Telegram Bot API token |
| `TELEGRAM_CHAT_ID` | (required) | Target chat/group ID |
| `TELEGRAM_PREFIX` | `[System]` | Message prefix |
| `RATE_LIMIT_SECONDS` | `1800` | Cooldown between same alerts |
| `STATE_DIR` | `/var/lib/alerts` | State file directory |
| `ENABLE_RECOVERY_ALERTS` | `true` | Send recovery notifications |

### Smart Alerts (smart-alerts.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `SMART_ALERT_GRACE_PERIOD` | `180` | Seconds before alerting |
| `SMART_ALERT_RECOVERY_THRESHOLD` | `300` | Minimum downtime for recovery alert |
| `SMART_ALERT_STATE_DIR` | `/var/lib/smart-alerts` | State directory |

### Device Detection (device-detection.sh)

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVICE_CONFIG_FILE` | `./devices.yml` | Device config path |
| `DEVICE_OVERRIDE` | - | Force specific device (testing) |

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

# Alerting
TELEGRAM_BOT_TOKEN="your-token"
TELEGRAM_CHAT_ID="your-chat-id"
TELEGRAM_PREFIX="[MyServer]"
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
TELEGRAM_BOT_TOKEN=your-token
TELEGRAM_CHAT_ID=your-chat-id
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
- [Monitoring Libraries](monitoring/) - Telegram alerting
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
