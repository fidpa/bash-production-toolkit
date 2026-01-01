# Device Detection Library (v1.2.0)

Multi-strategy device detection for scripts that run across different hosts. Supports hostname patterns, IP-based detection, and custom device registration.

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

source /path/to/utilities/device-detection.sh

# Detect current device
device=$(detect_device)
echo "Running on: $device"

# Get architecture
arch=$(get_device_architecture)
echo "Architecture: $arch"

# Conditional execution
on_device "router" echo "This only runs on router"
not_on_device "laptop" echo "This runs everywhere except laptop"
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/utilities/device-detection.sh
```

## Detection Strategy

The library uses multiple strategies in order:

1. **Environment override** (`DEVICE_OVERRIDE`)
2. **Config file** (if `yq` available)
3. **Hostname patterns**
4. **IP-based fallback**
5. **Default: "unknown"**

## API Reference

### detect_device

```bash
device=$(detect_device)
```

Detect the current device type.

**Returns:** Device identifier string (e.g., "router", "server", "laptop")

**Caching:** Result is cached in `_DETECTED_DEVICE` for performance.

**Example:**
```bash
device=$(detect_device)

case "$device" in
    router)
        echo "Configuring as router"
        ;;
    server)
        echo "Configuring as server"
        ;;
    *)
        echo "Unknown device: $device"
        ;;
esac
```

### get_device_architecture

```bash
arch=$(get_device_architecture)
```

Get CPU architecture with normalization.

**Returns:**
- `arm64` (normalized from `aarch64`)
- `x86_64` (normalized from `amd64`)
- Raw `uname -m` output if no mapping

**Example:**
```bash
arch=$(get_device_architecture)

if [[ "$arch" == "arm64" ]]; then
    BINARY="myapp-arm64"
else
    BINARY="myapp-amd64"
fi
```

### is_arm_device

```bash
if is_arm_device; then
    echo "Running on ARM"
fi
```

Check if running on ARM architecture.

**Returns:** 0 (true) if ARM, 1 (false) otherwise

### is_x86_device

```bash
if is_x86_device; then
    echo "Running on x86"
fi
```

Check if running on x86/AMD64 architecture.

### get_device_info

```bash
get_device_info [field]
```

Get device information.

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| field | (all) | Specific field: hostname, ip, arch, os, kernel |

**Example:**
```bash
# Get all info
get_device_info
# hostname: myserver
# ip: 192.168.1.100
# arch: x86_64
# os: Ubuntu 22.04.3 LTS
# kernel: 5.15.0-91-generic

# Get specific field
hostname=$(get_device_info hostname)
```

### register_device

```bash
register_device "pattern" "device_id"
```

Register a custom device mapping at runtime.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| pattern | Hostname pattern (glob or exact match) |
| device_id | Device identifier to return |

**Example:**
```bash
# Register custom devices
register_device "prod-*" "production"
register_device "staging-*" "staging"
register_device "dev-*" "development"

# Now detect_device() will match these patterns
device=$(detect_device)  # Returns "production" on prod-web-01
```

### on_device

```bash
on_device "device_id" command [args...]
```

Run command only on specific device.

**Example:**
```bash
# Only run on router
on_device "router" systemctl restart networking

# Only run on server
on_device "server" docker-compose up -d

# Can be used with any command
on_device "laptop" echo "Running on laptop"
```

### not_on_device

```bash
not_on_device "device_id" command [args...]
```

Run command on all devices except specified.

**Example:**
```bash
# Don't run on production
not_on_device "production" echo "Running tests"

# Run everywhere except router
not_on_device "router" apt-get update
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DEVICE_OVERRIDE` | Force specific device (for testing) |
| `DEVICE_CONFIG_FILE` | Path to YAML config (optional) |
| `VERBOSE` | Enable debug output |

### Override Detection

```bash
# Force detection result (useful for testing)
export DEVICE_OVERRIDE="router"
device=$(detect_device)  # Always returns "router"
```

## Default Detection Patterns

### Hostname Patterns

| Pattern | Device ID |
|---------|-----------|
| `*router*`, `*gateway*` | router |
| `*nas*`, `*storage*`, `*server*` | server |
| `*pi*`, `*raspberry*` | raspberry-pi |
| `*laptop*`, `*notebook*`, `*dell*`, `*thinkpad*` | laptop |
| `*desktop*`, `*workstation*` | desktop |

### IP-Based Fallback

| IP Pattern | Device ID |
|------------|-----------|
| `10.0.0.1`, `192.168.1.1`, `192.168.0.1` | router |
| `10.0.0.2`, `192.168.1.2` | server |
| `10.0.0.*` | infrastructure |
| `192.168.*.*` | client |

## Examples

### Multi-Device Deployment Script

```bash
#!/bin/bash
set -euo pipefail

source /path/to/device-detection.sh

device=$(detect_device)
arch=$(get_device_architecture)

echo "Deploying to: ${device} (${arch})"

# Device-specific deployment paths
case "$device" in
    router)
        DEPLOY_PATH="/opt/router"
        SERVICES=("networking" "dhcp" "dns")
        ;;
    server)
        DEPLOY_PATH="/opt/server"
        SERVICES=("docker" "nginx" "postgresql")
        ;;
    raspberry-pi)
        DEPLOY_PATH="/opt/pi"
        SERVICES=("monitoring" "sensors")
        ;;
    *)
        echo "Unknown device, using defaults"
        DEPLOY_PATH="/opt/app"
        SERVICES=()
        ;;
esac

# Deploy
cp -r ./dist/* "$DEPLOY_PATH/"

# Restart services
for service in "${SERVICES[@]}"; do
    systemctl restart "$service"
done
```

### Architecture-Aware Binary Selection

```bash
#!/bin/bash
set -euo pipefail

source /path/to/device-detection.sh

arch=$(get_device_architecture)
BINARY_URL="https://example.com/releases/myapp-${arch}"

echo "Downloading binary for ${arch}..."
curl -L "$BINARY_URL" -o /usr/local/bin/myapp
chmod +x /usr/local/bin/myapp
```

### Conditional Configuration

```bash
#!/bin/bash
set -euo pipefail

source /path/to/device-detection.sh

# Base configuration
CONFIG="
server:
  port: 8080
"

# Device-specific additions
on_device "router" CONFIG+="
  firewall: enabled
  nat: true
"

on_device "server" CONFIG+="
  workers: 8
  database: postgresql://localhost/app
"

echo "$CONFIG" > /etc/myapp/config.yaml
```

### Environment Setup

```bash
#!/bin/bash
source /path/to/device-detection.sh

device=$(detect_device)

# Set environment based on device
case "$device" in
    production|server)
        export NODE_ENV="production"
        export LOG_LEVEL="warn"
        ;;
    staging)
        export NODE_ENV="staging"
        export LOG_LEVEL="info"
        ;;
    *)
        export NODE_ENV="development"
        export LOG_LEVEL="debug"
        ;;
esac

exec node server.js
```

### Custom Device Registration

```bash
#!/bin/bash
source /path/to/device-detection.sh

# Register your infrastructure naming convention
register_device "web-*" "webserver"
register_device "db-*" "database"
register_device "cache-*" "cache"
register_device "worker-*" "worker"

device=$(detect_device)

case "$device" in
    webserver)
        install_nginx
        ;;
    database)
        install_postgresql
        ;;
    cache)
        install_redis
        ;;
    worker)
        install_celery
        ;;
esac
```

### Health Check with Device Context

```bash
#!/bin/bash
set -euo pipefail

source /path/to/device-detection.sh
source /path/to/monitoring/alerts.sh

device=$(detect_device)
export TELEGRAM_PREFIX="[${device}]"

# Device-specific checks
case "$device" in
    router)
        check_wan_connectivity
        check_dhcp_leases
        ;;
    server)
        check_docker_containers
        check_disk_space
        ;;
esac
```

## YAML Configuration (Optional)

If `yq` is available, you can use a YAML config file:

```yaml
# devices.yml
devices:
  production-web-01:
    type: webserver
    role: primary
  production-web-02:
    type: webserver
    role: secondary
  production-db-01:
    type: database
    role: primary
```

```bash
export DEVICE_CONFIG_FILE="/etc/myapp/devices.yml"
source /path/to/device-detection.sh

device=$(detect_device)  # Uses YAML config if available
```

## Caching

Detection results are cached to avoid repeated system calls:

```bash
# First call - performs detection
device=$(detect_device)  # ~10ms

# Subsequent calls - returns cached result
device=$(detect_device)  # ~0ms
```

To force re-detection:
```bash
unset _DETECTED_DEVICE
device=$(detect_device)  # Re-detects
```

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [LOGGING.md](../foundation/LOGGING.md) - For device-aware logging
- [ALERTS.md](../monitoring/ALERTS.md) - For device-prefixed alerts
