<p align="center">
  <img src="assets/logo/logo-full.svg" alt="mdoctor" width="400">
</p>

<p align="center">
  <strong>Machine Doctor -- Keep your system healthy.</strong><br>
  A comprehensive CLI to diagnose, clean, fix, and benchmark your macOS and Linux system. Pure Bash, zero dependencies.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS-brightgreen.svg" alt="macOS"></a>
  <a href="https://ubuntu.com/"><img src="https://img.shields.io/badge/platform-Linux%20(Debian%2FUbuntu)-brightgreen.svg" alt="Linux"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Bash"></a>
</p>

## Why mdoctor?

- **Comprehensive** -- health checks across Hardware, System, and Software categories (20 on macOS / 18 on Linux; `mdoctor list` shows the live set)
- **Safe by default** -- health checks are read-only, cleanup runs in dry-run mode
- **Risk-rated** -- every operation is classified `[SAFE]` `[LOW]` `[MED]` `[HIGH]`
- **Modular** -- run everything or target a single module
- **Actionable** -- provides a health score and specific next steps to fix issues
- **Trackable** -- JSON output, historical scores with trend detection
- **Cross-platform** -- macOS and Debian-based Linux (Ubuntu, Pop!_OS, Mint, etc.)
- **Zero dependencies** -- pure Bash, uses only standard system tools

## Quick Install

Works on macOS and Debian-based Linux (Ubuntu, Pop!_OS, Mint, Raspbian, etc.):

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/luongnv89/mdoctor.git ~/.mdoctor
cd ~/.mdoctor && ./install.sh
```

> **Linux prerequisite:** `git` must be installed (`sudo apt install git`).

## Usage

```bash
mdoctor <command> [options]
```

### Commands

Every command carries a safety badge from the same risk vocabulary as the
module registry: `[SAFE]` read-only, `[LOW]`/`[MED]` modifies,
`[HIGH]` deletes. Bare `mdoctor` prints the badged table plus a
recommended first command.

| Command | Badge | Description |
|---------|-------|-------------|
| `mdoctor check` | `[SAFE]` | Run full system health audit (20 checks on macOS / 18 on Linux, read-only) |
| `mdoctor check --json` | `[SAFE]` | JSON output for automation |
| `mdoctor clean` | `[HIGH]` | Run system cleanup (dry-run by default, 10 on macOS / 9 on Linux) |
| `mdoctor fix <target>` | `[MED]` | Apply common fixes (9 on macOS / 2 on Linux) |
| `mdoctor diagnose` | `[SAFE]` | Run active performance diagnosis (read-only — prints remedies, never runs them) |
| `mdoctor info` | `[SAFE]` | Show system information summary |
| `mdoctor list` | `[SAFE]` | List all modules with category & risk level |
| `mdoctor history` | `[SAFE]` | View health score trends over time |
| `mdoctor benchmark` | `[LOW]` | Run disk, network, CPU speed tests |
| `mdoctor update` | `[MED]` | Update to latest stable release |
| `mdoctor version` | `[SAFE]` | Show version |
| `mdoctor help` | `[SAFE]` | Show help |

### Health Check

Run a full system audit (read-only, changes nothing):

```bash
mdoctor check
```

Check a specific module only:

```bash
mdoctor check -m battery
mdoctor check -m security
mdoctor check -m performance
```

Output as JSON for automation:

```bash
mdoctor check --json | python3 -m json.tool
```

#### Check Modules (all `[SAFE]` — read-only)

| Category | macOS | Linux (Debian) |
|----------|-------|----------------|
| **Hardware** | `battery`, `hardware`, `bluetooth`, `usb` | `battery`, `hardware` |
| **System** | `system`, `disk`, `updates`, `security`, `startup`, `network`, `performance`, `storage` | `system`, `disk`, `updates`, `security`, `startup`, `network`, `performance`, `storage` |
| **Software** | `homebrew`, `node`, `python`, `devtools`, `shell`, `apps`, `git_config`, `containers` | `node`, `python`, `devtools`, `shell`, `apps`, `git_config`, `containers`, `apt` |

The health check:
- Scores your system 0-100
- Reports warnings and failures
- Generates a markdown report in `/tmp/`
- Saves score history for trend tracking
- Provides actionable next steps

### Cleanup

Dry-run mode (shows what would be deleted, nothing removed):

> Safety model and recovery guidance: see [`docs/SAFETY.md`](docs/SAFETY.md).

```bash
mdoctor clean
mdoctor clean --dry-run   # explicit form of the default (same as no flag)
```

Force mode (actually deletes):

```bash
mdoctor clean --force
```

Force mode prints a pre-flight summary of touched targets, then asks
`Proceed with deletion? [y/N]` — only an explicit `y` proceeds. For
non-interactive runs, `MDOCTOR_ASSUME_YES=true` skips the prompt; with
it set there is no confirmation and `--force` deletes immediately after
the summary. Piping from a non-tty without that variable refuses
outright. The summary itself is informational, not an approval step.

A full `mdoctor clean` does not run every registered module — it runs a
fixed step list of 7 on macOS / 6 on Linux. The opted-out modules —
`downloads` (report-only: lists large files, never deletes), `browser`
and `dev` — run via `mdoctor clean -m <name>` or
`mdoctor clean --interactive`.

Clean a specific target only:

```bash
mdoctor clean -m trash
mdoctor clean -m crash_reports --force
mdoctor clean -m xcode
```

Interactive cleanup selection:

```bash
mdoctor clean --interactive
mdoctor clean --interactive --force
```

#### Cleanup Modules (risk-rated by blast radius)

| Category | macOS | Linux (Debian) |
|----------|-------|----------------|
| **System** | `trash` [MED], `caches` [LOW], `logs` [MED], `downloads` [SAFE] (report-only), `crash_reports` [MED], `ios_backups` [HIGH] | `trash` [MED], `caches` [LOW], `logs` [MED], `downloads` [SAFE] (report-only), `crash_reports` [MED], `apt` [MED] |
| **Software** | `browser` [LOW], `dev` [MED], `xcode` [MED], `dev_caches` [MED] | `browser` [LOW], `dev` [MED], `dev_caches` [MED] |

### Fix

Apply common fixes for system issues:

**macOS:**

```bash
mdoctor fix homebrew       # [LOW]  Update & fix Homebrew
mdoctor fix dns            # [LOW]  Flush DNS cache
mdoctor fix disk           # [LOW]  Free disk space
mdoctor fix bluetooth      # [LOW]  Reset Bluetooth module
mdoctor fix audio          # [LOW]  Restart Core Audio
mdoctor fix wifi           # [LOW]  Renew DHCP, flush DNS, cycle Wi-Fi
mdoctor fix permissions    # [MED]  Reset file permissions
mdoctor fix spotlight      # [MED]  Rebuild Spotlight index
mdoctor fix timemachine    # [MED]  Verify Time Machine backup
mdoctor fix all            # Run all fixes
```

**Linux (Debian):**

```bash
mdoctor fix dns            # [LOW]  Flush DNS cache (systemd-resolved)
mdoctor fix apt            # [LOW]  Fix APT packages (update, upgrade, autoremove)
mdoctor fix all            # Run all fixes
```

### History & Trends

View health score history with trend arrows:

```bash
mdoctor history
```

Shows recent scores, detects regressions ("Score dropped from 92 to 64 since last run").

### Benchmark

Run disk I/O, network, and CPU benchmarks:

```bash
mdoctor benchmark
```

Tests include:
- Disk write/read speed (256 MB test file staged in the per-user cache
  dir — never `/tmp`, which is tmpfs/RAM on most Linux installs; the run
  is skipped rather than misreported when the target filesystem is
  RAM-backed or `dd` cannot flush to media, the write flushes via
  `conv=fdatasync`, and the read pass uses `iflag=direct` — or is
  skipped when no page-cache bypass is available)
- DNS resolution latency
- HTTPS fetch time
- CPU gzip compression (10 MB)

Both network probes use one configurable host — `MDOCTOR_BENCH_HOST`
(default `example.com`, fetched over HTTPS only). `MDOCTOR_BENCH_DIR`
overrides where the disk test file is staged (must be an existing
writable directory outside the protected system paths).

### System Info

Quick system overview:

```bash
mdoctor info
```

Shows: OS version, architecture, memory, disk, CPU, uptime, and installed dev tools.

### Module List

Show all available modules with categories and risk levels:

```bash
mdoctor list
```

### Update

Check whether a stable update is available:

```bash
mdoctor update --check
```

Apply the latest stable update:

```bash
mdoctor update
```

## Risk Levels

| Level | Badge | Meaning | Examples |
|-------|-------|---------|---------|
| **Safe** | `[SAFE]` | Read-only, no system modifications | All check modules |
| **Low** | `[LOW]` | Easily reversible, minimal impact | Clearing caches, flushing DNS |
| **Medium** | `[MED]` | May require manual reversal | Resetting permissions, rebuilding indexes |
| **High** | `[HIGH]` | Destructive or hard to reverse | Deleting backups, resetting SMC |

## Configuration

Override cleanup age thresholds (per-module defaults: 7 for logs/downloads, 30 for crash_reports/xcode, 90 for ios_backups):

```bash
DAYS_OLD_OVERRIDE=14 mdoctor clean --force
DAYS_OLD_NODE_MODULES=60 mdoctor clean --force   # stale node_modules in dev_caches
```

Cleanup whitelist path override:

```bash
MDOCTOR_CLEANUP_WHITELIST_FILE="$HOME/.config/mdoctor/cleanup_whitelist" mdoctor clean
```

Cleanup scope path override (dev_caches stale `node_modules` scan):

```bash
MDOCTOR_CLEANUP_SCOPE_FILE="$HOME/.config/mdoctor/cleanup_scope.conf" mdoctor clean -m dev_caches
```

Update remote/branch override (advanced use):

```bash
MDOCTOR_UPDATE_REMOTE=origin MDOCTOR_UPDATE_BRANCH=main mdoctor update --check
```

## Project Structure

```
mdoctor/
├── mdoctor              # Unified CLI entry point
├── install.sh           # One-line installer
├── uninstall.sh         # Uninstaller
├── doctor.sh            # Health check engine (20 on macOS / 18 on Linux)
├── cleanup.sh           # Cleanup engine (10 on macOS / 9 on Linux)
├── lib/                 # Shared libraries (18 files)
│   ├── platform.sh      # OS/distro detection (macOS, Debian, Ubuntu, etc.)
│   ├── constants.sh     # Named thresholds/timeouts + truthy predicate
│   ├── context.sh       # Module context contract (shared globals)
│   ├── common.sh        # Colors, icons, UI helpers, progress spinner
│   ├── logging.sh       # Logging + operation session records
│   ├── disk.sh          # Disk utilities
│   ├── metadata.sh      # Module registry primitives (categories, risk levels)
│   ├── registry.sh      # Module declarations (single source of truth)
│   ├── json.sh          # Pure-Bash JSON output support
│   ├── history.sh       # Health score history & trends
│   ├── benchmark.sh     # System benchmark tests
│   ├── perf_probes.sh   # Timeout-capped performance samplers
│   ├── preflight.sh     # Pre-flight size estimators
│   ├── timeout.sh       # Portable command time-capping
│   ├── help.sh          # usage_* renderers + shared flag parser
│   ├── safety.sh        # Deletion safety primitives + whitelist policy
│   ├── cleanup_scope.sh # Dev cache scope include/exclude config
│   └── clean_common.sh  # Single-module + interactive cleanup helpers
├── checks/              # Health check modules (22 files)
│   ├── battery.sh       # Battery health & cycle count
│   ├── hardware.sh      # CPU, RAM, thermals
│   ├── bluetooth.sh     # Bluetooth status (macOS)
│   ├── usb.sh           # USB device audit (macOS)
│   ├── system.sh        # OS, memory, load average
│   ├── disk.sh          # Disk usage
│   ├── updates.sh       # System updates (macOS + APT)
│   ├── security.sh      # Firewall, encryption, security settings
│   ├── startup.sh       # Startup services & agents
│   ├── network.sh       # Connectivity, DNS, Wi-Fi signal
│   ├── performance.sh   # Memory pressure, CPU, processes
│   ├── storage.sh       # Large files & storage analysis
│   ├── diagnose_performance.sh # Active performance diagnosis
│   ├── homebrew.sh      # Homebrew checks (macOS)
│   ├── node.sh          # Node.js & npm
│   ├── python.sh        # Python & pip
│   ├── devtools.sh      # Developer tools, Git, Docker
│   ├── shell.sh         # Shell config syntax
│   ├── apps.sh          # Crash reports, app health
│   ├── git_config.sh    # Git & SSH config
│   ├── containers.sh    # Docker & containers
│   └── apt.sh           # APT package manager health (Linux)
├── cleanups/            # Cleanup modules (11 files)
│   ├── trash.sh         # Trash cleanup
│   ├── caches.sh        # User caches
│   ├── logs.sh          # Old logs
│   ├── downloads.sh     # Large files in Downloads (report-only)
│   ├── browser.sh       # Browser caches (opt-in via -m)
│   ├── dev.sh           # Developer tool caches (opt-in via -m)
│   ├── crash_reports.sh # Old crash/diagnostic reports
│   ├── ios_backups.sh   # Old iOS device backups (macOS)
│   ├── xcode.sh         # Xcode DerivedData, archives, simulators (macOS)
│   ├── dev_caches.sh    # Developer dependency & package caches
│   └── apt.sh           # APT package cache cleanup (Linux)
├── fixes/               # Fix modules (10 files)
│   ├── homebrew.sh      # Homebrew update & repair (macOS)
│   ├── dns.sh           # Flush DNS cache
│   ├── disk.sh          # Free disk space (macOS)
│   ├── permissions.sh   # Reset permissions (macOS)
│   ├── spotlight.sh     # Rebuild Spotlight index (macOS)
│   ├── bluetooth.sh     # Reset Bluetooth (macOS)
│   ├── audio.sh         # Restart Core Audio (macOS)
│   ├── wifi.sh          # Fix Wi-Fi connection (macOS)
│   ├── timemachine.sh   # Time Machine repair (macOS)
│   └── apt.sh           # Fix APT packages (Linux)
├── scripts/             # Repo scripts (3 files)
│   ├── lint_shell.sh    # Shared ShellCheck policy entrypoint (local + CI)
│   ├── check_bash32.sh  # Bash 3.2 banned-construct scanner
│   └── check_version.sh # Version consistency check
├── tests/
│   ├── run.sh            # bats-core delegation, filter, JUnit, watchdog
│   ├── helpers/          # assert.bash, fixture.bash, fixes_lane.bash, PATH stubs (bin/, bin-macos/)
│   └── test_*.bats       # Regression coverage for parsing/safety/cleanup behavior
├── openspec/            # Task-scoped change artifacts and archived specs
└── docs/                # Documentation (8 files)
    ├── GUIDEBOOK.md
    ├── ARCHITECTURE.md
    ├── DEVELOPMENT.md
    ├── AGENT_ENVIRONMENT.md
    ├── DEPLOYMENT.md
    ├── SAFETY.md
    ├── LINUX_DEBIAN_PLAN.md
    └── CHANGELOG.md
```

## Documentation

All project documents — `docs/` holds the guides, the repo root holds the
project documents:

- [Guidebook](docs/GUIDEBOOK.md) -- Quick problem → command lookup
- [Architecture](docs/ARCHITECTURE.md) -- System design and component overview
- [Development](docs/DEVELOPMENT.md) -- Local setup and debugging guide
- [Agent Environment](docs/AGENT_ENVIRONMENT.md) -- Agent runbook: environment quirks, Bash 3.2 floor
- [Deployment](docs/DEPLOYMENT.md) -- Distribution and release process
- [Safety & Recovery](docs/SAFETY.md) -- Cleanup safety model, recovery playbook, known limitations
- [Linux Debian Plan](docs/LINUX_DEBIAN_PLAN.md) -- phased roadmap for Debian-based Linux support
- [Changelog](docs/CHANGELOG.md) -- Version history
- [Contributing](CONTRIBUTING.md) -- How to contribute
- [Security](SECURITY.md) -- Vulnerability reporting
- [Code of Conduct](CODE_OF_CONDUCT.md) -- Community standards
- [Release Notes](RELEASE_NOTES.md) -- Release-by-release highlights
- [Agents](AGENTS.md) -- Agent-facing project rules and conventions
- [Claude](CLAUDE.md) -- Claude-specific commands (includes AGENTS.md)
- [Code Review](CODE_REVIEW.md) -- Latest code-review artifact
- [Modernization Plan](MODERNIZATION_PLAN.md) -- Tasked improvement plan
- [Modernization Report](MODERNIZATION_REPORT.md) -- Plan execution report
- [README](README.md) -- This file

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Adding new health check modules
- Adding new cleanup modules
- Commit conventions and PR process

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/uninstall.sh | bash
```

Or manually:

```bash
rm -f /usr/local/bin/mdoctor
rm -rf ~/.mdoctor
```

## License

[MIT](LICENSE) -- Use freely.
