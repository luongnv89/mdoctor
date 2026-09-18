# mdoctor Guidebook

Quick problem-to-command reference for **macOS**, **Debian-based Linux** and **Arch-based Linux (including Omarchy)**. Find your symptom, run the command.

**Platform labels.** Every row below is marked **Both**, **macOS only** or **Linux only** — the platform that problem or module applies to. Distro-scoped Linux examples use the longer **Debian Linux only** / **Arch Linux only** labels and run only on that family. A command that needs a module registered only on one platform is rejected on the other — `mdoctor list` always shows the exact module set for the machine you are on.

---

## Quick Start

```bash
mdoctor check                # Full health audit (safe, read-only)
mdoctor clean                # Preview what can be cleaned (dry-run)
mdoctor clean --force        # Actually free disk space
```

---

## Problem → Command

### Disk & Storage

| Problem | Command | Platform |
|---------|---------|----------|
| Disk is almost full | `mdoctor check -m disk` | Both |
| Find what's eating space | `mdoctor check -m storage` | Both |
| Clear user caches | `mdoctor clean -m caches --force` | Both |
| Empty the Trash | `mdoctor clean -m trash --force` | Both |
| List large old files in Downloads (report only, never deletes) | `mdoctor clean -m downloads` | Both |
| Delete old crash/diagnostic reports | `mdoctor clean -m crash_reports --force` | Both |
| Clear browser caches | `mdoctor clean -m browser --force` | Both |
| Purge old log files | `mdoctor clean -m logs --force` | Both |
| Clean dev dependency/tool caches (npm, pip, Yarn, Gradle, Homebrew, Docker) | `mdoctor clean -m dev_caches --force` | Both |
| Clean the APT package cache | `mdoctor clean -m apt --force` | Linux only |
| Clean the pacman package cache | `mdoctor clean -m pacman --force` | Linux only |
| Clean Xcode bloat (DerivedData, archives, simulators) | `mdoctor clean -m xcode --force` | macOS only |
| Free disk space (combined fix) | `mdoctor fix disk` | macOS only |

### Performance

| Problem | Command | Platform |
|---------|---------|----------|
| General system info (OS, memory, load) | `mdoctor check -m system` | Both |
| Machine feels slow | `mdoctor diagnose` | Both |
| High CPU usage | `mdoctor check -m performance` | Both |
| High memory pressure | `mdoctor check -m performance` | Both |
| Thermal throttling / fans loud | `mdoctor check -m hardware` | Both |
| Too many startup items slowing boot | `mdoctor check -m startup` | Both |
| Spotlight using too much CPU | `mdoctor fix spotlight` | macOS only |

### Network & Connectivity

| Problem | Command | Platform |
|---------|---------|----------|
| No internet connection | `mdoctor check -m network` | Both |
| Slow or broken DNS | `mdoctor fix dns` | Both |
| Weak Wi-Fi signal | `mdoctor check -m network` | Both |
| Wi-Fi keeps dropping | `mdoctor fix wifi` | macOS only |
| Bluetooth not working | `mdoctor check -m bluetooth` | macOS only |
| Bluetooth device won't connect | `mdoctor fix bluetooth` | macOS only |

### Audio & Peripherals

| Problem | Command | Platform |
|---------|---------|----------|
| No sound / wrong audio output | `mdoctor fix audio` | macOS only |
| USB device not recognized | `mdoctor check -m usb` | macOS only |
| Bluetooth audio issues | `mdoctor fix bluetooth` | macOS only |

### Security & Privacy

| Problem | Command | Platform |
|---------|---------|----------|
| Is my firewall on? | `mdoctor check -m security` | Both |
| Disk encryption status (FileVault / LUKS) | `mdoctor check -m security` | Both |
| SSH / remote-login exposure | `mdoctor check -m security` | Both |
| Is SIP (System Integrity Protection) on? | `mdoctor check -m security` | macOS only |
| Gatekeeper status | `mdoctor check -m security` | macOS only |
| File permission issues | `mdoctor fix permissions` | macOS only |

### Software & Dev Tools

| Problem | Command | Platform |
|---------|---------|----------|
| Node.js / npm issues | `mdoctor check -m node` | Both |
| Python / pip issues | `mdoctor check -m python` | Both |
| Docker not running or unhealthy | `mdoctor check -m containers` | Both |
| Git or SSH config problems | `mdoctor check -m git_config` | Both |
| Developer tools missing or outdated | `mdoctor check -m devtools` | Both |
| Shell config syntax errors | `mdoctor check -m shell` | Both |
| APT package problems | `mdoctor check -m apt` | Linux only |
| Fix broken APT packages (update, upgrade, autoremove) | `mdoctor fix apt` | Linux only |
| pacman package problems | `mdoctor check -m pacman` | Linux only |
| Fix pacman packages (keyring refresh, full upgrade) | `mdoctor fix pacman` | Linux only |
| Homebrew errors or outdated | `mdoctor check -m homebrew` | macOS only |
| Update and fix Homebrew | `mdoctor fix homebrew` | macOS only |

### Startup & Apps

| Problem | Command | Platform |
|---------|---------|----------|
| Slow boot / too many startup items | `mdoctor check -m startup` | Both |
| App keeps crashing | `mdoctor check -m apps` | Both |
| System updates pending | `mdoctor check -m updates` | Both |

### Backup (macOS only)

| Problem | Command | Platform |
|---------|---------|----------|
| Time Machine problems | `mdoctor fix timemachine` | macOS only |
| Old iOS backups wasting space | `mdoctor clean -m ios_backups --force` | macOS only |

---

## Cleanup Cheat Sheet

Cleanup modules are risk-rated (`[SAFE]` modules only report — they never delete). Dry-run by default — add `--force` to actually delete.

The registered cleanup set is platform-filtered: 9 on macOS / 8 on Linux (`mdoctor list` shows the live set for your machine).

A full `mdoctor clean` does not run every registered module — it runs a fixed step list of 7 on macOS / 6 on Linux. The opted-out modules — `downloads` (report-only: it lists large files, never deletes) and `browser` — run via `mdoctor clean -m <name>` or `mdoctor clean --interactive`.

| Module | What it removes | Platform |
|--------|-----------------|----------|
| `trash` | Files in Trash (`~/.Trash` on macOS, freedesktop Trash on Linux) | Both |
| `caches` | User-level cache directories — `~/Library/Caches` on macOS, `~/.cache` (the XDG cache home) on Linux | Both |
| `logs` | Old log files | Both |
| `downloads` | Report only: lists large files in `~/Downloads` older than threshold (never deletes) | Both |
| `crash_reports` | Old crash and diagnostic reports | Both |
| `apt` | APT package cache (`/var/cache/apt/archives`) plus autoremove | Linux only |
| `pacman` | pacman package cache (`/var/cache/pacman/pkg`), AUR helper caches, plus orphan removal | Linux only |
| `ios_backups` | Old iOS device backups | macOS only |
| `browser` | Browser cache files | Both |
| `dev_caches` | Package-manager caches (npm, Yarn, pnpm, pip, Conda, Maven, Gradle, Go, Cargo), stale `node_modules`, `brew cleanup`/`autoremove`, Docker prune (opt-in only); plus CocoaPods and Xcode DerivedData on macOS | Both |
| `xcode` | Xcode DerivedData, archives, old simulators | macOS only |

```bash
mdoctor clean                        # Dry-run the full-clean step list (7 on macOS / 6 on Linux)
mdoctor clean --dry-run              # Same dry-run, stated explicitly
mdoctor clean --force                # Same step list for real (asks to confirm)
mdoctor clean -m caches              # Dry-run one module
mdoctor clean -m caches --force      # Run one module for real
mdoctor clean -m apt --force         # Debian Linux only — clean the APT cache for real
mdoctor clean -m pacman --force      # Arch Linux only — clean the pacman cache for real
mdoctor clean -m xcode --force       # macOS only — clean Xcode data for real
mdoctor clean --interactive          # Guided module selection
mdoctor clean --interactive --force  # Guided destructive run
```

---

## Fix Cheat Sheet

| Target | What it does | Risk | Platform |
|--------|--------------|------|----------|
| `dns` | Flush DNS cache | LOW | Both |
| `apt` | Fix APT packages (update, upgrade, autoremove) | LOW | Linux only |
| `pacman` | Fix pacman packages (keyring refresh, full upgrade) | LOW | Linux only |
| `homebrew` | Update, upgrade, and cleanup Homebrew | LOW | macOS only |
| `disk` | Free disk space | LOW | macOS only |
| `bluetooth` | Reset Bluetooth module (devices may need re-pairing) | LOW | macOS only |
| `audio` | Restart Core Audio daemon | LOW | macOS only |
| `wifi` | Renew DHCP, flush DNS, cycle Wi-Fi | LOW | macOS only |
| `permissions` | Reset file permissions | MED | macOS only |
| `spotlight` | Rebuild Spotlight index | MED | macOS only |
| `timemachine` | Verify Time Machine backups (may take a long time) | MED | macOS only |

```bash
mdoctor fix dns          # Flush DNS cache (runs on both platforms)
mdoctor fix apt          # Debian Linux only — repair APT packages
mdoctor fix pacman       # Arch Linux only — repair pacman packages
mdoctor fix wifi         # macOS only — renew DHCP, flush DNS, cycle Wi-Fi
mdoctor fix all          # Run all applicable fixes for this platform
```

---

## Diagnose Cheat Sheet

`mdoctor diagnose` is the active counterpart to `mdoctor check -m performance` — it samples the live metrics, correlates them and prints a prioritized remedy list. Read-only (`[SAFE]`): remedies are printed, never applied.

| Command | What it does | Risk | Platform |
|---------|--------------|------|----------|
| `mdoctor diagnose` | Active performance diagnosis — CPU, memory, disk I/O, swap, zombies, FD limits and connection counts, plus cross-check correlation | SAFE | Both |

```bash
mdoctor diagnose          # Active performance diagnosis (read-only)
mdoctor diagnose --debug  # Same run with structured debug diagnostics
```

---

## Other Commands

```bash
mdoctor info             # System information summary
mdoctor list             # All modules for this platform, with categories and risk levels
mdoctor diagnose         # Active performance diagnosis (read-only — prints remedies, never runs them)
mdoctor history          # Health score trends over time
mdoctor version          # Print the version
mdoctor help             # Full help and environment variables
```

Heavier operations (both platforms): `mdoctor benchmark` runs disk, network and CPU speed tests; `mdoctor update --check` checks for a stable update and `mdoctor update` applies it.

---

## Tips

**Read safety + recovery guidance first** — See [SAFETY.md](SAFETY.md) for whitelist/scope controls, logs, recovery flow, and known limitations.

**Preview before deleting** — `mdoctor clean` runs in dry-run mode by default on both platforms. Review the output, then re-run with `--force` to actually delete.

**Change the age threshold** — Cleanup modules each ship their own documented default (7 days for logs/downloads, 30 for crash_reports and the macOS only `xcode` module, 90 for the macOS only `ios_backups` module). Override every module at once with:

```bash
DAYS_OLD_OVERRIDE=14 mdoctor clean --force        # Override all module age thresholds
DAYS_OLD_NODE_MODULES=60 mdoctor clean --force    # dev_caches stale node_modules (default 30)
```

**JSON output for scripts** — Pipe check results into your tooling:

```bash
mdoctor check --json               # Full audit as JSON
mdoctor check -m disk --json       # Single module as JSON
```

**See what a command is doing** — `--debug` turns on structured debug
diagnostics (accepted by `check`, `clean`, `fix`, `diagnose`, `update`);
`MDOCTOR_DEBUG=true` does the same from the environment:

```bash
mdoctor diagnose --debug
MDOCTOR_DEBUG=true mdoctor check -m disk
```

**Run a single check** — Use `-m` to target one module:

```bash
mdoctor check -m battery
mdoctor check -m network
```
