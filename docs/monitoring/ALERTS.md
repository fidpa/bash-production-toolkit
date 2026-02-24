# Alerts Library (v2.0.0)

Generic webhook alerting with rate limiting, severity auto-derivation, and recovery notifications.
Works with any Slack-compatible webhook: Mattermost, Slack, Discord, or custom endpoints.

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/monitoring/alerts.sh

export ALERT_WEBHOOK_URL="https://mattermost.example.com/hooks/TOKEN"
export ALERTS_PREFIX="[MyApp]"

# Send rate-limited alert (severity auto-derived from type name)
send_alert "BACKUP_FAILED" "Backup failed: disk full"
# → emoji: 🟠, severity: error (from *_FAILED pattern)

# Send recovery notification
send_alert "SERVICE_RECOVERED" "nginx is back online"
# → emoji: 🔵, severity: notice (from *_RECOVERED pattern)
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/monitoring/alerts.sh
```

## Migration from v1.x

```bash
# Before (v1.x — Telegram)
export TELEGRAM_BOT_TOKEN="123:abc"
export TELEGRAM_CHAT_ID="-1234"
export TELEGRAM_PREFIX="[MyApp]"
send_telegram_alert "backup_failed" "Disk full" "❌"

# After (v2.0.0 — Generic Webhook)
export ALERT_WEBHOOK_URL="https://your-webhook-endpoint/TOKEN"
export ALERTS_PREFIX="[MyApp]"
send_alert "BACKUP_FAILED" "Disk full"
# emoji and severity auto-derived from type name
```

## Configuration

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `ALERT_WEBHOOK_URL` | Slack-compatible webhook endpoint URL |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ALERT_WEBHOOK_CACERT` | `<not set>` | Path to CA cert for self-signed TLS |
| `ALERTS_PREFIX` | `[System]` | Prefix for all messages |
| `RATE_LIMIT_SECONDS` | `1800` | Cooldown between identical alerts (30 min) |
| `STATE_DIR` | `/var/lib/alerts` | Directory for state files |
| `ENABLE_RECOVERY_ALERTS` | `true` | Send recovery notifications |

### Supported Webhook Endpoints

The library sends Slack-compatible JSON `{"text": "..."}` payloads:

| Service | URL Format |
|---------|-----------|
| **Mattermost** | `https://your-mm.example.com/hooks/TOKEN` |
| **Slack** | `https://hooks.slack.com/services/T/B/TOKEN` |
| **Discord** | `https://discord.com/api/webhooks/ID/TOKEN` |
| **Custom** | Any endpoint accepting `{"text": "..."}` |

## API Reference

### send_alert

```bash
send_alert "ALERT_TYPE" "message" [emoji] [prefix]
```

Send a rate-limited webhook alert. Severity and emoji are auto-derived from the alert type name.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| ALERT_TYPE | Yes | - | Unique identifier (UPPER_SNAKE_CASE recommended) |
| message | Yes | - | Alert message text |
| emoji | No | (auto) | Override emoji (disables auto-derivation) |
| prefix | No | `$ALERTS_PREFIX` | Override message prefix |

**Severity Auto-Derivation:**

| Pattern | Severity | Emoji | Example Types |
|---------|----------|-------|---------------|
| `*_CRITICAL`, `*_DOWN` | critical | 🔴 | `SERVICE_DOWN`, `DB_CRITICAL` |
| `*_FAILED`, `*_ERROR`, `*_FAILURE` | error | 🟠 | `BACKUP_FAILED`, `DISK_ERROR` |
| `*_WARNING`, `*_DEGRADED`, `*_HIGH` | warning | 🟡 | `CPU_HIGH`, `DISK_DEGRADED` |
| `*_RECOVERED`, `*_RESOLVED`, `*_SUCCESS` | notice | 🔵 | `SERVICE_RECOVERED`, `DISK_RESOLVED` |
| everything else | info | ⚪ | `SYSTEM_BOOT`, `TASK_NEW` |

**Rate Limiting:**
- Each `ALERT_TYPE` has an independent cooldown
- Default: 30 minutes between identical alerts
- Customize via `RATE_LIMIT_SECONDS`

**Returns:**
- 0: Alert sent or rate-limited (success)
- 1: Error (delivery failure, missing `ALERT_WEBHOOK_URL`)

**Examples:**
```bash
# Severity auto-derived from type name
send_alert "BACKUP_FAILED" "Backup failed at 03:00"       # 🟠 error
send_alert "SERVICE_DOWN" "nginx not responding"           # 🔴 critical
send_alert "DISK_HIGH" "Disk usage at 85%"                # 🟡 warning
send_alert "SERVICE_RECOVERED" "nginx is back online"     # 🔵 notice
send_alert "SYSTEM_BOOT" "Server rebooted"                # ⚪ info

# Custom emoji (overrides auto-derivation)
send_alert "BACKUP_FAILED" "Backup failed" "🚨"

# Custom prefix per alert
send_alert "DEPLOY_COMPLETE" "v2.0 deployed" "" "[Deployment]"

# Suppress prefix (empty string)
send_alert "HEARTBEAT" "All systems nominal" "💚" ""
```

### send_recovery_alert

```bash
send_recovery_alert "alert_type" "identifier" [message]
```

Send recovery notification and clear state. Only sends if a prior state file exists.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| alert_type | Yes | - | Alert category |
| identifier | Yes | - | Instance identifier |
| message | No | "Recovered" | Recovery message |

**Behavior:**
- Sends with `_RECOVERED` suffix (→ notice severity, 🔵)
- Only sends if there was a previous state file
- Clears stored state for this `alert_type`+`identifier`
- Can be disabled via `ENABLE_RECOVERY_ALERTS=false`

**Example:**
```bash
if systemctl is-active nginx; then
    send_recovery_alert "service_down" "nginx" "nginx is back online"
else
    # Use smart-alerts.sh send_smart_alert for state-change deduplication
    send_alert "SERVICE_DOWN" "nginx is not running"
fi
```

### clear_rate_limit

```bash
clear_rate_limit "alert_type"
```

Clear rate limit for an alert type (useful for testing or manual reset).

**Example:**
```bash
clear_rate_limit "BACKUP_FAILED"
send_alert "BACKUP_FAILED" "Testing alert delivery"
```

## State Files

The library stores state in `STATE_DIR`:

```
$STATE_DIR/
├── .last_alert_BACKUP_FAILED      # Timestamp of last alert (rate limiting)
├── .last_alert_SERVICE_DOWN       # Per-alert-type rate limits
└── .smart_service_down_nginx      # Per-identifier state (recovery tracking)
```

## Examples

### Monitoring Script

```bash
#!/bin/bash
set -uo pipefail

source /path/to/monitoring/alerts.sh

export ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL}"
export ALERTS_PREFIX="[Monitor]"
export RATE_LIMIT_SECONDS=3600  # 1 hour

# CPU check
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
if [[ $cpu -gt 90 ]]; then
    send_alert "CPU_HIGH" "CPU usage: ${cpu}%"
fi

# Disk check
disk=$(df / | awk 'NR==2 {print int($5)}')
if [[ $disk -gt 80 ]]; then
    send_alert "DISK_HIGH" "Root disk usage: ${disk}%"
fi
```

### Service Health Checker

```bash
#!/bin/bash
set -uo pipefail

source /path/to/monitoring/alerts.sh

SERVICES=("nginx" "postgresql" "redis")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        send_recovery_alert "service_down" "$service" "${service} is running"
    else
        send_alert "SERVICE_DOWN" "${service} is not running"
    fi
done
```

### Backup Notifications

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh
source /path/to/monitoring/alerts.sh

export ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL}"
export ALERTS_PREFIX="[Backup]"

if restic backup /data; then
    send_alert "BACKUP_SUCCESS" "Daily backup completed successfully"
else
    send_alert "BACKUP_FAILED" "Daily backup failed - check logs"
fi
```

### Self-Signed TLS (e.g., step-ca)

```bash
#!/bin/bash
set -uo pipefail

source /path/to/monitoring/alerts.sh

export ALERT_WEBHOOK_URL="https://mattermost.internal/hooks/TOKEN"
export ALERT_WEBHOOK_CACERT="/usr/local/share/ca-certificates/step-ca.crt"

send_alert "SYSTEM_BOOT" "Server restarted"
```

## Rate Limiting

### Per-Alert-Type Limiting

Each alert type has an independent cooldown:

```bash
export RATE_LIMIT_SECONDS=1800

send_alert "CPU_HIGH" "..."    # Sent
send_alert "CPU_HIGH" "..."    # Rate-limited for 30 min
send_alert "DISK_HIGH" "..."   # Sent (different type)
```

### Inline Override

```bash
# Critical alerts: shorter cooldown
RATE_LIMIT_SECONDS=300 send_alert "SERVICE_DOWN" "..."

# Low-priority: longer cooldown
RATE_LIMIT_SECONDS=7200 send_alert "HEALTH_CHECK" "All OK"
```

## See Also

- [SMART_ALERTS.md](SMART_ALERTS.md) - Grace periods, event aggregation, state machine
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [ERROR_HANDLING.md](../foundation/ERROR_HANDLING.md) - For alerting on errors
