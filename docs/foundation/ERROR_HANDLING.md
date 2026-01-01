# Error Handling Library (v2.0.0)

Domain-specific error handlers for Docker, network, and systemd services with automatic diagnostics and recovery suggestions.

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

source /path/to/foundation/logging.sh
source /path/to/foundation/error-handling.sh

# Enable automatic error traps
set_error_traps

# Docker error handling
if ! docker start nginx; then
    handle_docker_error "nginx" "Failed to start container"
    exit $ERROR_DOCKER
fi

# Network error handling
if ! sudo ip link set eth1 up; then
    handle_network_error "eth1" "Could not activate interface"
    exit $ERROR_NETWORK
fi
```

## Installation

```bash
# error-handling.sh requires logging.sh
source /path/to/bash-production-toolkit/src/foundation/logging.sh
source /path/to/bash-production-toolkit/src/foundation/error-handling.sh
```

## Error Codes

The library defines standard exit codes for different error domains:

| Constant | Code | Domain |
|----------|------|--------|
| `ERROR_NETWORK` | 10 | Network issues |
| `ERROR_DOCKER` | 20 | Docker container issues |
| `ERROR_FILESYSTEM` | 30 | File system issues |
| `ERROR_PERMISSION` | 40 | Permission denied |
| `ERROR_CONFIG` | 50 | Configuration errors |
| `ERROR_SERVICE` | 60 | systemd service issues |

**Usage:**
```bash
exit $ERROR_DOCKER  # Exit with code 20
```

## API Reference

### Domain Handlers

#### handle_error

```bash
handle_error exit_code "message" [component] [recovery_action]
```

Generic error handler with optional component and recovery.

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| exit_code | Yes | Error code to report |
| message | Yes | Error description |
| component | No | Affected component name |
| recovery_action | No | Command to run for recovery |

**Example:**
```bash
handle_error 1 "Configuration file missing" "config" "cp config.example config.yaml"
```

#### handle_docker_error

```bash
handle_docker_error "container_name" "error_message"
```

Handle Docker container errors with automatic diagnostics.

**Automatic actions:**
1. Log the error
2. Check container state
3. If exited: attempt restart
4. If failed: show logs
5. Suggest recovery steps

**Example:**
```bash
if ! docker exec myapp health-check; then
    handle_docker_error "myapp" "Health check failed"
fi
```

#### handle_network_error

```bash
handle_network_error "interface" "error_message"
```

Handle network interface errors with diagnostics.

**Automatic actions:**
1. Log the error
2. Show interface status (`ip link show`)
3. Attempt to bring interface UP
4. Suggest recovery steps

**Example:**
```bash
if ! ping -c 1 gateway.local; then
    handle_network_error "eth0" "Cannot reach gateway"
fi
```

#### handle_service_error

```bash
handle_service_error "service_name" "error_message"
```

Handle systemd service errors with diagnostics.

**Automatic actions:**
1. Log the error
2. Show service status
3. Show recent logs (`journalctl -u service -n 10`)
4. Attempt restart
5. Suggest recovery steps

**Example:**
```bash
if ! systemctl is-active nginx; then
    handle_service_error "nginx" "Service not running"
fi
```

### Recovery Suggestions

#### suggest_docker_recovery

```bash
suggest_docker_recovery "container_name"
```

Print Docker recovery commands to stdout.

**Output example:**
```
Suggested recovery steps for container 'nginx':
  1. docker logs nginx --tail 50
  2. docker inspect nginx
  3. docker restart nginx
  4. docker rm nginx && docker-compose up -d nginx
```

#### suggest_network_recovery

```bash
suggest_network_recovery "interface"
```

Print network recovery commands.

#### suggest_service_recovery

```bash
suggest_service_recovery "service_name"
```

Print systemd service recovery commands.

### Error Traps

#### set_error_traps

```bash
set_error_traps
```

Enable automatic error trap with stack trace on failures.

**Example:**
```bash
#!/bin/bash
set -uo pipefail

source /path/to/error-handling.sh
set_error_traps

# Any command that fails will trigger error_trap
false  # This triggers the trap
```

**Stack trace output:**
```
[ERROR] Command failed at line 15: false
[ERROR] Exit code: 1
[ERROR] Call stack:
[ERROR]   main() at script.sh:15
```

#### error_trap

```bash
error_trap line_number command
```

Internal trap handler. Called automatically when ERR trap fires.

### Safe Execution

#### safe_execute

```bash
safe_execute "command" "description" [recovery_action]
```

Execute a command with error handling wrapper.

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| command | Yes | Command to execute |
| description | Yes | Human-readable description |
| recovery_action | No | Command to run on failure |

**Example:**
```bash
safe_execute "docker start nginx" "Starting nginx container" "docker restart nginx"
```

### Health Checks

#### check_container_health

```bash
check_container_health "container_name"
```

Check Docker container health status.

**Returns:**
- 0: Container is healthy/running
- 1: Container is unhealthy/stopped

**Example:**
```bash
if check_container_health "postgres"; then
    echo "Database is ready"
else
    handle_docker_error "postgres" "Database not healthy"
fi
```

### Recovery Mode

#### enable_recovery_mode

```bash
enable_recovery_mode
```

Enable automatic recovery attempts in error handlers.

When enabled:
- `handle_docker_error` automatically restarts containers
- `handle_network_error` automatically brings interfaces UP
- `handle_service_error` automatically restarts services

```bash
enable_recovery_mode

# Now errors trigger automatic recovery
handle_docker_error "nginx" "Container crashed"
# Automatically runs: docker restart nginx
```

### Statistics

#### cleanup_and_exit

```bash
cleanup_and_exit [exit_code]
```

Print error/warning summary and exit.

**Example:**
```bash
# At end of script
cleanup_and_exit $?
# Output: "Script completed with 2 errors and 1 warning"
```

## Global Counters

The library tracks error statistics:

| Variable | Description |
|----------|-------------|
| `ERROR_COUNT` | Total errors encountered |
| `WARNING_COUNT` | Total warnings encountered |
| `RECOVERY_MODE` | Whether auto-recovery is enabled |

```bash
# Check error count
if [[ $ERROR_COUNT -gt 0 ]]; then
    echo "Script had $ERROR_COUNT errors"
fi
```

## Examples

### Docker Deployment Script

```bash
#!/bin/bash
set -uo pipefail

source /path/to/logging.sh
source /path/to/error-handling.sh

set_error_traps
enable_recovery_mode

deploy_container() {
    local container="$1"
    local image="$2"

    log_info "Deploying ${container}"

    if ! docker pull "$image"; then
        handle_docker_error "$container" "Failed to pull image"
        return $ERROR_DOCKER
    fi

    if ! docker stop "$container" 2>/dev/null; then
        log_debug "Container not running, skipping stop"
    fi

    if ! docker run -d --name "$container" "$image"; then
        handle_docker_error "$container" "Failed to start container"
        return $ERROR_DOCKER
    fi

    log_success "Deployed ${container}"
}

deploy_container "web" "nginx:latest"
deploy_container "api" "myapp:latest"

cleanup_and_exit
```

### Network Health Monitor

```bash
#!/bin/bash
set -uo pipefail

source /path/to/logging.sh
source /path/to/error-handling.sh

check_interface() {
    local iface="$1"
    local gateway="$2"

    if ! ip link show "$iface" | grep -q "state UP"; then
        handle_network_error "$iface" "Interface is DOWN"
        return $ERROR_NETWORK
    fi

    if ! ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
        handle_network_error "$iface" "Cannot reach gateway ${gateway}"
        return $ERROR_NETWORK
    fi

    log_info "Interface ${iface} is healthy"
}

check_interface "eth0" "192.168.1.1"
check_interface "eth1" "10.0.0.1"
```

### systemd Service Checker

```bash
#!/bin/bash
set -uo pipefail

source /path/to/logging.sh
source /path/to/error-handling.sh

REQUIRED_SERVICES=(
    "nginx"
    "postgresql"
    "redis"
)

for service in "${REQUIRED_SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$service"; then
        handle_service_error "$service" "Service not running"
    else
        log_info "Service ${service} is running"
    fi
done

if [[ $ERROR_COUNT -gt 0 ]]; then
    log_error "Health check failed: ${ERROR_COUNT} services down"
    exit 1
fi

log_success "All services healthy"
```

### Custom Error Handler

```bash
#!/bin/bash
source /path/to/logging.sh
source /path/to/error-handling.sh

# Custom handler for database errors
handle_database_error() {
    local db="$1"
    local message="$2"

    log_error "[DATABASE] ${message}"
    log_error "Database: ${db}"

    # Custom diagnostics
    if command -v psql >/dev/null; then
        log_info "Checking PostgreSQL status..."
        pg_isready -h localhost || true
    fi

    # Use generic handler for recovery suggestions
    handle_error 50 "$message" "database"
}

# Usage
if ! psql -c "SELECT 1" >/dev/null 2>&1; then
    handle_database_error "main" "Database connection failed"
    exit $ERROR_CONFIG
fi
```

## Integration with Alerting

Combine with [alerts.sh](../monitoring/ALERTS.md) for notifications:

```bash
#!/bin/bash
source /path/to/logging.sh
source /path/to/error-handling.sh
source /path/to/monitoring/alerts.sh

export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat"

if ! docker start nginx; then
    handle_docker_error "nginx" "Container failed to start"
    send_telegram_alert "docker_error" "nginx container failed to start" "🚨"
    exit $ERROR_DOCKER
fi
```

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Error handling philosophy
- [LOGGING.md](LOGGING.md) - Required dependency
- [ALERTS.md](../monitoring/ALERTS.md) - For alerting on errors
