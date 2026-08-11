# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.4.3] - 2026-08-11

### Fixed
- `examples/*.sh` (7 scripts) and `install.sh`: restored the executable bit
  (`chmod 644` → `755`). `README.md` and `examples/README.md` have always
  documented direct invocation (`./examples/01-logging-basics.sh`), but the
  files themselves were not executable — following the docs literally failed
  with `Permission denied`. `bash examples/01-logging-basics.sh` still worked
  as a workaround, which is why the regression went unnoticed. No script
  content changed.

## [2.4.2] - 2026-08-08

Maintenance release. No library code changed — every version number in the
documentation now matches the `# Version:` header of the library it describes,
and release notes are built from this changelog instead of from commit messages.

### Fixed
- Documentation version drift across 12 references in 5 files. Six of ten
  libraries advertised a version they had outgrown: `logging.sh` (2.0.0 → 2.1.0),
  `simple-logging.sh` (1.0.0 → 1.2.0), `secure-file-utils.sh` (1.0.0 → 1.1.0),
  `error-handling.sh` (1.0.0 → 1.0.1), `smart-alerts.sh` (2.0.0 → 2.1.0) and
  `backup-safety.sh` (1.0.0 → 1.1.0). Affected: the directory tree in
  `docs/README.md`, the dependency graph in `docs/ARCHITECTURE.md`, and the
  heading lines of `docs/foundation/LOGGING.md`,
  `docs/foundation/SECURE_FILE_UTILS.md` and `docs/monitoring/SMART_ALERTS.md`.
  The library headers were correct throughout; only the documentation lagged.
  One reference — `simple-logging.sh (v1.1.1)` in `docs/foundation/LOGGING.md` —
  named a version that never existed: the file went from 1.0.0 (v2.1.0) straight
  to 1.2.0 (v2.4.0). This matters for a sourced library, where the header version
  is how a consumer decides whether the fix they need is in the copy they have.

### Changed
- `.github/workflows/release.yml`: release notes are now extracted from the
  matching `CHANGELOG.md` section instead of generated from commit messages.
  With this repository's bare `vX.Y.Z` commit subjects, `generate_release_notes`
  produced release pages containing nothing but a compare link (v2.4.1: 92
  characters) while the changelog held the actual write-up. The extraction step
  fails the workflow on an empty result rather than publishing an empty release.
- `.gitignore`: ignore local assistant configuration (`.claude/`, `CLAUDE.md`).

## [2.4.1] - 2026-07-16

Documentation-only release, prompted by a field incident in a downstream
deployment: a `log_warning` line inside a command-substituted function leaked
into the captured value and broke a sed expression during a real WAN outage.

### Added
- `docs/foundation/LOGGING.md` / `docs/TROUBLESHOOTING.md`: Documented the command-substitution pitfall — with `LOG_TO_STDOUT=true` (default), `log_*` calls inside functions captured via `$(...)` leak the log line into the captured value (latent until the logging branch fires). Fix pattern: `log_warning "..." >&2` in captured functions. Also documented that the `:=` defaults are applied at source time, so overrides must be set *before* sourcing `logging.sh`.

## [2.4.0] - 2026-07-15

### Fixed
- `logging.sh` v2.1.0: Removed the INT/TERM trap — a trap without re-raise made every sourcing script **survive SIGTERM/SIGINT** (under systemd, `stop` then escalates to SIGKILL after `TimeoutStopSec`). The `ORIGINAL_PWD` restore machinery was removed with it: the library only changes directory in subshells, so the caller's working directory never needs restoring.
- `logging.sh`: ERROR/CRITICAL messages are now always logged regardless of `LOG_LEVEL`, matching the documented `log_error_structured()` semantics.
- `logging.sh`: Exported functions now work in fresh child shells (`bash -c`, `xargs bash`) — `get_log_level_value` and `log_info_structured` were missing from `export -f`, and the configuration variables the functions read are now exported. Metrics are skipped in child shells (associative arrays cannot be exported).
- `logging.sh`: Zero-argument calls (e.g. `log_info $empty_var` with an unquoted empty variable) no longer kill callers running under `set -u`; log lines no longer end with a trailing space when no context fields are given; `log_to_journald_legacy()` closes stdin like the structured variant (prevents a journald hang).
- `simple-logging.sh` v1.2.0: `log_warning()` was filtered at INFO level because `WARNING` did not map to the `WARN` level value; the log file is now created with `600` permissions instead of only being chmod'ed when it already existed; `logger` calls close stdin.
- `simple-logging.sh` v1.2.0 / `secure-file-utils.sh` v1.1.0: Removed file-scope `set -uo pipefail` — a sourced library must not change the caller's shell options (the leak reached every caller of all three foundation libraries).
- `smart-alerts.sh` v2.1.0: Removed file-scope `set -uo pipefail` (same flag-leak fix as the foundation libraries — with this, no library in the toolkit sets file-scope shell flags anymore). `ARCHITECTURE.md` § Error Handling Philosophy updated: libraries set no file-scope flags and are written to be `set -u` clean.
- `simple-logging.sh`: `get_log_level_value()` renamed to `_slog_get_log_level_value()` — the name collided with `logging.sh`'s function of the same name, which uses an incompatible level scale, silently corrupting level filtering when both libraries were loaded.

### Added
- `logging.sh` / `simple-logging.sh`: Warn on stderr when both libraries are loaded in the same shell — they define the same `log_*` names with different semantics (last one sourced wins).

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

[Unreleased]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.3...HEAD
[2.4.3]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.2...v2.4.3
[2.4.2]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/fidpa/bash-production-toolkit/releases/tag/v1.0.0
