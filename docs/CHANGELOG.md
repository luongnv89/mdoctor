# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [3.2.1] - 2026-09-18

### Fixed
- `install.sh` never `rm -rf`s the install dir — a state-only `~/.mdoctor` (e.g., only `history/` from plain `mdoctor check`) is adopted in place instead of deadlocking `install.sh`/`uninstall.sh`; failed fast-forwards reseed in place and the move-aside fallback carries `history/` forward; foreign content is still refused with recovery instructions (#249, closes #250)

## [3.2.0] - 2026-09-18

### Added
- Arch-family Linux support (Omarchy, Arch, EndeavourOS, Manjaro, CachyOS): new `pacman` check/cleanup/fix modules (`checks/pacman.sh`, `cleanups/pacman.sh`, `fixes/pacman.sh`), `is_arch`/`is_omarchy` predicates in `lib/platform.sh` (with `MDOCTOR_DISTRO_LIKE` from `ID_LIKE`), installer and agent-skill support, and Arch-specific install/upgrade advice in the devtools and git_config checks (#247)
- Apple-style landing page (`site/index.html`) deployed via GitHub Pages — PAS-framework copy, light/dark Apple design tokens, copy buttons on the install command and terminal output (#245)

### Changed
- README fix-target docs now state commands print with a `[DRY RUN]` prefix and are never executed, and that `timemachine` is macOS-only (#243)

## [3.1.0] - 2026-09-16

### Added
- `mdoctor diagnose` — read-only, cross-platform performance diagnosis for CPU, memory, disk I/O, swap, zombie processes and connection pressure, with prioritized remedies and timeout-capped shared probes (#13)
- An install-and-operate `mdoctor-agent` skill with dependency checks, local/remote install modes, verification and safe-use guidance (#8)
- A centralized module registry, named threshold constants, explicit module context initialization and shared disk, preflight, help, timeout and performance-probe libraries (#184, #185, #186, #187, #190, #191, #198, #199)
- Signed release-tag verification for install and update flows, plus a tag-triggered GitHub Release workflow with version-agreement checks (#156, #164)
- Secret scanning in pre-commit and CI, Dependabot configuration and a kcov coverage lane (#133, #154, #165)

### Changed
- Cleanup and check dispatch now derive from the platform-filtered registry; the legacy `dev` cleanup was retired in favor of `dev_caches`, and command help reflects only modules available on the current platform (#184, #195, #200, #213)
- `mdoctor clean` now accepts an explicit `--dry-run`, names the selected cleanup mode and always ends with a run summary; command badges, bare invocation guidance and installer risk labels are clearer (#209, #215, #216)
- The regression suite migrated to bats-core and gained broad behavioral coverage for CLI parsing, checks, cleanups, fixes, installers, safety, JSON, cross-platform behavior and Bash 3.2 compatibility (#167–#179, #197, #234)
- Contributor, safety, deployment, development, guidebook, README and agent-facing documentation now reflect the current two-platform behavior, release gates, module inventories and configuration rules (#121, #224–#232, #236)
- CI now uses pinned actions and runner images, aligned ShellCheck gates, hardened permissions/timeouts/concurrency, hermetic release checks and sharded macOS test legs (#132, #138–#148, #238)

### Fixed
- `mdoctor clean` no longer aborts when cleanup scope configuration has no active `EXCLUDE_GLOB`; unavailable Docker daemons no longer stop later development-cache cleanup (#15)
- Deletion safety now fails closed for invalid `HOME` values and unknown roots, validates install directories, rejects unsafe symlinks by default, canonicalizes targets and requires confirmation before destructive execution (#124–#129, #150, #151)
- Check-module names are allowlisted before sourcing, string-evaluated command paths were removed, fix modules consistently honor dry-run, and platform-incompatible fixes are gated (#131, #152, #161, #162)
- Linux and Bash 3.2 behavior is more reliable, including host-command guards, correct ping timeout units, empty-array handling, Arch compatibility, platform-specific advice and valid JSON output (#7, #142, #146, #180, #181, #218)
- JSON status helpers now record checks correctly and fully escape output; numeric probes reject malformed readings and report collection failures instead of presenting misleading values (#180, #219)
- Cleanup now honors per-module staleness thresholds, safely handles size-probe failures, scans stale `node_modules` with NUL delimiters, skips caches for running browsers, reports downloads honestly and de-duplicates physical scope roots (#155, #194, #196, #221, #237)
- Benchmarking now measures real disk targets over HTTPS and refuses temporary filesystems (#212)
- History validation, state-file modes, ordered exit hooks and decimal normalization prevent malformed state, hangs and leading-zero arithmetic errors (#153, #163, #223, #242)
- CLI parsing now guards missing module arguments and rejects unknown global flags cleanly (#214, #240)
- Color initialization now honors `NO_COLOR` and terminal detection (#217)
- `fix all --dry-run` now succeeds on hosts where optional platform tools are unavailable (#235)

### Performance
- Network and daemon probes are time-capped, independent checks run in parallel, and slow command output is captured only once (#208, #210)
- Check parsing and logging use fewer subprocesses, while the spinner uses one worker per run (#205, #207, #211)
- Storage scans and force-cleanup size estimation collapse repeated traversals into shared passes with per-process caching (#201–#203)

### Security
- Installer overrides are validated without clobbering existing installs, temporary files use `mktemp`, and release/update flows verify signed tags (#157, #158, #156)
- CI dependencies are pinned and automatically maintained; workflow permissions and destructive test paths are hardened (#122, #132, #133, #143)

### Dependencies
- Updated `actions/upload-artifact` from 4.6.2 to 7.0.1 and `pre-commit-hooks` from 5.0.0 to 6.0.0 (#222, #135)

## [3.0.0] - 2026-05-05

### Added
- Linux (Debian/Ubuntu) cross-platform support:
  - Platform detection layer (`lib/platform.sh`) with OS/distro predicates and platform-aware paths
  - Linux-specific modules: `checks/apt.sh`, `cleanups/apt.sh`, `fixes/apt.sh`
  - Platform-conditional module loading throughout `doctor.sh`, `cleanup.sh`, and `mdoctor`
  - Installer support for Debian-family distros (Ubuntu, Pop!_OS, Mint, Raspbian, etc.)
- End-to-end safe mode test (`tests/test_e2e_safe_mode.sh`) — 25+ assertions across all CLI commands
- CI: Linux/Ubuntu test job, Bash 3.2 compatibility job, timeout guards
- Cross-platform test suite (trash path, module assertions adapt to platform)

### Changed
- Rebranded from "System Doctor" to **"Machine Doctor"** to reflect cross-platform scope
- `clean` preflight no longer exits silently when `du` fails (#9, #11)

### Fixed
- CI lint script compatibility with Bash 3.2 (removed `mapfile` dependency in `scripts/lint_shell.sh`)
- Test harness portability on macOS runners for temporary directories in cleanup tests
- Bash 3.2 empty-array edge cases:
  - whitelist matching in `lib/safety.sh`
  - full cleanup dispatch in `mdoctor clean`
- Pre-commit shellcheck severity aligned to match `lint_shell.sh` policy
- Executable permissions on 7 files with shebangs

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
- 11 new check modules: battery, hardware, bluetooth, usb, security, startup, performance, storage, apps, git_config, containers — total now 20
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
