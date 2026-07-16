# Troubleshooting

Common issues and solutions for the Bash Production Toolkit.

## Logging Issues

### No Log Output

**Symptoms:** Script runs but no log messages appear.

**Check 1:** Log level filtering
```bash
echo "LOG_LEVEL=$LOG_LEVEL"
# If LOG_LEVEL=ERROR, INFO messages are filtered
```

**Solution:** Lower the log level:
```bash
export LOG_LEVEL=DEBUG
```

**Check 2:** Output destination
```bash
echo "LOG_TO_STDOUT=$LOG_TO_STDOUT"
echo "LOG_TO_JOURNAL=$LOG_TO_JOURNAL"
```

**Solution:** Enable stdout:
```bash
export LOG_TO_STDOUT=true
```

### Journald Not Working

**Symptoms:** `LOG_TO_JOURNAL=true` but no entries in journalctl.

**Check:** Is systemd-cat available?
```bash
command -v systemd-cat
command -v logger
```

**Solution:** Install systemd or use file logging:
```bash
export LOG_TO_JOURNAL=false
export LOG_FILE="/var/log/myapp.log"
```

### Log File Permission Denied

**Symptoms:** Error writing to log file.

**Check:**
```bash
ls -la /var/log/myapp.log
ls -la /var/log/
```

**Solutions:**

1. Use a writable location:
   ```bash
   export LOG_DIR="$HOME/logs"
   mkdir -p "$LOG_DIR"
   ```

2. Fix permissions:
   ```bash
   sudo touch /var/log/myapp.log
   sudo chown $USER:$USER /var/log/myapp.log
   ```

### Captured Values Contain Log Lines

**Symptoms:** A variable assigned via `var=$(some_function)` contains log
output in addition to the expected value. Downstream commands fail in
surprising ways — e.g. `sed: unterminated 's' command` when the multi-line
value is interpolated into a sed expression, or string comparisons that
mysteriously report a change.

**Cause:** `LOG_TO_STDOUT` defaults to `true`, so `log_*` calls print to
stdout — and command substitution captures stdout. The bug is latent: it only
fires when the logging branch inside the captured function actually executes,
which is often an error path that normal testing never reaches.

**Solution:** In functions whose stdout is captured, redirect log calls to
stderr:

```bash
log_warning "falling back to cached value" >&2
```

Also validate captured values before using them in write operations
(`[[ "$ip" =~ ^[0-9.]+$ ]] || return 1`) — that stops any stray output from
reaching config files. See the pitfall section in
[foundation/LOGGING.md](foundation/LOGGING.md) for a full example.

---

## Alert Issues

### Alert Not Sending

**Check 1:** Webhook URL configured?
```bash
echo "ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL:-<not set>}"
```

**Solution:**
```bash
export ALERT_WEBHOOK_URL="https://your-mattermost/hooks/TOKEN"
```

**Check 2:** Webhook reachable?
```bash
curl -s -X POST "$ALERT_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"text": "test"}' && echo "OK"
```

**Expected:** `OK` (HTTP 200 from webhook)

**If fails:**
- Check network connectivity to webhook host
- Verify webhook URL is correct and active
- Check firewall rules for the webhook host
- If TLS error with self-signed cert: set `ALERT_WEBHOOK_CACERT`

**Check 3:** Self-signed TLS?
```bash
# If webhook uses internal CA (e.g. step-ca), configure cert:
export ALERT_WEBHOOK_CACERT="/usr/local/share/ca-certificates/my-ca.crt"
```

### Rate Limiting Issues

**Symptoms:** Alert blocked when it shouldn't be.

**Check:** State file timestamp
```bash
cat /var/lib/alerts/.last_alert_YOUR_ALERT_TYPE
# Shows Unix timestamp of last alert
```

**Solutions:**

1. Clear rate limit:
   ```bash
   clear_rate_limit "YOUR_ALERT_TYPE"
   # or: rm /var/lib/alerts/.last_alert_YOUR_ALERT_TYPE
   ```

2. Reduce cooldown:
   ```bash
   export RATE_LIMIT_SECONDS=300  # 5 minutes
   ```

3. Use different alert type:
   ```bash
   send_alert "DISK_WARNING_V2" "..."
   ```

### State Directory Permission Denied

**Check:**
```bash
ls -la /var/lib/alerts/
```

**Solutions:**
```bash
# Create with correct permissions
sudo mkdir -p /var/lib/alerts
sudo chown $USER:$USER /var/lib/alerts

# Or use user directory
export STATE_DIR="$HOME/.alerts-state"
mkdir -p "$STATE_DIR"
```

---

## Smart Alert Issues

### No Alerts Even With Events

**Check:** Event file exists?
```bash
ls -la /var/lib/smart-alerts/events/
```

**Check:** Grace period not yet elapsed?
```bash
cat /var/lib/smart-alerts/events/*.json | jq '.first_seen'
# Compare to current time
date +%s
```

**Solution:** Wait for grace period or reduce it:
```bash
export SMART_ALERT_GRACE_PERIOD=60  # 1 minute
```

### Recovery Alerts Not Sending

**Check:** Was alert ever sent?
```bash
cat /var/lib/smart-alerts/events/*.json | jq '.alert_sent'
```

**Check:** Downtime threshold met?
```bash
# Recovery only sends if downtime > SMART_ALERT_RECOVERY_THRESHOLD (default 300s)
```

**Solution:**
```bash
export SMART_ALERT_RECOVERY_THRESHOLD=60  # 1 minute
```

---

## Secure File Utils Issues

### Atomic Write Fails

**Symptoms:** `sfu_write_file` returns error.

**Check:** Directory writable?
```bash
ls -la $(dirname /path/to/file)
```

**Check:** Temp directory accessible?
```bash
echo "$TMPDIR"
ls -la "${TMPDIR:-/tmp}"
```

**Solution:** Set explicit temp dir:
```bash
export TMPDIR="/var/tmp"
```

### Permission Not Applied

**Symptoms:** File created but wrong permissions.

**Check:** Permission parameter format
```bash
# Correct: octal without leading zero
sfu_write_file "data" "/path/file" "644"

# Wrong: leading zero
sfu_write_file "data" "/path/file" "0644"
```

---

## Device Detection Issues

### Always Returns "unknown"

**Check 1:** Hostname pattern matched?
```bash
hostname -s
```

**Check 2:** Config file exists?
```bash
echo "DEVICE_CONFIG_FILE=$DEVICE_CONFIG_FILE"
cat "$DEVICE_CONFIG_FILE"
```

**Solutions:**

1. Override manually:
   ```bash
   export DEVICE_OVERRIDE="my-server"
   ```

2. Use hostname patterns:
   ```bash
   # Hostname contains "router" → detected as "router"
   # Hostname contains "nas" → detected as "server"
   ```

3. Create config file:
   ```yaml
   # devices.yml
   devices:
     - id: my-server
       hostname: myhost
   ```

### Architecture Detection Wrong

**Check:**
```bash
uname -m
```

**Note:** aarch64 is normalized to arm64, amd64 to x86_64.

---

## Error Handling Issues

### Recovery Action Not Executed

**Check:** Recovery action syntax
```bash
# Recovery action is passed as string and eval'd
handle_error 1 "Error" "component" "systemctl restart myservice"
```

**Check:** Permissions
```bash
# May need sudo
handle_error 1 "Error" "component" "sudo systemctl restart myservice"
```

### Error Trap Not Firing

**Check:** Trap set correctly?
```bash
set_error_traps
set -E  # Required for trap inheritance
```

**Check:** In function scope?
```bash
# Traps may not fire in subshells
my_function() {
    false  # Trap fires
}
my_function

# Subshell - trap may not fire
(false)
```

---

## General Debugging

### Enable Debug Mode

Most libraries support debug logging:

```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
```

### Check Library Loaded

```bash
# Check include guard
echo "${_LOGGING_LOADED:-not loaded}"
echo "${MONITORING_ALERTS_LOADED:-not loaded}"
echo "${DEVICE_DETECTION_LOADED:-not loaded}"
```

### Verify Dependencies

```bash
# Check jq (for smart-alerts, JSON logging)
command -v jq && jq --version

# Check curl (for webhook alerts)
command -v curl && curl --version | head -1

# Check systemd tools
command -v systemd-cat
command -v logger
```

### Source Order Issues

Libraries must be sourced in dependency order:

```bash
# Correct order
source logging.sh          # No dependencies
source secure-file-utils.sh # Optional: logging.sh
source error-handling.sh   # Requires: logging.sh
source alerts.sh           # Optional: logging.sh, secure-file-utils.sh
source smart-alerts.sh     # Requires: alerts.sh
```

---

## Common Error Messages

| Message | Cause | Fix |
|---------|-------|-----|
| `logging.sh not found` | error-handling.sh can't find logging.sh | Ensure both in same directory |
| `jq: command not found` | smart-alerts.sh requires jq | Install jq: `apt install jq` |
| `ALERT_WEBHOOK_URL not configured` | Webhook URL not set | Export ALERT_WEBHOOK_URL |
| `Rate limited: Skipping alert` | Same alert sent recently | Wait for cooldown or clear state |
| `Failed to create directory` | No write permission | Check STATE_DIR permissions |

---

## Getting Help

1. **Enable debug mode** and capture output
2. **Check library loaded** (include guard variables)
3. **Verify dependencies** (jq, curl, systemd)
4. **Check state files** for unexpected values
5. **Open an issue** at [GitHub Issues](https://github.com/fidpa/bash-production-toolkit/issues)
