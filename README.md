<p align="center">
  <img src="assets/logo/logo-full.svg" alt="mdoctor" width="400">
</p>

<p align="center">
  <strong>Keep your Mac healthy.</strong><br>
  A unified CLI to diagnose, clean, and fix your macOS system. Pure Bash, zero dependencies.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="macOS"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Bash"></a>
</p>

## Why mdoctor?

- **One command** to audit your entire Mac: OS, disk, memory, Homebrew, Node, Python, Docker, shell configs, network
- **Safe by default** -- health checks are read-only, cleanup runs in dry-run mode
- **Modular** -- run everything or target a single module
- **Actionable** -- provides a health score and specific next steps to fix issues
- **Zero dependencies** -- pure Bash, uses only standard macOS tools

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/luongnv89/mdoctor.git ~/.mdoctor
cd ~/.mdoctor && ./install.sh
```

## Usage

```bash
mdoctor <command> [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `mdoctor check` | Run full system health audit (read-only) |
| `mdoctor clean` | Run system cleanup (dry-run by default) |
| `mdoctor fix <target>` | Apply common fixes |
| `mdoctor info` | Show system information summary |
| `mdoctor version` | Show version |
| `mdoctor help` | Show help |

### Health Check

Run a full system audit (read-only, changes nothing):

```bash
mdoctor check
```

Check a specific module only:

```bash
mdoctor check -m homebrew
mdoctor check -m disk
mdoctor check -m network
```

Available check modules: `system`, `disk`, `updates`, `homebrew`, `node`, `python`, `devtools`, `shell`, `network`

The health check:
- Scores your system 0-100
- Reports warnings and failures
- Generates a markdown report in `/tmp/`
- Provides actionable next steps

### Cleanup

Dry-run mode (shows what would be deleted, nothing removed):

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
mdoctor clean -m caches --force
```

Available cleanup modules: `trash`, `caches`, `logs`, `downloads`, `browser`, `dev`

### Fix

Apply common fixes for macOS issues:

```bash
mdoctor fix homebrew    # Update & fix Homebrew
mdoctor fix dns         # Flush DNS cache
mdoctor fix disk        # Free disk space
mdoctor fix permissions # Reset file permissions
mdoctor fix spotlight   # Rebuild Spotlight index
mdoctor fix all         # Run all fixes
```

### System Info

Quick system overview:

```bash
mdoctor info
```

Shows: OS version, architecture, memory, disk, CPU, uptime, and installed dev tools.

## Configuration

Override cleanup age threshold (default 7 days):

```bash
DAYS_OLD_OVERRIDE=14 mdoctor clean --force
```

## Project Structure

```
mdoctor/
├── mdoctor              # Unified CLI entry point
├── install.sh           # One-line installer
├── uninstall.sh         # Uninstaller
├── doctor.sh            # Health audit engine
├── cleanup.sh           # Cleanup engine
├── lib/                 # Shared libraries
│   ├── common.sh        # Colors, icons, UI helpers
│   ├── logging.sh       # Logging and markdown reports
│   └── disk.sh          # Disk utilities
├── checks/              # Health check modules
│   ├── system.sh        # System & OS checks
│   ├── disk.sh          # Disk health checks
│   ├── updates.sh       # Update status checks
│   ├── homebrew.sh      # Homebrew checks
│   ├── node.sh          # Node.js & npm checks
│   ├── python.sh        # Python & pip checks
│   ├── devtools.sh      # Xcode, Git, Docker checks
│   ├── shell.sh         # Shell config checks
│   └── network.sh       # Network connectivity checks
├── cleanups/            # Cleanup modules
│   ├── trash.sh         # Trash cleanup
│   ├── caches.sh        # User caches cleanup
│   ├── logs.sh          # Old logs cleanup
│   ├── downloads.sh     # Large files in Downloads
│   ├── browser.sh       # Browser caches
│   └── dev.sh           # Developer tools cleanup
└── docs/                # Documentation
    ├── ARCHITECTURE.md   # System design
    ├── DEVELOPMENT.md    # Dev setup guide
    ├── DEPLOYMENT.md     # Distribution & releases
    └── CHANGELOG.md      # Version history
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) -- System design and component overview
- [Development](docs/DEVELOPMENT.md) -- Local setup and debugging guide
- [Deployment](docs/DEPLOYMENT.md) -- Distribution and release process
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
