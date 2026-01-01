# Secure File Utilities (v1.6.1)

Atomic file operations library preventing race conditions, partial writes, and security issues.

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/secure-file-utils.sh

# Atomic write (content, then target)
sfu_write_file "my config data" "/etc/myapp/config.txt"

# Atomic write with custom permissions
sfu_write_file "secret data" "/etc/myapp/secret.txt" "600"

# Atomic append
sfu_append_file "$(date): Log entry" "/var/log/myapp.log"
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/foundation/secure-file-utils.sh
```

## Why Atomic Operations?

Standard file writes can fail mid-write:

```bash
# DANGEROUS - can leave partial file on crash
echo "$config" > /etc/myapp/config.txt
```

Atomic operations prevent this:

```bash
# SAFE - file is complete or doesn't exist
sfu_write_file "$config" "/etc/myapp/config.txt"
```

The library uses: `mktemp` → write → `chmod` → `mv` (atomic on POSIX filesystems).

## API Reference

### sfu_write_file

```bash
sfu_write_file "content" "/path/to/target" [permissions]
```

Write content to a file atomically.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| content | Yes | - | Content to write |
| target | Yes | - | Target file path |
| permissions | No | 600 | File permissions (octal) |

**Returns:** 0 on success, 1 on error

**Example:**
```bash
# Write config with default permissions (600)
sfu_write_file "key=value" "/etc/myapp/config"

# Write with custom permissions
sfu_write_file "public data" "/var/lib/app/data.txt" "644"

# Write metrics (readable by monitoring)
sfu_write_file "42" "/var/lib/node_exporter/metric.prom" "644"
```

### sfu_append_file

```bash
sfu_append_file "content" "/path/to/target"
```

Append content to a file atomically (read → append → atomic write).

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| content | Yes | Content to append |
| target | Yes | Target file path |

**Example:**
```bash
sfu_append_file "$(date): Process started" "/var/log/myapp.log"
```

### sfu_append_line

```bash
sfu_append_line "/path/to/target" "content"
```

Append a single line. Note: **parameter order is reversed** from `sfu_append_file`.

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| target | Yes | Target file path |
| content | Yes | Line to append |

**Example:**
```bash
sfu_append_line "/var/log/events.log" "Event occurred at $(date)"
```

### sfu_heredoc

```bash
sfu_heredoc [--append] "/path/to/target" <<'EOF'
Content here
Multiple lines
EOF
```

Write or append heredoc content to a file.

**Flags:**
- `--append` - Append instead of overwrite

**Example:**
```bash
# Write heredoc
sfu_heredoc "/etc/myapp/config.yaml" <<'EOF'
server:
  port: 8080
  host: localhost
EOF

# Append heredoc
sfu_heredoc --append "/etc/myapp/config.yaml" <<'EOF'
logging:
  level: info
EOF
```

### sfu_validate_path

```bash
sfu_validate_path "/user/provided/path" [allowed_base]
```

Validate a path to prevent directory traversal attacks.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| path | Yes | - | Path to validate |
| allowed_base | No | (none) | Restrict to this directory |

**Returns:** 0 if valid, 1 if invalid (traversal detected)

**Example:**
```bash
# Validate user input
user_input="../../../etc/passwd"

if sfu_validate_path "$user_input" "/var/lib/myapp"; then
    sfu_write_file "$data" "$user_input"
else
    echo "Invalid path!" >&2
    exit 1
fi
```

### sfu_setup_wd_protection

```bash
sfu_setup_wd_protection
```

Save current working directory and set up trap to restore on exit.

**Example:**
```bash
sfu_setup_wd_protection

cd /some/directory
# ... work ...
# Working directory is restored automatically on exit
```

### sfu_cleanup_wd_protection

```bash
sfu_cleanup_wd_protection
```

Manually restore original working directory (usually called by trap).

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STATE_DIRECTORY` | (unset) | systemd StateDirectory path |
| `TMPDIR` | `/tmp` | Custom temp directory |
| `SCRIPT_NAME` | basename of `$0` | Script name for temp file naming |

### Secure Temp Directory

The library creates a secure temp directory:

```
${STATE_DIRECTORY:-${TMPDIR:-/tmp}}/bash-toolkit-secure-${USER}/
```

- Permissions: 700 (owner only)
- Cleaned up on exit via trap

## Common Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "Content cannot be empty" | First parameter empty | Validate variable before call |
| "Target path cannot be empty" | Second parameter empty | Ensure path variable is set |
| "Target directory does not exist" | Parent dir missing | `mkdir -p "$(dirname "$file")"` |
| "Failed to move temp file to target 'X'" | **Parameters swapped** | Check parameter order |

### Parameter Order Bug

The most common bug is swapping parameters:

```bash
# WRONG - tries to create file named "42"
sfu_write_file "$counter_file" "42"

# CORRECT - writes "42" to file
sfu_write_file "42" "$counter_file"
```

**Mnemonic:** "Write the CONTENT to the FILE"

## Examples

### Metric Files (Prometheus)

```bash
#!/bin/bash
source /path/to/secure-file-utils.sh

METRICS_DIR="/var/lib/node_exporter/textfile_collector"

# Write metric atomically
latency=42
sfu_write_file "request_latency_ms ${latency}" \
    "${METRICS_DIR}/latency.prom" "644"
```

### State Files

```bash
#!/bin/bash
source /path/to/secure-file-utils.sh

STATE_DIR="${STATE_DIRECTORY:-/var/lib/myapp}"
mkdir -p "$STATE_DIR"

# Track restart count
count_file="${STATE_DIR}/restart_count"
if [[ -f "$count_file" ]]; then
    count=$(<"$count_file")
else
    count=0
fi

((count++))
sfu_write_file "$count" "$count_file"
```

### Configuration Management

```bash
#!/bin/bash
source /path/to/secure-file-utils.sh

# Generate config from template
config="
server:
  port: ${PORT:-8080}
  host: ${HOST:-localhost}
database:
  url: ${DATABASE_URL}
"

# Write atomically with restrictive permissions
sfu_write_file "$config" "/etc/myapp/config.yaml" "640"
```

### Log Rotation Safe Appending

```bash
#!/bin/bash
source /path/to/secure-file-utils.sh

LOG_FILE="/var/log/myapp/events.log"

log_event() {
    local timestamp event
    timestamp=$(date -Iseconds)
    event="$1"
    sfu_append_file "${timestamp} ${event}" "$LOG_FILE"
}

log_event "Application started"
log_event "Processing batch"
log_event "Batch complete"
```

### Protecting Against User Input

```bash
#!/bin/bash
source /path/to/secure-file-utils.sh

DATA_DIR="/var/lib/myapp/data"

save_user_file() {
    local filename="$1"
    local content="$2"

    # Validate path before writing
    local target="${DATA_DIR}/${filename}"

    if ! sfu_validate_path "$target" "$DATA_DIR"; then
        echo "ERROR: Invalid filename" >&2
        return 1
    fi

    sfu_write_file "$content" "$target" "644"
}

# Safe: stays in DATA_DIR
save_user_file "report.txt" "Report data"

# Blocked: attempts traversal
save_user_file "../../../etc/passwd" "malicious"
# Returns error, does not write
```

## Integration with systemd

When running under systemd with `StateDirectory=myapp`:

```ini
[Service]
StateDirectory=myapp
```

The library automatically uses `/var/lib/myapp` for temp files:

```bash
# STATE_DIRECTORY is set by systemd
# Temp files go to /var/lib/myapp/bash-toolkit-secure-root/
```

This survives reboots and is cleaned up with the service.

## Technical Details

### Atomic Write Process

1. Create temp file in secure directory (`mktemp`)
2. Write content to temp file
3. Set permissions (`chmod`)
4. Move temp file to target (`mv` - atomic on POSIX)

### Race Condition Prevention

```
Traditional write:
  [open] → [write partial] → [CRASH] → [partial file remains]

Atomic write:
  [write to temp] → [CRASH] → [temp cleaned up, original unchanged]
  [write to temp] → [mv atomic] → [complete file or nothing]
```

### umask Handling

The library temporarily sets `umask 077` during operations to ensure secure default permissions, then restores the original umask.

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [LOGGING.md](LOGGING.md) - Uses secure-file-utils.sh optionally
- [ERROR_HANDLING.md](ERROR_HANDLING.md) - For handling file operation errors
