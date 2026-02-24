# Monitoring Libraries

## ⚡ TL;DR

Alerting libraries for production systems: alerts.sh (generic webhook alerts with rate limiting, severity auto-derivation), smart-alerts.sh (event tracking with grace periods, recovery detection). Prevent alert fatigue via state-based deduplication.

---

## Overview

Monitoring libraries provide intelligent alerting for production systems:

- **Rate-Limited Alerts** - Prevent alert fatigue via configurable cooldown
- **Event Tracking** - Grace periods for transient issues
- **Recovery Detection** - Automatic recovery alerts
- **State Management** - Persistent state via `/var/lib/` directories
- **Vendor-Agnostic** - Works with Mattermost, Slack, Discord, or any Slack-compatible webhook

## Libraries

### alerts.sh

**Purpose**: Generic webhook alerts with rate limiting and severity auto-derivation

**Key Features**:
- Slack-compatible JSON webhook delivery via `curl`
- Severity auto-derived from alert type name (`*_FAILED`→error, `*_RECOVERED`→notice, etc.)
- Rate limiting (default: 30 min, configurable per alert type)
- State persistence via `/var/lib/alerts/`
- Recovery alerts (optional)
- Self-signed TLS support via `ALERT_WEBHOOK_CACERT`
- Performance: ~0.5s per alert (network latency)

**Key Functions**:
```bash
send_alert "ALERT_TYPE" "message"              # Send alert (severity auto-derived)
send_recovery_alert "type" "id" ["message"]    # Send recovery notification
clear_rate_limit "alert_type"                  # Reset rate limit for testing
```

**Configuration**:
```bash
export ALERT_WEBHOOK_URL="https://your-endpoint/TOKEN"  # Required
export ALERT_WEBHOOK_CACERT="/path/to/ca.crt"           # Optional (self-signed TLS)
export ALERTS_PREFIX="[System]"                         # Optional (default)
export RATE_LIMIT_SECONDS=1800                          # Optional (default: 30 min)
```

**Documentation**: [ALERTS.md](../../docs/monitoring/ALERTS.md)

---

### smart-alerts.sh

**Purpose**: Event tracking with grace periods and recovery detection

**Key Features**:
- Grace period handling (don't alert on transient issues, default: 3 min)
- Event state machine with JSON state files
- Recovery threshold detection (only alert recovery if downtime > 5 min)
- Aggregation window (collect events, send summary)
- JSON state files via `jq`
- Performance: ~0.02s per tracking call

**Key Functions**:
```bash
sa_register_event "type" "id" "message"        # Register event (starts grace period)
sa_check_pending_alerts                        # Process pending events (call periodically)
sa_register_recovery "type" "id" ["message"]   # Register recovery
```

**Configuration**:
```bash
export SMART_ALERT_GRACE_PERIOD=180            # Seconds before alerting (default: 3 min)
export SMART_ALERT_RECOVERY_THRESHOLD=300      # Min downtime for recovery alert (default: 5 min)
export SMART_ALERT_STATE_DIR="/var/lib/smart-alerts"  # Optional
```

**Documentation**: [SMART_ALERTS.md](../../docs/monitoring/SMART_ALERTS.md)

## Usage Example

### Basic Webhook Alerts

```bash
#!/usr/bin/env bash
set -uo pipefail

TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

export ALERT_WEBHOOK_URL="https://mattermost.example.com/hooks/TOKEN"

# Send rate-limited alert (severity auto-derived: *_DOWN → critical)
if ! systemctl is-active --quiet my-service; then
    log_error "Service my-service is down"
    send_alert "SERVICE_DOWN" "my-service is not running on $(hostname)"
fi
```

### Smart Alerts with Grace Period

```bash
#!/usr/bin/env bash
set -uo pipefail

TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"
source "${TOOLKIT}/monitoring/smart-alerts.sh"

export ALERT_WEBHOOK_URL="https://mattermost.example.com/hooks/TOKEN"
export SMART_ALERT_GRACE_PERIOD=300  # 5 minute grace period

SERVICE_NAME="my-service"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log_warn "Service $SERVICE_NAME is down"
    # Register event - alert only fires after grace period
    sa_register_event "service_down" "$SERVICE_NAME" "Service $SERVICE_NAME is not running"
else
    log_notice "Service $SERVICE_NAME is running"
    sa_register_recovery "service_down" "$SERVICE_NAME" "Service $SERVICE_NAME recovered"
fi

# Call periodically to process grace period expirations
sa_check_pending_alerts
```

## Requirements

- **Bash 4.0+** - All libraries require Bash 4.0 or higher
- **curl** - Required for webhook alerts (alerts.sh)
- **jq** - Required for JSON state files (smart-alerts.sh)
- **Standard Unix utilities** - coreutils (date, mkdir, mv)
- **State directories**: `/var/lib/alerts/`, `/var/lib/smart-alerts/` (created automatically)

## Best Practices

1. **Use UPPER_SNAKE_CASE alert types** - Enables severity auto-derivation (`BACKUP_FAILED`, `SERVICE_DOWN`)
2. **Use grace periods for transient issues** - Don't alert on temporary network blips
3. **Send recovery alerts** - Inform when issues resolve automatically
4. **Choose appropriate rate limits** - 5-30 min for critical, 1-4h for warnings
5. **Use descriptive alert types** - `SERVICE_NAME_ISSUE` pattern (e.g., `NGINX_DOWN`)

## See Also

- [Back to src/](../README.md)
- [Foundation Libraries](../foundation/README.md)
- [Utility Libraries](../utilities/README.md)
- [Setup Guide](../../docs/SETUP.md)
- [Examples](../../examples/README.md)
