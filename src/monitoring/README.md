# Monitoring Libraries

## ⚡ TL;DR

Alerting libraries for production systems: alerts.sh (Telegram alerts with rate limiting, deduplication, 3h default), smart-alerts.sh (event tracking with grace periods, recovery detection). Prevent alert fatigue via state-based deduplication.

---

## Overview

Monitoring libraries provide intelligent alerting for production systems:

- **Rate-Limited Alerts** - Prevent alert fatigue via deduplication
- **Event Tracking** - Grace periods for transient issues
- **Recovery Detection** - Automatic recovery alerts
- **State Management** - Persistent state via `/var/lib/` directories

## Libraries

### alerts.sh

**Purpose**: Telegram alerts with rate limiting and deduplication

**Key Features**:
- Telegram Bot API integration via `curl`
- Rate limiting (default: 3 hours, configurable)
- Alert deduplication (same message won't spam)
- State persistence via `/var/lib/alerts/`
- Recovery alerts (optional)
- Performance: ~0.5s per alert (network latency)

**Key Functions**:
```bash
send_telegram_alert "message"                   # Send alert (no deduplication)
send_alert_deduplicated "message" [interval]    # Rate-limited alert (default: 3h)
mark_alert_recovered "alert_id"                 # Mark issue as recovered
```

**Configuration**:
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token"      # Required
export TELEGRAM_CHAT_ID="your_chat_id"          # Required
export ALERTS_STATE_DIR="/var/lib/alerts"       # Optional (default)
```

**Documentation**: [ALERTS.md](../../docs/monitoring/ALERTS.md)

---

### smart-alerts.sh

**Purpose**: Event tracking with grace periods and recovery detection

**Key Features**:
- Grace period handling (don't alert on transient issues)
- Event tracking (count occurrences before alerting)
- Automatic recovery detection
- JSON state files via `jq`
- Multiple event types per script
- Performance: ~0.02s per tracking call

**Key Functions**:
```bash
track_event "event_id" "grace_period_seconds"   # Track event occurrence
is_in_grace_period "event_id"                   # Check if in grace period
clear_event "event_id"                          # Clear event (recovery)
get_event_count "event_id"                      # Get occurrence count
```

**Configuration**:
```bash
export SMART_ALERTS_STATE_DIR="/var/lib/smart-alerts"  # Optional
```

**Documentation**: [SMART_ALERTS.md](../../docs/monitoring/SMART_ALERTS.md)

## Usage Example

### Basic Telegram Alerts

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source monitoring libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

# Configure Telegram
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
export TELEGRAM_CHAT_ID="-1001234567890"

# Send rate-limited alert (won't spam if called multiple times within 3h)
if ! systemctl is-active --quiet my-service; then
    log_error "Service my-service is down"
    send_alert_deduplicated "⚠️ Service my-service is down on $(hostname)"
fi
```

### Smart Alerts with Grace Period

```bash
#!/usr/bin/env bash
set -uo pipefail

# Source monitoring libraries
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
source "${TOOLKIT}/monitoring/smart-alerts.sh"
source "${TOOLKIT}/monitoring/alerts.sh"

# Configure
export TELEGRAM_BOT_TOKEN="your_token"
export TELEGRAM_CHAT_ID="your_chat_id"

# Track events (5 minute grace period)
SERVICE_NAME="my-service"
GRACE_PERIOD=$((5 * 60))  # 5 minutes

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log_warn "Service $SERVICE_NAME is down"

    # Track event (don't alert immediately)
    track_event "$SERVICE_NAME-down" "$GRACE_PERIOD"

    # Only alert if still down after grace period
    if ! is_in_grace_period "$SERVICE_NAME-down"; then
        send_alert_deduplicated "⚠️ Service $SERVICE_NAME down for >5min on $(hostname)"
    fi
else
    # Service is up - clear event if it was tracked
    if [[ -f "/var/lib/smart-alerts/${SERVICE_NAME}-down.json" ]]; then
        log_success "Service $SERVICE_NAME recovered"
        clear_event "$SERVICE_NAME-down"
        send_alert_deduplicated "✅ Service $SERVICE_NAME recovered on $(hostname)"
    fi
fi
```

## Requirements

- **Bash 4.0+** - All libraries require Bash 4.0 or higher
- **curl** - Required for Telegram alerts (alerts.sh)
- **jq** - Required for JSON state files (smart-alerts.sh)
- **Standard Unix utilities** - coreutils (date, mkdir, mv)
- **State directories**: `/var/lib/alerts/`, `/var/lib/smart-alerts/` (created automatically)

## Best Practices

1. **Always use rate limiting** - Prevent alert fatigue via `send_alert_deduplicated()`
2. **Use grace periods for transient issues** - Don't alert on temporary network blips
3. **Send recovery alerts** - Inform when issues resolve automatically
4. **Choose appropriate intervals** - 3h for critical alerts, 24h for warnings
5. **Use descriptive event IDs** - `service-name-issue-type` (e.g., `nginx-down`)

## See Also

- [Back to src/](../README.md)
- [Foundation Libraries](../foundation/README.md)
- [Utility Libraries](../utilities/README.md)
- [Setup Guide](../../docs/SETUP.md)
- [Examples](../../examples/README.md)
