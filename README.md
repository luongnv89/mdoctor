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

- **Comprehensive** -- 21 health checks across Hardware, System, and Software categories
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

| Command | Description |
|---------|-------------|
| `mdoctor check` | Run full system health audit (21 checks, read-only) |
| `mdoctor check --json` | JSON output for automation |
| `mdoctor clean` | Run system cleanup (dry-run by default, 10 modules) |
| `mdoctor fix <target>` | Apply common fixes (9 targets) |
| `mdoctor info` | Show system information summary |
| `mdoctor list` | List all modules with category & risk level |
| `mdoctor history` | View health score trends over time |
| `mdoctor benchmark` | Run disk, network, CPU speed tests |
| `mdoctor update` | Update to latest stable release |
| `mdoctor version` | Show version |
| `mdoctor help` | Show help |

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
| **Hardware** | `battery`, `hardware`, `bluetooth`, `usb` | `hardware` |
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
```

Force mode (actually deletes):

```bash
mdoctor clean --force
```

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

#### Cleanup Modules (all `[LOW]` risk)

| Category | macOS | Linux (Debian) |
|----------|-------|----------------|
| **System** | `trash`, `caches`, `logs`, `downloads`, `crash_reports`, `ios_backups` | `trash`, `caches`, `logs`, `downloads`, `crash_reports`, `apt` |
| **Software** | `browser`, `dev`, `xcode`, `dev_caches` | `browser`, `dev`, `dev_caches` |

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
mdoctor fix disk           # [LOW]  Free disk space
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
- Disk write/read speed (256 MB test file)
- DNS resolution latency
- HTTP fetch time
- CPU gzip compression (10 MB)

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

Override cleanup age threshold (default 7 days):

```bash
DAYS_OLD_OVERRIDE=14 mdoctor clean --force
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
├── doctor.sh            # Health audit engine (21 checks)
├── cleanup.sh           # Cleanup engine (10 modules)
├── lib/                 # Shared libraries
│   ├── platform.sh      # OS/distro detection (macOS, Debian, Ubuntu, etc.)
│   ├── common.sh        # Colors, icons, UI helpers, progress spinner
│   ├── logging.sh       # Logging + operation session records
│   ├── disk.sh          # Disk utilities
│   ├── metadata.sh      # Module registry (categories, risk levels)
│   ├── json.sh          # Pure-Bash JSON output support
│   ├── history.sh       # Health score history & trends
│   ├── benchmark.sh     # System benchmark tests
│   ├── safety.sh        # Deletion safety primitives + whitelist policy
│   └── cleanup_scope.sh # Dev cache scope include/exclude config
├── checks/              # Health check modules (21)
│   ├── battery.sh       # Battery health & cycle count
│   ├── hardware.sh      # CPU, RAM, thermals
│   ├── bluetooth.sh     # Bluetooth status
│   ├── usb.sh           # USB device audit
│   ├── system.sh        # OS, memory, load average
│   ├── disk.sh          # Disk usage
│   ├── updates.sh       # System updates (macOS + APT)
│   ├── security.sh      # Firewall, encryption, security settings
│   ├── startup.sh       # Startup services & agents
│   ├── network.sh       # Connectivity, DNS, Wi-Fi signal
│   ├── performance.sh   # Memory pressure, CPU, processes
│   ├── storage.sh       # Large files & storage analysis
│   ├── homebrew.sh      # Homebrew checks
│   ├── node.sh          # Node.js & npm
│   ├── python.sh        # Python & pip
│   ├── devtools.sh      # Developer tools, Git, Docker
│   ├── shell.sh         # Shell config syntax
│   ├── apps.sh          # Crash reports, app health
│   ├── git_config.sh    # Git & SSH config
│   ├── containers.sh    # Docker & containers
│   └── apt.sh           # APT package manager health (Linux)
├── cleanups/            # Cleanup modules (10)
│   ├── trash.sh         # Trash cleanup
│   ├── caches.sh        # User caches
│   ├── logs.sh          # Old logs
│   ├── downloads.sh     # Large files in Downloads
│   ├── browser.sh       # Browser caches
│   ├── dev.sh           # Developer tool caches
│   ├── crash_reports.sh # Old crash/diagnostic reports
│   ├── ios_backups.sh   # Old iOS device backups
│   ├── xcode.sh         # Xcode DerivedData, archives, simulators
│   ├── dev_caches.sh    # Developer dependency & package caches
│   └── apt.sh           # APT package cache cleanup (Linux)
├── fixes/               # Fix modules (9)
│   ├── homebrew.sh      # Homebrew update & repair
│   ├── dns.sh           # Flush DNS cache
│   ├── disk.sh          # Free disk space
│   ├── permissions.sh   # Reset permissions
│   ├── spotlight.sh     # Rebuild Spotlight index
│   ├── bluetooth.sh     # Reset Bluetooth
│   ├── audio.sh         # Restart Core Audio
│   ├── wifi.sh          # Fix Wi-Fi connection
│   ├── timemachine.sh   # Time Machine repair (macOS)
│   └── apt.sh           # Fix APT packages (Linux)
├── scripts/
│   └── lint_shell.sh    # Shared ShellCheck policy entrypoint (local + CI)
├── tests/
│   ├── run.sh
│   ├── helpers/assert.sh
│   └── test_*.sh        # Regression coverage for parsing/safety/cleanup behavior
├── openspec/            # Task-scoped change artifacts and archived specs
└── docs/                # Documentation
    ├── GUIDEBOOK.md
    ├── ARCHITECTURE.md
    ├── DEVELOPMENT.md
    ├── DEPLOYMENT.md
    ├── SAFETY.md
    ├── LINUX_DEBIAN_PLAN.md
    └── CHANGELOG.md
```

## Documentation

- [Guidebook](docs/GUIDEBOOK.md) -- Quick problem → command lookup
- [Architecture](docs/ARCHITECTURE.md) -- System design and component overview
- [Development](docs/DEVELOPMENT.md) -- Local setup and debugging guide
- [Deployment](docs/DEPLOYMENT.md) -- Distribution and release process
- [Safety & Recovery](docs/SAFETY.md) -- Cleanup safety model, recovery playbook, known limitations
- [Linux Debian Plan](docs/LINUX_DEBIAN_PLAN.md) -- phased roadmap for Debian-based Linux support
- [Changelog](docs/CHANGELOG.md) -- Version history
- [Contributing](CONTRIBUTING.md) -- How to contribute
- [Security](SECURITY.md) -- Vulnerability reporting

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
