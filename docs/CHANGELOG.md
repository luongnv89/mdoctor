# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- CI lint script compatibility with Bash 3.2 (removed `mapfile` dependency in `scripts/lint_shell.sh`)
- Test harness portability on macOS runners for temporary directories in cleanup tests
- Bash 3.2 empty-array edge cases:
  - whitelist matching in `lib/safety.sh`
  - full cleanup dispatch in `mdoctor clean`

## [2.1.0] - 2026-02-24

### Added
- Centralized deletion safety primitives with guarded APIs (`safe_remove`, `safe_remove_children`, `safe_find_delete`) and protection checks
- Destructive error taxonomy with actionable hints (`INVALID_TARGET`, `PROTECTED_TARGET`, `SYMLINK_BLOCKED`, `PERMISSION_DENIED`, `SIP_OR_READONLY`, `RUNTIME_FAILURE`)
- Persistent operation logging at `~/.config/mdoctor/operations.log`
- Structured `--debug` diagnostics for `check`, `clean`, and `fix`
- Cleanup whitelist support (`~/.config/mdoctor/cleanup_whitelist`)
- Custom cleanup scope config for stale `node_modules` scanning (`~/.config/mdoctor/cleanup_scope.conf`)
- Shell regression harness (`tests/run.sh`) with coverage for parsing, metadata routing, safety, dry-run semantics, and interactive cleanup
- `mdoctor update` command (stable channel) with check mode (`mdoctor update --check`)
- Interactive cleanup module selection (`mdoctor clean --interactive`)
- Dedicated safety and recovery documentation (`docs/SAFETY.md`)

### Changed
- Cleanup modules migrated to centralized safety primitives
- Force-mode cleanup now provides explicit pre-flight safety summaries
- CI expanded into lint/test/release-sanity lanes with shared local scripts for parity
- Shell lint policy standardized via `.shellcheckrc` and `scripts/lint_shell.sh`
- Installer/uninstaller gained optional env overrides for isolated CI/dev sanity runs

### Fixed
- Removed shared cleanup runner dependence on `eval`-based command execution
- Improved destructive failure reporting consistency across cleanup paths

## [2.0.0] - 2026-02-14

### Added
- 12 new check modules: battery, hardware, bluetooth, usb, security, startup, performance, storage, apps, git_config, containers, shell — total now 21
- 4 new cleanup modules: crash_reports, ios_backups, xcode, dev_caches — total now 10
- 4 new fix targets: bluetooth, audio, wifi, timemachine — total now 9
- `mdoctor list` command with category & risk level display
- `mdoctor history` command with trend detection
- `mdoctor benchmark` command (disk, network, CPU)
- JSON output support (`--json` flag)
- Module registry with metadata (category, risk level)
- Health score history and trend tracking

## [1.1.1] - 2026-02-13

### Fixed
- Use `/System/Volumes/Data` for accurate disk usage on macOS APFS (previously reported only the read-only system snapshot, showing ~11 GB instead of actual usage)

## [1.1.0] - 2026-02-12

### Added
- Animated spinner with progress bar (`[████████░░░░░░░░] 44%`) shown while checks run
- Version string now includes short git commit hash (e.g. `1.1.0+d2d9a90`)
- Version displayed at the start of `mdoctor check` and `mdoctor clean`

### Changed
- `mdoctor version` now outputs full version with commit hash
- Banner in `mdoctor help` shows version with commit hash
- Spinner is automatically hidden when output is piped or redirected
- Status output (ok/warn/fail/info) pauses spinner to prevent garbled lines

## [1.0.0] - 2025-12-01

### Added
- Unified `mdoctor` CLI with subcommands: `check`, `clean`, `fix`, `info`, `version`, `help`
- 9 health check modules: system, disk, updates, homebrew, node, python, devtools, shell, network
- 6 cleanup modules: trash, caches, logs, downloads, browser, dev
- 5 fix targets: homebrew, dns, disk, permissions, spotlight
- One-line installer via `curl | bash`
- Uninstall script
- Dry-run mode for all cleanup operations
- Health scoring system (0-100)
- Markdown report generation
- Module-level execution (`-m` flag)
- Shared library: colors, logging, disk utilities
