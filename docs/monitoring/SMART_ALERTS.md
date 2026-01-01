# Smart Alerts Library (v1.1.0)

Advanced event tracking with grace periods, aggregation, and intelligent recovery detection. Prevents alert fatigue from transient issues.

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh
source /path/to/monitoring/smart-alerts.sh

export TELEGRAM_BOT_TOKEN="123456:ABC-xyz"
export TELEGRAM_CHAT_ID="-1001234567890"

# Initialize state directories
sa_init

# Register event (starts grace period)
sa_register_event "wan_down" "primary" "Primary WAN is unreachable"

# In monitoring loop - check if grace period exceeded
sa_check_pending_alerts

# When issue resolves
sa_register_recovery "wan_down" "primary" "Primary WAN restored"
```

## Why Smart Alerts?

Standard alerting leads to **alert fatigue**:

```
12:00:00 - WAN down alert
12:00:30 - WAN recovered
12:01:00 - WAN down alert
12:01:45 - WAN recovered
12:02:00 - WAN down alert
...
```

Smart alerts solve this with **grace periods**:

```
12:00:00 - Event registered, grace period starts (180s)
12:00:30 - Event clears, grace period cancelled (no alert)
12:02:00 - Event registered, grace period starts
12:05:00 - Grace period exceeded → ALERT SENT
12:10:00 - Issue persists for 5+ min → RECOVERY ALERT when resolved
```

## Installation

```bash
# smart-alerts.sh requires alerts.sh
source /path/to/bash-production-toolkit/src/monitoring/alerts.sh
source /path/to/bash-production-toolkit/src/monitoring/smart-alerts.sh
```

**External dependency:** `jq` (for JSON state management)

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SMART_ALERT_ENABLED` | `true` | Enable/disable smart alerts |
| `SMART_ALERT_GRACE_PERIOD` | `180` | Seconds before first alert (3 min) |
| `SMART_ALERT_RECOVERY_THRESHOLD` | `300` | Min downtime for recovery alert (5 min) |
| `SMART_ALERT_AGGREGATION_WINDOW` | `300` | Event aggregation window (5 min) |
| `SMART_ALERT_STATE_DIR` | `/var/lib/smart-alerts` | State file directory |

### Configuration Examples

```bash
# Quick detection (30s grace, 1 min recovery threshold)
export SMART_ALERT_GRACE_PERIOD=30
export SMART_ALERT_RECOVERY_THRESHOLD=60

# Conservative (5 min grace, 10 min recovery)
export SMART_ALERT_GRACE_PERIOD=300
export SMART_ALERT_RECOVERY_THRESHOLD=600

# Disable smart alerts (use standard alerting)
export SMART_ALERT_ENABLED=false
```

## API Reference

### sa_init

```bash
sa_init
```

Initialize state directories. Call once at script start.

**Creates:**
```
$SMART_ALERT_STATE_DIR/
├── events/     # Event state files (JSON)
└── pending/    # Pending event markers
```

### sa_register_event

```bash
sa_register_event "event_type" "identifier" "message" [details]
```

Register an event occurrence.

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| event_type | Yes | Event category (e.g., "wan_down") |
| identifier | Yes | Unique instance (e.g., "primary") |
| message | Yes | Alert message |
| details | No | Additional context |

**Behavior:**
1. First occurrence: Creates pending event, starts grace period
2. Repeated: Updates `last_seen` timestamp
3. Critical event: Sends alert immediately (no grace period)

**Returns:**
- 0: Grace period active (no alert yet)
- 1: Critical event (alert sent immediately)

**Example:**
```bash
# Standard event with grace period
sa_register_event "disk_full" "root" "Root disk at 95%"

# With details
sa_register_event "service_down" "nginx" "nginx stopped unexpectedly" \
    "Exit code: 137, Signal: SIGKILL"
```

### sa_check_pending_alerts

```bash
sa_check_pending_alerts
```

Process pending events and send alerts for exceeded grace periods.

**Call this periodically** (e.g., every 30 seconds in monitoring loop).

**Behavior:**
1. Scans pending events
2. If grace period exceeded: sends alert, marks as "alerted"
3. Aggregates multiple events if within aggregation window

**Example:**
```bash
# Monitoring loop
while true; do
    check_services

    # Process any pending alerts
    sa_check_pending_alerts

    sleep 30
done
```

### sa_register_recovery

```bash
sa_register_recovery "event_type" "identifier" [message]
```

Register that an event has recovered.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| event_type | Yes | - | Event category |
| identifier | Yes | - | Instance identifier |
| message | No | "Recovered" | Recovery message |

**Behavior:**
1. If downtime < `SMART_ALERT_RECOVERY_THRESHOLD`: Clear silently
2. If downtime >= threshold: Send recovery alert

**Example:**
```bash
if ping -c 1 gateway.local >/dev/null 2>&1; then
    sa_register_recovery "wan_down" "primary" "Connection restored"
else
    sa_register_event "wan_down" "primary" "Cannot reach gateway"
fi
```

## Critical Events

Certain events bypass the grace period and alert immediately:

| Event Type | Description |
|------------|-------------|
| `BOTH_WANS_DOWN` | Complete network outage |
| `SELF_HEALING_FAILED` | Auto-recovery mechanism failed |
| `CRITICAL_SERVICE_DOWN` | Essential service failed |

**Example:**
```bash
# This alerts immediately (no grace period)
sa_register_event "BOTH_WANS_DOWN" "network" "All WAN connections lost"
```

## Event State Machine

```
                    register_event()
                          │
                          ▼
                    ┌─────────────┐
            ┌───────│   PENDING   │◄─────────────────┐
            │       └─────────────┘                  │
            │             │                          │
            │     grace period                  event clears
            │     exceeded                    before grace
            │             │                          │
            │             ▼                          │
            │       ┌─────────────┐                  │
            │       │   ALERTED   │──────────────────┤
            │       └─────────────┘                  │
            │             │                          │
            │     register_recovery()                │
            │             │                          │
            │             ▼                          │
            │       ┌─────────────┐                  │
            └──────►│  RESOLVED   │──────────────────┘
                    └─────────────┘
```

## State File Format

Events are stored as JSON:

```json
{
    "event_type": "wan_down",
    "identifier": "primary",
    "message": "Primary WAN is unreachable",
    "details": "Gateway 192.168.1.1 not responding",
    "first_seen": 1704067200,
    "last_seen": 1704067500,
    "alert_sent": false,
    "status": "pending"
}
```

## Examples

### Network Monitoring

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh
source /path/to/monitoring/smart-alerts.sh

export SMART_ALERT_GRACE_PERIOD=180
export SMART_ALERT_RECOVERY_THRESHOLD=300

sa_init

check_wan() {
    local name="$1"
    local gateway="$2"

    if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
        sa_register_recovery "wan_down" "$name" "${name} WAN restored"
    else
        sa_register_event "wan_down" "$name" "${name} WAN unreachable" \
            "Gateway: ${gateway}"
    fi
}

while true; do
    check_wan "primary" "192.168.1.1"
    check_wan "backup" "10.0.0.1"

    # Process pending alerts
    sa_check_pending_alerts

    sleep 30
done
```

### Service Health Monitor

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh
source /path/to/monitoring/smart-alerts.sh

sa_init

SERVICES=("nginx" "postgresql" "redis")

check_services() {
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            sa_register_recovery "service_down" "$service" \
                "${service} is running"
        else
            sa_register_event "service_down" "$service" \
                "${service} is DOWN" \
                "$(systemctl status "$service" 2>&1 | head -5)"
        fi
    done
}

while true; do
    check_services
    sa_check_pending_alerts
    sleep 60
done
```

### Disk Space Monitor with Thresholds

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh
source /path/to/monitoring/smart-alerts.sh

# Short grace period for disk issues
export SMART_ALERT_GRACE_PERIOD=60

sa_init

check_disk() {
    local mount="$1"
    local warn_threshold="$2"
    local crit_threshold="$3"

    local usage
    usage=$(df "$mount" | awk 'NR==2 {print int($5)}')

    if [[ $usage -ge $crit_threshold ]]; then
        # Critical: immediate alert (bypass grace period)
        sa_register_event "CRITICAL_SERVICE_DOWN" "disk_${mount}" \
            "CRITICAL: ${mount} at ${usage}%"
    elif [[ $usage -ge $warn_threshold ]]; then
        sa_register_event "disk_warning" "disk_${mount}" \
            "Warning: ${mount} at ${usage}%"
    else
        sa_register_recovery "disk_warning" "disk_${mount}" \
            "${mount} back to ${usage}%"
    fi
}

while true; do
    check_disk "/" 80 95
    check_disk "/var" 80 95
    check_disk "/data" 70 90

    sa_check_pending_alerts
    sleep 120
done
```

### Container Health with Grace Periods

```bash
#!/bin/bash
set -euo pipefail

source /path/to/monitoring/alerts.sh
source /path/to/monitoring/smart-alerts.sh

# Containers may restart legitimately - longer grace
export SMART_ALERT_GRACE_PERIOD=300

sa_init

CONTAINERS=("web" "api" "worker" "cache")

while true; do
    for container in "${CONTAINERS[@]}"; do
        if docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
            sa_register_recovery "container_down" "$container"
        else
            status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
            sa_register_event "container_down" "$container" \
                "Container ${container} is ${status}"
        fi
    done

    sa_check_pending_alerts
    sleep 30
done
```

## Tuning Guidelines

### Grace Period Selection

| Scenario | Recommended Grace Period |
|----------|-------------------------|
| Network flaps | 180-300s |
| Service restarts | 60-120s |
| Disk space | 30-60s |
| Critical infrastructure | 0s (immediate) |

### Recovery Threshold Selection

| Scenario | Recommended Threshold |
|----------|----------------------|
| Brief outages normal | 300-600s |
| Always want recovery alert | 60s |
| Only long outages matter | 900-1800s |

### Alert Fatigue Prevention

1. **Too many alerts?** Increase `SMART_ALERT_GRACE_PERIOD`
2. **Missing real issues?** Decrease `SMART_ALERT_GRACE_PERIOD`
3. **Too many recovery alerts?** Increase `SMART_ALERT_RECOVERY_THRESHOLD`
4. **Want all recoveries?** Set `SMART_ALERT_RECOVERY_THRESHOLD=0`

## Performance

| Operation | Typical Time |
|-----------|-------------|
| Event registration | ~10ms |
| Pending check (10 events) | ~100ms |
| Recovery registration | ~10ms |
| State file size | ~300 bytes/event |

## Comparison with alerts.sh

| Feature | alerts.sh | smart-alerts.sh |
|---------|-----------|-----------------|
| Rate limiting | Time-based | Event-based |
| Grace periods | No | Yes |
| Event aggregation | No | Yes |
| Recovery tracking | Basic | Advanced (downtime-aware) |
| State persistence | Minimal | Full event history |
| Best for | Simple alerts | Complex monitoring |

## See Also

- [ALERTS.md](ALERTS.md) - Base alerting library (required)
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency graph
- [ERROR_HANDLING.md](../foundation/ERROR_HANDLING.md) - Error handling integration
