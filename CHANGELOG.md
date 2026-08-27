# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.4.6] - 2026-08-27: Release notes match the tag they are published under

A release whose headline mentions another version number used to make the workflow serve
the wrong section. Tagging v2.4.5, whose headline reads "One unsupported claim removed
from the 2.4.0 section", meant that an extraction for version 2.4.0 matched the 2.4.5
heading first, because the match was a plain substring search over the whole line.

### Fixed
- **The release workflow selects a changelog section by its heading, not by a substring
  anywhere in the line.** `.github/workflows/release.yml` matches the literal prefix
  `## [VERSION]` at column 1 via awk's `index()`. A regex was not an option here: the
  brackets need escaping that does not survive the shell, and an unescaped `[` turns the
  pattern into a character class that matches nothing. Both the body extraction and the
  title extraction added in 2.4.4 used the substring form. If no section matches, the
  body extraction still fails the workflow and the title still falls back to the bare tag
  name.

### Upgrade notes

Nothing to do. This release changes CI behaviour only, and only for future tags.

## [2.4.5] - 2026-08-27: One unsupported claim removed from the 2.4.0 section

Follow-up to the editorial pass in 2.4.4. No library code changed. A sentence that pass
had left standing turned out to have no basis in the repository.

### Fixed
- **The 2.4.0 section no longer claims a semantics that was never documented.** It read
  "This matches the semantics `log_error_structured()` had always documented". Neither
  `src/foundation/logging.sh` nor `docs/foundation/LOGGING.md` says anything about
  `ERROR` and `CRITICAL` bypassing the level check, at `v1.0.0` or at `v2.3.0`; the
  function carries no doc comment at all. The behaviour the entry describes is real, only
  the justification was not. The entry now states what changed and why it matters,
  without appealing to documentation that does not exist.

### Upgrade notes

Nothing to do. This release changes one paragraph of changelog text.

## [2.4.4] - 2026-08-27: Editorial pass over the changelog

Editorial release. No library code changed. Every section below 2.4.4 was rewritten
against a written rule set for release messages: entries now lead with what changes for
an operator instead of with the code that changed, each release gets an opening paragraph
that names the symptom before the fix, and the file is plain ASCII. Three factual errors
that had been public since February, July and August 2026 were corrected in the process;
they are listed below rather than silently fixed.

### Fixed
- **A breaking change shipped in 2.1.0 was documented as a documentation update.** The
  2.1.0 section read "Version references updated across docs, examples, and install.sh".
  In fact `logging.sh` dropped `log_warn()` and `log_warn_structured()` without leaving
  aliases, renamed the constant `LOG_LEVEL_WARN` to `LOG_LEVEL_WARNING`, and changed the
  level string written into every log line from `WARN` to `WARNING`. The 2.1.0 section
  now carries a `**Breaking:**` entry and `### Upgrade notes`.
- **The 2.4.2 section claimed 12 documentation references, the diff contains 15.** Counted
  in `git diff v2.4.1 v2.4.2 -- docs/`: three in `docs/ARCHITECTURE.md`, six in
  `docs/README.md`, four in `docs/foundation/LOGGING.md`, one each in
  `docs/foundation/SECURE_FILE_UTILS.md` and `docs/monitoring/SMART_ALERTS.md`. The count
  of five files was correct.
- **The 2.4.0 section attributed a shell-flag leak to "all three foundation libraries".**
  At `v2.3.0` the libraries carrying a file-scope `set -uo pipefail` were
  `src/foundation/secure-file-utils.sh`, `src/foundation/simple-logging.sh` and
  `src/monitoring/smart-alerts.sh`. Two of the three were foundation libraries, the third
  was a monitoring library.
- **Release v1.2.2 had no changelog section.** Its release page carried nothing but the
  generated compare link. The section below was reconstructed from the tag annotation and
  the `v1.2.0..v1.2.2` diff.

### Changed
- **Tagging a release now produces a release title, not just a version number.**
  `.github/workflows/release.yml` reads the headline from the changelog section heading
  and passes it to `softprops/action-gh-release` as `name`. Without it the action falls
  back to the tag name, which is how the last five releases ended up titled `v2.3.0`,
  `v2.2.0` and so on. If a section has no headline, the workflow falls back to the plain
  tag name rather than failing the release.

### Upgrade notes

Nothing to do. No library file, function name, configuration variable or measured value
changed in this release. What changed is the wording of past changelog sections and the
title the release workflow sets.

## [2.4.3] - 2026-08-11: Examples runnable the way the docs describe

`README.md` and `examples/README.md` had always documented direct invocation
(`./examples/01-logging-basics.sh`), but the files carried mode `644`. Following the
documentation literally failed with `Permission denied`. The regression stayed unnoticed
because `bash examples/01-logging-basics.sh` still worked and is what most readers try
next.

### Fixed
- **The example scripts and the installer can be run the way the documentation says.**
  Seven scripts under `examples/` and `install.sh` went from mode `644` back to `755`
  (`git ls-tree -r v2.4.3 examples/ install.sh` shows the modes). No script content
  changed.

## [2.4.2] - 2026-08-08: Documentation versions match the libraries

Maintenance release. No library code changed. Every version number in the documentation
now matches the `# Version:` header of the library it describes, and release notes are
built from this changelog instead of from commit messages.

### Fixed
- **A consumer reading the documentation could no longer tell which library version a
  fix landed in.** Fifteen version references across five files had drifted. Six of the
  ten libraries advertised a version they had outgrown: `logging.sh` (2.0.0 to 2.1.0),
  `simple-logging.sh` (1.0.0 to 1.2.0), `secure-file-utils.sh` (1.0.0 to 1.1.0),
  `error-handling.sh` (1.0.0 to 1.0.1), `smart-alerts.sh` (2.0.0 to 2.1.0) and
  `backup-safety.sh` (1.0.0 to 1.1.0). Affected were the directory tree in
  `docs/README.md`, the dependency graph in `docs/ARCHITECTURE.md`, and the heading lines
  of `docs/foundation/LOGGING.md`, `docs/foundation/SECURE_FILE_UTILS.md` and
  `docs/monitoring/SMART_ALERTS.md`. The library headers were correct throughout, only
  the documentation lagged. One reference, `simple-logging.sh (v1.1.1)` in
  `docs/foundation/LOGGING.md`, named a version that never existed: the file went from
  1.0.0 (v2.1.0) straight to 1.2.0 (v2.4.0). This matters for a sourced library, where
  the header version is how a consumer decides whether the fix they need is in the copy
  they have.

  The count of fifteen was corrected in 2.4.4; this section originally said twelve.

### Changed
- **The release page now shows the write-up instead of a compare link.**
  `.github/workflows/release.yml` extracts release notes from the matching `CHANGELOG.md`
  section instead of generating them from commit messages. With this repository's bare
  `vX.Y.Z` commit subjects, `generate_release_notes` produced release pages containing
  nothing but a compare link (v2.4.1: 92 characters) while the changelog held the actual
  write-up. The extraction step fails the workflow on an empty result rather than
  publishing an empty release.
- **Local assistant configuration stays out of the repository.** `.gitignore` now covers
  `.claude/` and `CLAUDE.md`.

## [2.4.1] - 2026-07-16: The command substitution pitfall documented

Documentation-only release, prompted by a field incident in a downstream deployment: a
`log_warning` line inside a command-substituted function leaked into the captured value
and broke a `sed` expression during a real WAN outage.

### Added
- **Capturing the output of a function that logs no longer surprises the caller.**
  `docs/foundation/LOGGING.md` and `docs/TROUBLESHOOTING.md` document the
  command-substitution pitfall: with `LOG_TO_STDOUT=true`, which is the default, a `log_*`
  call inside a function captured via `$(...)` puts the log line into the captured value.
  The defect stays latent until the logging branch fires. The documented fix is
  `log_warning "..." >&2` in captured functions. The same pages now also state that the
  `:=` defaults are applied at source time, so an override has to be set before
  `logging.sh` is sourced.

## [2.4.0] - 2026-07-15: Libraries stop reaching into the caller shell

Three defects in this release share one cause: a sourced library reached into the state
of the shell that sourced it. One of them made systemd unable to stop a script the normal
way, one changed the caller's shell options behind its back, and one silently corrupted
level filtering when two of the toolkit's own libraries were loaded together.

### Fixed
- **Breaking:** **A script sourcing `logging.sh` no longer ignores SIGTERM and SIGINT.**
  The library installed an `INT TERM` trap that restored `ORIGINAL_PWD` without
  re-raising the signal, which made the sourcing script survive both. Under systemd,
  `systemctl stop` then escalates to SIGKILL after `TimeoutStopSec`. The trap is gone,
  and with it the `ORIGINAL_PWD` machinery: the library only changes directory in
  subshells, so the caller's working directory never needs restoring.
- **`ERROR` and `CRITICAL` messages are logged regardless of `LOG_LEVEL`.** Raising
  `LOG_LEVEL` past `ERROR` used to suppress them along with everything else, which meant
  a quieter log level could hide the failures it was least meant to hide. The level check
  in `log_structured()` no longer applies to those two levels.
- **Exported log functions work in a fresh child shell.** `get_log_level_value` and
  `log_info_structured` were missing from the `export -f` lists in `logging.sh`, so
  `bash -c` and `xargs bash` callers hit "command not found"; the configuration variables
  the functions read are now exported as well. Metrics are skipped in a child shell,
  because an associative array cannot be exported.
- **A log call with an unquoted empty variable no longer kills a `set -u` caller.**
  `log_info $empty_var` used to abort. In the same pass, a log line with no context fields
  stopped ending in a trailing space, and `log_to_journald_legacy()` closes stdin the way
  the structured variant does, which prevents a journald hang.
- **`log_warning()` in `simple-logging.sh` is no longer swallowed at INFO level.**
  `WARNING` did not map to the `WARN` level value in `get_log_level_value()`, so the call
  was filtered out. The library is v1.2.0 as of this release. Its log file is now created
  with mode `600` instead of being chmod'ed only when it already existed, and its `logger`
  calls close stdin.
- **Sourcing a library no longer changes the caller's shell options.**
  `src/foundation/simple-logging.sh` (v1.2.0), `src/foundation/secure-file-utils.sh`
  (v1.1.0) and `src/monitoring/smart-alerts.sh` (v2.1.0) each carried a file-scope
  `set -uo pipefail` that took effect in the sourcing shell. With these three removed, no
  library in the toolkit sets file-scope shell flags. `docs/ARCHITECTURE.md`, section
  "Error Handling Philosophy", now states that libraries set no file-scope flags and are
  written to be `set -u` clean.

  The attribution "all three foundation libraries" was corrected in 2.4.4: two of the
  three were foundation libraries, the third was a monitoring library.
- **Loading `logging.sh` and `simple-logging.sh` together no longer corrupts level
  filtering.** Both defined `get_log_level_value()` with incompatible level scales, and
  the last definition won. The `simple-logging.sh` one is now
  `_slog_get_log_level_value()`.

### Added
- **Loading both logging libraries in one shell produces a warning on stderr.** They
  define the same `log_*` names with different semantics, and the one sourced last wins.
  The warning does not prevent the load; it names the collision so the caller can decide.

### Upgrade notes

If a script relied on `logging.sh` absorbing SIGTERM or SIGINT, it now receives both.
Install your own trap if that behaviour was wanted. `ORIGINAL_PWD` is no longer defined by
the library; a script reading that variable has to set it itself.

## [2.3.0] - 2026-06-15: Retry primitives and a test suite

Feature release. The toolkit gained retry primitives and, for the first time, a test suite
that runs in CI.

### Added
- **A script can retry a flaky command without writing its own backoff loop.**
  `src/utilities/retry.sh` provides `calculate_backoff()`, which grows the delay as
  `RETRY_BASE_DELAY * 2^attempt`, caps it at `RETRY_MAX_DELAY` and adds up to
  `RETRY_JITTER` seconds of jitter. The doubling uses a bounded loop rather than the `**`
  operator, so a large attempt number cannot overflow into a negative delay. Defaults are
  `RETRY_BASE_DELAY=1`, `RETRY_MAX_DELAY=60` and `RETRY_JITTER=0`, which means jitter is
  off unless asked for. `retry_with_backoff()` wraps a command in a bounded retry and
  propagates the command's own exit code, so the caller still sees why it failed.
  `logging.sh` is used when it is loaded and a plain `echo` fallback when it is not.
- **A worked example of a daemon that restarts itself.**
  `examples/07-self-healing-daemon.sh` combines retry, logging, the single-instance lock
  from secure-file-utils and alerting, with an optional precondition gate.
- **`docs/utilities/RETRY.md`** with the API reference, the configuration variables and
  usage patterns.
- **Library changes are covered by tests.** `tests/` holds a dependency-free suite in pure
  Bash with no `bats`: `tests/lib/assert.sh` for the helpers, `tests/test-retry.sh` for
  the retry unit tests, `tests/smoke-examples.sh` which runs the examples that need no
  external dependencies, and `tests/run-all.sh` as the runner.

### Changed
- **One CI workflow instead of two.** `.github/workflows/lint.yml` was folded into
  `ci.yml`, which now runs ShellCheck, a Bash syntax check and the test suite, and covers
  `tests/` as well. The CI badge in `README.md` points at `ci.yml`.

## [2.2.0] - 2026-04-20: An unwritable log file no longer aborts the caller

A caller running under `set -euo pipefail` could be aborted by its own logging: when the
log file was missing or not writable, every `simple-logging.sh` function returned 1, and
the shell treated that as a failed command.

### Fixed
- **A log file that cannot be written no longer aborts the calling script.**
  `log_info`, `log_success`, `log_error`, `log_warning` and `log_debug` in
  `src/foundation/simple-logging.sh` return 0 in that case and keep writing the warning to
  stderr. Logging is best effort; the caller decides what is fatal.

## [2.1.0] - 2026-02-27: RFC 5424 level names throughout

The 2.0.0 release introduced NOTICE and called itself RFC 5424 aligned, but kept the
abbreviated level name `WARN` in the constant, the function names and the level string
written into each log line. This release completes that rename.

### Changed
- **Breaking:** **`log_warn()` and `log_warn_structured()` no longer exist.** They were
  renamed to `log_warning()` and `log_warning_structured()` in
  `src/foundation/logging.sh` with no alias left behind, so a call to the old name fails
  with "command not found". The aliases `warn()` and `warning()` were kept and now point
  at `log_warning()`.
- **Breaking:** **The level string in every log line changed from `WARN` to `WARNING`.**
  Any log parser, `grep` pattern or journald filter matching on `WARN` as a whole word
  stops matching. `WARN` is still accepted as an *input* value for `LOG_LEVEL` and in
  `get_log_level_value()`; only the emitted string changed.
- **Breaking:** **The constant `LOG_LEVEL_WARN` was renamed to `LOG_LEVEL_WARNING`.**
  A script comparing against the old constant reads an empty value under `set -u` and
  aborts.
- Version references were updated across the documentation, the examples and `install.sh`
  to match.

### Upgrade notes

Three renames, all mechanical:

```bash
# 1. Call sites
log_warn "..."             ->  log_warning "..."
log_warn_structured "..."  ->  log_warning_structured "..."

# 2. Anything matching on the emitted level string
grep 'WARN'                ->  grep 'WARNING'

# 3. Numeric comparisons against the constant
$LOG_LEVEL_WARN            ->  $LOG_LEVEL_WARNING
```

`LOG_LEVEL=WARN` in the environment keeps working; the input side accepts both spellings.

This section was rewritten in 2.4.4. As published in February 2026 it described only the
documentation updates and did not mention that the three renames above had shipped.

## [2.0.0] - 2026-02-24: Webhook alerts and a six level logger

Alerting moved off Telegram and onto a generic webhook, and the logger gained the NOTICE
level that RFC 5424 defines between INFO and WARNING. Both are breaking, and both are
listed first in their section.

### Changed
- **Breaking:** **Alerts are delivered to a webhook, not to Telegram.**
  `src/monitoring/alerts.sh` no longer reads `TELEGRAM_BOT_TOKEN` or `TELEGRAM_CHAT_ID`.
  The endpoint is `ALERT_WEBHOOK_URL`, which is required; without it `send_alert()` logs
  "ALERT_WEBHOOK_URL not configured" and returns without sending. `ALERT_WEBHOOK_CACERT`
  takes a CA certificate path for a self-signed TLS endpoint and is optional. Mattermost,
  Slack and Discord all accept the payload.
- **Breaking:** **`send_telegram_alert()` was removed.** `send_alert()` is the public API.
  Severity and emoji are derived from the alert type name by `_derive_severity()`, so the
  third argument is gone.
- **Breaking:** **`TELEGRAM_PREFIX` is now `ALERTS_PREFIX`,** default `[System]`.
- **Breaking:** **The numeric log levels shifted by one** to make room for NOTICE:
  `WARN=3`, `ERROR=4`, `CRITICAL=5`, previously 2, 3 and 4. String comparisons are
  unaffected.
- `log_success()` and `success()` in `logging.sh` are deprecated aliases for
  `log_notice()`; they mapped to `log_info()` before.
- `send_recovery_alert()`, and `_sa_send_immediate_alert()`, `_sa_send_pending_alert()`
  and `sa_register_recovery()` in `smart-alerts.sh`, all call `send_alert()` now.
  `sa_register_recovery()` passes the `_RECOVERED` suffix.

### Added
- **A level between INFO and WARN, for events worth noticing but not worth warning
  about.** `LOG_LEVEL_NOTICE=2` in `logging.sh`, with the `log_notice()` wrapper, the
  `notice()` alias, `log_notice_structured()` for the journald fields, and a
  `notice_count` entry in `SCRIPT_METRICS`.
- **Log lines carry the environment they were written in.** `detect_environment()` derives
  prod, dev or test from the hostname and `ENV`, and populates `SCRIPT_ENV` when the
  library is loaded.

### Upgrade notes

**alerts.sh:**

```bash
# Before (v1.x)
export TELEGRAM_BOT_TOKEN="123:abc"
export TELEGRAM_CHAT_ID="-1234"
export TELEGRAM_PREFIX="[MyApp]"
send_telegram_alert "backup_failed" "Disk full" "<emoji>"

# After (v2.0.0)
export ALERT_WEBHOOK_URL="https://mattermost.example/hooks/TOKEN"
export ALERTS_PREFIX="[MyApp]"
send_alert "BACKUP_FAILED" "Disk full"
# emoji and severity are derived from the alert type name
```

**logging.sh**, only if you compare `LOG_LEVEL` numerically:

```bash
# Before: WARN=2, ERROR=3, CRITICAL=4
# After:  WARN=3, ERROR=4, CRITICAL=5
```

## [1.2.2] - 2026-01-21: Documentation in every library directory

Documentation release. Someone landing in `src/` or in one of its subdirectories had no
entry point there and had to go back to the top-level `README.md` to find out what the
libraries do.

### Added
- **Every library directory explains itself.** `src/README.md`,
  `src/foundation/README.md`, `src/monitoring/README.md` and `src/utilities/README.md`
  were added, covering the libraries in their directory with usage examples.
- **`docs/README.md` and `docs/SETUP.md` open with a TL;DR,** and `docs/README.md` and
  `examples/README.md` end with a "See Also" section, so a reader can move between the
  documents without going through the root.
- **`README.md` says how to contribute and where to get help,** through a Contributing and
  a Support section.

### Changed
- **`install.sh` says what it is doing and stops early when a prerequisite is missing.**
  It checks its required commands with `command -v` before touching anything, prints
  colour-coded progress, and carries an SPDX license identifier.

This section was written in 2.4.4 from the tag annotation and the `v1.2.0..v1.2.2` diff.
The release had been published without one.

## [1.2.0] - 2026-01-21: Installer and community files

The repository had the libraries but not the scaffolding an outside contributor expects:
no installer, no contribution guide, no way to report a vulnerability privately.

### Added
- **The toolkit installs into a user's home without root.** `install.sh` sets up the
  libraries for a per-user installation.
- **`CONTRIBUTING.md`** with the development workflow, **`SECURITY.md`** with the
  vulnerability reporting process, and GitHub templates for bug reports, feature requests
  and pull requests, plus an issue config that routes contributors to the right place.

### Changed
- `README.md` went from four badges to seven, adding ShellCheck, Release and Maintained.

## [1.0.0] - 2026-01-20: Nine libraries extracted into a toolkit

Initial release. Nine Bash libraries extracted from a production server repository, with
documentation and a linting pipeline.

### Added
- **Foundation libraries:** `logging.sh`, `simple-logging.sh`, `secure-file-utils.sh` and
  `error-handling.sh` under `src/foundation/`.
- **Monitoring libraries:** `alerts.sh` and `smart-alerts.sh` under `src/monitoring/`.
- **Utility libraries:** `device-detection.sh`, `path-calculator.sh` and
  `backup-safety.sh` under `src/utilities/`.
- Six example scripts under `examples/` and twelve documents under `docs/`.
- A CI pipeline running ShellCheck over the libraries
  (`.github/workflows/lint.yml`).

[Unreleased]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.6...HEAD
[2.4.6]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.5...v2.4.6
[2.4.5]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.4...v2.4.5
[2.4.4]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.3...v2.4.4
[2.4.3]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.2...v2.4.3
[2.4.2]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/fidpa/bash-production-toolkit/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/fidpa/bash-production-toolkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.2.0...v2.0.0
[1.2.2]: https://github.com/fidpa/bash-production-toolkit/compare/v1.2.0...v1.2.2
[1.2.0]: https://github.com/fidpa/bash-production-toolkit/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/fidpa/bash-production-toolkit/releases/tag/v1.0.0
