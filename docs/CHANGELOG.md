# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
