# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
