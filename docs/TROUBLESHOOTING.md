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

---

## Alert Issues

### Alert Not Sending

**Check 1:** Credentials set?
```bash
echo "Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "Chat ID: $TELEGRAM_CHAT_ID"
```

**Solution:**
```bash
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"
```

**Check 2:** Telegram API reachable?
```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
```

**Expected:** JSON with `"ok":true`

**If fails:**
- Check network connectivity
- Verify token is correct
- Check firewall for api.telegram.org

**Check 3:** Chat ID correct?
```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=Test"
```

**Common errors:**
- `"chat not found"` - Wrong chat ID or bot not in group
- `"bot was blocked"` - User blocked the bot
- `"group chat was upgraded"` - Use new supergroup ID (starts with -100)

### Rate Limiting Issues

**Symptoms:** Alert blocked when it shouldn't be.

**Check:** State file timestamp
```bash
cat /var/lib/alerts/.rate_limit_your_alert_type
# Shows Unix timestamp of last alert
```

**Solutions:**

1. Clear rate limit:
   ```bash
   rm /var/lib/alerts/.rate_limit_your_alert_type
   ```

2. Reduce cooldown:
   ```bash
   export RATE_LIMIT_SECONDS=300  # 5 minutes
   ```

3. Use different alert type:
   ```bash
   send_telegram_alert "disk_warning_v2" "..."
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

# Check curl (for Telegram)
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
| `TELEGRAM_BOT_TOKEN not configured` | Token not set | Export TELEGRAM_BOT_TOKEN |
| `Rate limited: Skipping alert` | Same alert sent recently | Wait for cooldown or clear state |
| `Failed to create directory` | No write permission | Check STATE_DIR permissions |

---

## Getting Help

1. **Enable debug mode** and capture output
2. **Check library loaded** (include guard variables)
3. **Verify dependencies** (jq, curl, systemd)
4. **Check state files** for unexpected values
5. **Open an issue** at [GitHub Issues](https://github.com/fidpa/bash-production-toolkit/issues)
