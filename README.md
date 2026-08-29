# Bash Production Toolkit

![CI](https://github.com/fidpa/bash-production-toolkit/actions/workflows/ci.yml/badge.svg)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen?logo=gnu-bash)
![Release](https://img.shields.io/github/v/release/fidpa/bash-production-toolkit)
![Maintained](https://img.shields.io/badge/Maintained-yes-brightgreen.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Bash 4.0+](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![Libraries](https://img.shields.io/badge/Libraries-10-orange)
![Last Commit](https://img.shields.io/github/last-commit/fidpa/bash-production-toolkit)

Ten Bash libraries for the parts of a script that get rewritten in every project: logging,
writing a file without leaving a half-written one behind, alerting a chat channel
without flooding it, retrying a flaky command. You source the files you need. There
is no framework to adopt, no runtime, and no build step.

The count of ten is the file count under [src/](src/): four foundation libraries,
two for monitoring, four utilities. Each has its own version number in its header
and its own document under [docs/](docs/).

## Scope

- **Libraries, not a service.** Nothing here runs on its own; every function is
  called from a script you maintain. The repository has no daemon, no systemd unit,
  and no state of its own beyond the directories the alert libraries write to.
- **`secure-file-utils.sh` is hygiene, not a security boundary.** A write goes to a
  `0700` temp directory under `TMPDIR` (or systemd's `STATE_DIRECTORY`), gets its
  permissions set there, and is then moved into place, so a reader sees either the
  old file or the new one, never a half-written or briefly world-readable one. The
  rename is what makes that true, so it holds only while temp directory and target
  sit on the same filesystem; across filesystems `mv` copies. It does not sandbox
  the caller either, and when the target directory is not writable it falls back to
  `sudo mv` - the caller decides whether that is acceptable.
- **Linux first.** `simple-logging.sh` is written for Linux and macOS, the rest
  assumes Linux; the journald paths of `logging.sh` and the systemd handlers of
  `error-handling.sh` have no macOS equivalent. Every library header declares Bash
  4.0+, so the Bash 3.2 that ships as `/bin/bash` on macOS is not enough anywhere.
- **The test suite covers one library.** `retry.sh` has unit tests; the other nine
  are covered only by the smoke test that runs four examples end to end. See
  [Testing](#testing) for what that does and does not prove.

## Libraries

### Foundation

| Library | What it does |
|---------|--------------|
| [logging.sh](docs/foundation/LOGGING.md) | Six log levels along RFC 5424, journald and JSON output, size-based rotation (`LOG_ROTATE_SIZE`, default `10M`) |
| [simple-logging.sh](docs/foundation/LOGGING.md#comparison-loggingsh-vs-simple-loggingsh) | Terminal plus file logging for hooks and short scripts, five levels, no journald |
| [secure-file-utils.sh](docs/foundation/SECURE_FILE_UTILS.md) | `sfu_write_file`, `sfu_append_file`, `sfu_heredoc` write through a private temp file; `sfu_validate_path` rejects paths outside a given base |
| [error-handling.sh](docs/foundation/ERROR_HANDLING.md) | `set_error_traps` with stack traces, plus handlers for network, Docker and systemd failures that print the diagnosis commands. Requires `logging.sh` |

### Monitoring

| Library | What it does |
|---------|--------------|
| [alerts.sh](docs/monitoring/ALERTS.md) | Slack-compatible webhooks (Mattermost, Slack, Discord, or any endpoint taking `{"text": "..."}`); one message per alert type per `RATE_LIMIT_SECONDS`, severity derived from the type name |
| [smart-alerts.sh](docs/monitoring/SMART_ALERTS.md) | Holds an event for a grace period before it alerts, and only reports recovery if the outage lasted long enough. State is JSON, so `jq` is required |

### Utilities

| Library | What it does |
|---------|--------------|
| [backup-safety.sh](docs/utilities/BACKUP_SAFETY.md) | Refuses a backup target that is not a mountpoint or sits on the root partition, and checks free space first. Written after a backup wrote 25 GB to an unmounted path |
| [device-detection.sh](docs/utilities/DEVICE_DETECTION.md) | Identifies the host by hostname, IP or config file; `on_device` / `not_on_device` guard host-specific branches, `get_device_architecture` reports arm64 or x86_64 |
| [path-calculator.sh](docs/utilities/PATH_CALCULATOR.md) | Relative paths between files and markdown-aware link paths, for documentation tooling |
| [retry.sh](docs/utilities/RETRY.md) | `retry_with_backoff N command...` with a delay that doubles up to `RETRY_MAX_DELAY` and optional jitter; the doubling is a bounded loop, so a large attempt count cannot overflow |

## Quick Start

```bash
#!/bin/bash
set -uo pipefail

# Source the libraries
source /path/to/bash-production-toolkit/src/foundation/logging.sh
source /path/to/bash-production-toolkit/src/foundation/secure-file-utils.sh

# Use them
log_info "Application started"
sfu_write_file "config data" "/var/lib/myapp/config.txt" "644"
log_notice "Configuration saved"
```

The third argument to `sfu_write_file` is the file mode; without it the file is
written `600`. The libraries set no shell options of their own, so `set -uo pipefail`
in the example above stays yours: they return exit codes and leave the reaction to
the caller.

## Installation

Clone the repository and source what you need:

```bash
git clone https://github.com/fidpa/bash-production-toolkit.git
```

```bash
TOOLKIT="/path/to/bash-production-toolkit/src"
source "${TOOLKIT}/foundation/logging.sh"
```

For a copy outside the clone, `install.sh` copies `src/`, `examples/` and `docs/` to
a prefix and writes an `init.sh` that exports `BASH_PRODUCTION_TOOLKIT` and
`BASH_TOOLKIT_LIB`:

```
Usage: ./install.sh [OPTIONS]

Install Bash Production Toolkit to your system.

OPTIONS:
    --prefix DIR         Installation directory (default: ~/.local/share/bash-production-toolkit)
    --skip-completion    Skip bash completion installation
    --help, -h           Show this help message

EXAMPLE:
    ./install.sh
    ./install.sh --prefix /opt/bash-toolkit
    ./install.sh --skip-completion

After installation, add to your .bashrc or .bash_profile:
    export BASH_PRODUCTION_TOOLKIT="~/.local/share/bash-production-toolkit"
    source "${BASH_PRODUCTION_TOOLKIT}/init.sh"
```

The help expands the prefix, so the path in those last lines shows up as your own
home directory. The libraries keep their subdirectories under the prefix, so the
source line that follows reads
`source "${BASH_TOOLKIT_LIB}/foundation/logging.sh"`.

## Configuration

Everything is configured through environment variables set before sourcing.
[config/toolkit.env.example](config/toolkit.env.example) lists all of them with
their defaults; the table below is the subset that changes behaviour most often.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Minimum level: `DEBUG`, `INFO`, `NOTICE`, `WARN`, `ERROR`, `CRITICAL` |
| `LOG_FORMAT` | `standard` | `standard`, `json` or `compact` |
| `LOG_TO_JOURNAL` | `false` | Send to journald when running under systemd |
| `LOG_TO_STDOUT` | `true` | Also write to the terminal |
| `LOG_DIR` | `/var/log` | Directory for the log file |
| `LOG_ROTATE_SIZE` | `10M` | Size at which the log file is rotated |
| `LOG_ROTATE_COUNT` | `5` | Rotated files kept |
| `ALERT_WEBHOOK_URL` | none, required | Slack-compatible webhook endpoint for `alerts.sh` |
| `ALERT_WEBHOOK_CACERT` | unset | CA certificate for a self-signed endpoint |
| `ALERTS_PREFIX` | `[System]` | Prefix on every alert message |
| `RATE_LIMIT_SECONDS` | `1800` | Cooldown per alert type |
| `ENABLE_RECOVERY_ALERTS` | `true` | Send a message when a condition clears |
| `STATE_DIR` | `/var/lib/alerts` | Rate-limit state of `alerts.sh` |
| `SMART_ALERT_GRACE_PERIOD` | `180` | Seconds an event must persist before it alerts |
| `SMART_ALERT_RECOVERY_THRESHOLD` | `300` | Minimum outage length for a recovery message |
| `SMART_ALERT_AGGREGATION_WINDOW` | `300` | Window in which events are aggregated |
| `SMART_ALERT_STATE_DIR` | `/var/lib/smart-alerts` | State of `smart-alerts.sh` |
| `RETRY_BASE_DELAY` | `1` | First delay in seconds, doubled per attempt |
| `RETRY_MAX_DELAY` | `60` | Cap on the delay |
| `RETRY_JITTER` | `0` | Random seconds added on top, `0` turns jitter off |
| `BACKUP_BASE_DIR` | `/opt/backups` | Base directory for `get_backup_path` |
| `BACKUP_MIN_FREE_GB` | `10` | Free space a backup target must have |
| `DEVICE_CONFIG_FILE` | `devices.yml` next to the library | YAML device map, read with `yq` if present |
| `DEVICE_OVERRIDE` | unset | Force a device name, for testing |

## Requirements

- Bash 4.0+
- Standard Unix utilities (coreutils, plus `df` and `stat` for `backup-safety.sh`)
- `curl` for `alerts.sh`; without it no webhook is sent
- `jq` for `smart-alerts.sh`; the library refuses to load without it
- `yq` for the YAML device map of `device-detection.sh`; hostname and IP detection
  work without it

## Documentation

Full documentation is in the [docs/](docs/) directory:

- [Overview](docs/README.md)
- [Setup Guide](docs/SETUP.md) covers installation, configuration and systemd integration
- [Architecture](docs/ARCHITECTURE.md) covers library dependencies and patterns
- [Troubleshooting](docs/TROUBLESHOOTING.md)

Each library has its own page, linked from the tables above.

## Examples

The [examples/](examples/) directory holds runnable scripts:

```bash
./examples/01-logging-basics.sh
./examples/02-file-operations.sh
./examples/03-webhook-alerts.sh          # needs ALERT_WEBHOOK_URL
./examples/07-self-healing-daemon.sh     # supervise loop: retry + lock + alerts
```

## Testing

The test suite is pure Bash with no `bats` and no other dependency:

```bash
bash tests/run-all.sh
```

`run-all.sh` picks up every `test-*.sh` and `smoke-*.sh` in `tests/`. Today those are
unit tests for `retry.sh` and a smoke test that runs examples 01, 02, 04, 05 and 07
and fails if one of them exits non-zero. That proves the dependency-free libraries
load and run; it does not exercise journald, webhooks or the backup and device
checks, which need a host to be true about.

CI (`ci.yml`) runs on every push and pull request against `main`: ShellCheck at
`--severity=error` over `src`, `examples` and `tests`, a `bash -n` syntax check over
the same files, and this suite.

## Contributing

Contributions welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has the guidelines,
[SECURITY.md](SECURITY.md) the reporting path for anything security relevant.

- **Bug reports**: [open an issue](https://github.com/fidpa/bash-production-toolkit/issues/new?template=bug_report.md)
- **Feature requests**: [request a feature](https://github.com/fidpa/bash-production-toolkit/issues/new?template=feature_request.md)
- **Pull requests**: fork, change, submit

## License

MIT License, see [LICENSE](LICENSE).

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))
