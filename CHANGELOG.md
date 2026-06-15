# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.3.0] - 2026-06-15

### Added
- `retry.sh` (utilities) — resilient retry primitives:
  - `calculate_backoff()` — exponential backoff (`base * 2^attempt`), capped, with optional jitter; overflow-safe bounded loop instead of the `**` operator
  - `retry_with_backoff()` — bounded retry wrapper that propagates the command's exit code
  - Optional `logging.sh` integration (plain-echo fallback); config via `RETRY_BASE_DELAY`, `RETRY_MAX_DELAY`, `RETRY_JITTER`
- `examples/07-self-healing-daemon.sh` — crash-resilient supervise loop combining retry, logging, secure-file-utils (single-instance lock) and alerts, with an optional precondition gate
- `docs/utilities/RETRY.md` — API reference, configuration, and usage patterns
- `tests/` — dependency-free test suite (pure Bash, no `bats`): `lib/assert.sh` helpers, `test-retry.sh` (unit tests for retry.sh), `smoke-examples.sh` (runs dependency-free examples), `run-all.sh` runner

### Changed
- CI: consolidated `lint.yml` into `ci.yml` (ShellCheck + Bash syntax + test suite); ShellCheck/syntax checks now also cover `tests/`. README CI badge points to `ci.yml`.

## [2.2.0] - 2026-04-20

### Fixed
- `simple-logging.sh`: Log functions (`log_info`, `log_success`, `log_error`, `log_warning`, `log_debug`) no longer return exit code 1 when the log file is not writable. Logging is best-effort — a missing or unwritable log file must not abort callers using `set -euo pipefail`.

## [2.1.0] - 2026-02-27

### Changed
- Version references updated across docs, examples, and install.sh

## [2.0.0] - 2026-02-24

### Added
- `LOG_LEVEL_NOTICE=2` in logging.sh — new level between INFO and WARN (RFC 5424 aligned)
- `log_notice()` wrapper and `notice()` alias in logging.sh
- `log_notice_structured()` — structured logging for NOTICE level with journald fields
- `detect_environment()` in logging.sh — auto-detects prod/dev/test from hostname and ENV
- `SCRIPT_ENV` variable populated on library load
- `notice_count` metric tracking in `SCRIPT_METRICS`
- `_derive_severity()` in alerts.sh — auto-derives severity from alert_type name patterns
- `ALERT_WEBHOOK_URL` — generic webhook endpoint configuration (Mattermost/Slack/Discord)
- `ALERT_WEBHOOK_CACERT` — optional CA cert path for self-signed TLS endpoints
- `send_alert()` — new primary public API replacing `send_telegram_alert()`

### Changed
- **BREAKING** (alerts.sh): Removed Telegram backend (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`)
- **BREAKING** (alerts.sh): Removed `send_telegram_alert()` — use `send_alert()` instead
- **BREAKING** (alerts.sh): Renamed `TELEGRAM_PREFIX` → `ALERTS_PREFIX`
- **BREAKING** (logging.sh): Level values shifted — WARN=3, ERROR=4, CRITICAL=5 (was 2/3/4)
- `log_success()` in logging.sh is now a deprecated alias for `log_notice()` (was `log_info()`)
- `success()` alias now maps to `log_notice()` (was `log_info()`)
- `send_recovery_alert()` now uses `send_alert()` internally
- smart-alerts.sh: `_sa_send_immediate_alert()` uses `send_alert()` instead of `send_telegram_alert()`
- smart-alerts.sh: `_sa_send_pending_alert()` uses `send_alert()` instead of `send_telegram_alert()`
- smart-alerts.sh: `sa_register_recovery()` uses `send_alert()` with `_RECOVERED` suffix

### Migration from v1.x

**alerts.sh users:**
```bash
# Before (v1.x)
export TELEGRAM_BOT_TOKEN="123:abc"
export TELEGRAM_CHAT_ID="-1234"
export TELEGRAM_PREFIX="[MyApp]"
send_telegram_alert "backup_failed" "Disk full" "❌"

# After (v2.0.0)
export ALERT_WEBHOOK_URL="https://your-mattermost/hooks/TOKEN"
export ALERTS_PREFIX="[MyApp]"
send_alert "BACKUP_FAILED" "Disk full"
# emoji and severity auto-derived from alert type name
```

**logging.sh users (if using LOG_LEVEL=WARN/ERROR/CRITICAL numerically):**
```bash
# Level values shifted by +1 for NOTICE insertion. If you relied on numeric values:
# Before: WARN=2, ERROR=3, CRITICAL=4
# After:  WARN=3, ERROR=4, CRITICAL=5
# Only affects direct numeric comparisons - string comparisons unchanged.
```

## [1.2.0] - 2026-01-21

### Added
- Installation script (`install.sh`) for user-home-based setup
- Community guidelines (`CONTRIBUTING.md`) with development workflow
- Security policy (`SECURITY.md`) with vulnerability reporting
- GitHub issue templates (bug report, feature request)
- GitHub pull request template
- Issue config to guide contributors

### Changed
- Extended README badges from 4 to 7 (added ShellCheck, Release, Maintained)
- Improved repository structure for open-source contributions

## [1.0.0] - 2026-01-20

### Added
- Initial release
- Foundation libraries: logging.sh, simple-logging.sh, secure-file-utils.sh, error-handling.sh
- Monitoring libraries: alerts.sh, smart-alerts.sh
- Utility libraries: device-detection.sh, path-calculator.sh, backup-safety.sh
- 6 example scripts demonstrating library usage
- Comprehensive documentation (12 docs)
- CI/CD pipeline with ShellCheck linting

[Unreleased]: https://github.com/fidpa/bash-production-toolkit/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/fidpa/bash-production-toolkit/releases/tag/v1.0.0
