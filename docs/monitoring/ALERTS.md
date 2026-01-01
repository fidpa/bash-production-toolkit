# Alerts Library (v1.1.0)

Telegram alerting with rate limiting, smart deduplication, and recovery notifications.

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh

export TELEGRAM_BOT_TOKEN="123456:ABC-xyz"
export TELEGRAM_CHAT_ID="-1001234567890"
export TELEGRAM_PREFIX="[MyApp]"

# Send rate-limited alert
send_telegram_alert "backup_failed" "Backup failed: disk full" "❌"

# Send smart alert (only on state change)
send_smart_alert "disk_space" "server1" "Disk space low: 90%" "⚠️"

# Send recovery notification
send_recovery_alert "disk_space" "server1" "Disk space recovered: 45%"
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/monitoring/alerts.sh
```

## Configuration

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | Chat/group ID for notifications |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TELEGRAM_PREFIX` | `[System]` | Prefix for all messages |
| `RATE_LIMIT_SECONDS` | `1800` | Cooldown between identical alerts (30 min) |
| `STATE_DIR` | `/var/lib/alerts` | Directory for state files |
| `ENABLE_RECOVERY_ALERTS` | `true` | Send recovery notifications |

### Getting Telegram Credentials

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Get the bot token (format: `123456789:ABCdefGHI...`)
3. Add the bot to your group/channel
4. Get chat ID via: `curl "https://api.telegram.org/bot<TOKEN>/getUpdates"`

## API Reference

### send_telegram_alert

```bash
send_telegram_alert "alert_type" "message" [emoji] [prefix]
```

Send a rate-limited Telegram alert.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| alert_type | Yes | - | Unique identifier for rate limiting |
| message | Yes | - | Alert message (supports HTML) |
| emoji | No | 📟 | Emoji prefix |
| prefix | No | `$TELEGRAM_PREFIX` | Message prefix |

**Rate Limiting:**
- Each `alert_type` has independent cooldown
- Default: 30 minutes between identical alerts
- Customize via `RATE_LIMIT_SECONDS`

**Returns:**
- 0: Alert sent or rate-limited (success)
- 1: Error (API failure, missing config)

**Example:**
```bash
# Basic alert
send_telegram_alert "cpu_high" "CPU usage: 95%"

# With custom emoji
send_telegram_alert "backup_failed" "Backup failed" "🚨"

# HTML formatting
send_telegram_alert "deploy" "<b>Deployment</b> completed\n<code>v2.1.0</code>" "✅"
```

### send_smart_alert

```bash
send_smart_alert "alert_type" "identifier" "message" [emoji]
```

Send alert only when state changes (prevents duplicate alerts).

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| alert_type | Yes | Alert category |
| identifier | Yes | Unique instance identifier |
| message | Yes | Alert message |
| emoji | No | Emoji prefix |

**State Tracking:**
- Stores hash of last message per `alert_type`+`identifier`
- Only sends when content changes
- Persists across script runs

**Example:**
```bash
# Only sends if disk usage changed
disk_usage=$(df -h / | awk 'NR==2 {print $5}')
send_smart_alert "disk_space" "root" "Root disk: ${disk_usage}" "💾"

# Different identifiers = separate tracking
send_smart_alert "disk_space" "data" "Data disk: 45%"
send_smart_alert "disk_space" "backup" "Backup disk: 80%"
```

### send_recovery_alert

```bash
send_recovery_alert "alert_type" "identifier" [message]
```

Send recovery notification and clear state.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| alert_type | Yes | - | Alert category |
| identifier | Yes | - | Instance identifier |
| message | No | "Recovered" | Recovery message |

**Behavior:**
- Only sends if there was a previous alert
- Clears stored state for this `alert_type`+`identifier`
- Can be disabled via `ENABLE_RECOVERY_ALERTS=false`

**Example:**
```bash
# Check service status
if systemctl is-active nginx; then
    send_recovery_alert "service_down" "nginx" "nginx is back online"
else
    send_smart_alert "service_down" "nginx" "nginx is not running" "🚨"
fi
```

### clear_rate_limit

```bash
clear_rate_limit "alert_type"
```

Clear rate limit for testing.

**Example:**
```bash
# Clear rate limit to resend immediately
clear_rate_limit "backup_failed"
send_telegram_alert "backup_failed" "Testing alert"
```

## State Files

The library stores state in `STATE_DIR`:

```
$STATE_DIR/
├── .rate_limit_backup_failed     # Timestamp of last alert
├── .rate_limit_cpu_high          # Per-alert-type rate limits
├── .smart_disk_space_root        # Content hash for smart alerts
└── .smart_service_down_nginx     # Per-identifier state
```

## Examples

### Monitoring Script

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh

export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
export TELEGRAM_PREFIX="[Monitor]"
export RATE_LIMIT_SECONDS=3600  # 1 hour

# CPU check
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
if [[ $cpu -gt 90 ]]; then
    send_telegram_alert "cpu_high" "CPU usage: ${cpu}%" "🔥"
fi

# Memory check
mem=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [[ $mem -gt 85 ]]; then
    send_telegram_alert "memory_high" "Memory usage: ${mem}%" "💾"
fi

# Disk check
disk=$(df / | awk 'NR==2 {print int($5)}')
if [[ $disk -gt 80 ]]; then
    send_smart_alert "disk_full" "root" "Disk usage: ${disk}%" "📀"
else
    send_recovery_alert "disk_full" "root" "Disk back to normal: ${disk}%"
fi
```

### Service Health Checker

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh

SERVICES=("nginx" "postgresql" "redis")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        send_recovery_alert "service_down" "$service" "${service} is running"
    else
        send_smart_alert "service_down" "$service" "${service} is DOWN" "🚨"
    fi
done
```

### Backup Status Notifications

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh

export TELEGRAM_PREFIX="[Backup]"

backup_result=0
backup_size=""

# Run backup
if restic backup /data --json | tee /tmp/backup.log; then
    backup_size=$(jq -r '.total_bytes_processed' /tmp/backup.log | numfmt --to=iec)
    backup_result=0
else
    backup_result=$?
fi

if [[ $backup_result -eq 0 ]]; then
    send_telegram_alert "backup_daily" "✅ Backup completed\nSize: ${backup_size}" "📦"
else
    send_telegram_alert "backup_failed" "❌ Backup FAILED\nExit code: ${backup_result}" "🚨"
fi
```

### Docker Container Monitoring

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh

containers=$(docker ps -a --format '{{.Names}}')

for container in $containers; do
    status=$(docker inspect -f '{{.State.Status}}' "$container")

    case "$status" in
        running)
            send_recovery_alert "container_down" "$container"
            ;;
        exited|dead)
            exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$container")
            send_smart_alert "container_down" "$container" \
                "Container ${container} is ${status} (exit: ${exit_code})" "🐳"
            ;;
    esac
done
```

## Rate Limiting Strategies

### Per-Alert-Type Limiting

```bash
# Each type has its own cooldown
export RATE_LIMIT_SECONDS=1800

send_telegram_alert "cpu_high" "..."    # Sent
send_telegram_alert "cpu_high" "..."    # Rate-limited for 30 min
send_telegram_alert "memory_high" "..." # Sent (different type)
```

### Custom Cooldowns

```bash
# Critical alerts: shorter cooldown
RATE_LIMIT_SECONDS=300 send_telegram_alert "critical" "..."

# Low-priority: longer cooldown
RATE_LIMIT_SECONDS=7200 send_telegram_alert "info" "..."
```

### Smart Deduplication vs Rate Limiting

| Feature | send_telegram_alert | send_smart_alert |
|---------|---------------------|------------------|
| Deduplication | Time-based | Content-based |
| Repeat same message | After cooldown | Never (until changed) |
| Tracks state | Timestamp only | Message hash |
| Best for | Time-sensitive alerts | State changes |

## HTML Formatting

Telegram supports HTML in messages:

```bash
send_telegram_alert "deploy" "
<b>Deployment Complete</b>

Version: <code>v2.1.0</code>
Server: <i>production</i>

<a href='https://example.com/logs'>View Logs</a>
" "🚀"
```

Supported tags: `<b>`, `<i>`, `<code>`, `<pre>`, `<a href=''>`, `<s>`, `<u>`

## Error Handling

```bash
# Check if alert was sent
if send_telegram_alert "test" "Test message"; then
    echo "Alert sent or rate-limited"
else
    echo "Alert failed (check TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID)"
fi

# Ensure state directory exists
mkdir -p "${STATE_DIR:-/var/lib/alerts}"
```

## See Also

- [SMART_ALERTS.md](SMART_ALERTS.md) - Advanced event tracking with grace periods
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [ERROR_HANDLING.md](../foundation/ERROR_HANDLING.md) - For alerting on errors
