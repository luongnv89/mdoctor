# Mac Doctor Guidebook

Quick problem-to-command reference. Find your symptom, run the command.

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

| Problem | Command |
|---------|---------|
| Disk is almost full | `mdoctor check -m disk` |
| Find what's eating space | `mdoctor check -m storage` |
| Clear user caches | `mdoctor clean -m caches --force` |
| Clean Xcode bloat (DerivedData, archives, simulators) | `mdoctor clean -m xcode --force` |
| Clean dev dependency caches (npm, pip, Gradle, etc.) | `mdoctor clean -m dev_caches --force` |
| Clean dev tool caches (Homebrew, Docker) | `mdoctor clean -m dev --force` |
| Empty the Trash | `mdoctor clean -m trash --force` |
| Remove large old files from Downloads | `mdoctor clean -m downloads --force` |
| Delete old crash/diagnostic reports | `mdoctor clean -m crash_reports --force` |
| Clear browser caches | `mdoctor clean -m browser --force` |
| Purge old log files | `mdoctor clean -m logs --force` |
| Free disk space (combined fix) | `mdoctor fix disk` |

### Performance

| Problem | Command |
|---------|---------|
| General system info (OS, memory, load) | `mdoctor check -m system` |
| Mac feels slow | `mdoctor check -m performance` |
| High CPU usage | `mdoctor check -m performance` |
| High memory pressure | `mdoctor check -m performance` |
| Thermal throttling / fans loud | `mdoctor check -m hardware` |
| Too many login items slowing boot | `mdoctor check -m startup` |
| Spotlight using too much CPU | `mdoctor fix spotlight` |

### Network & Connectivity

| Problem | Command |
|---------|---------|
| No internet connection | `mdoctor check -m network` |
| Slow or broken DNS | `mdoctor fix dns` |
| Weak Wi-Fi signal | `mdoctor check -m network` |
| Wi-Fi keeps dropping | `mdoctor fix wifi` |
| Bluetooth not working | `mdoctor check -m bluetooth` |
| Bluetooth device won't connect | `mdoctor fix bluetooth` |

### Audio & Peripherals

| Problem | Command |
|---------|---------|
| No sound / wrong audio output | `mdoctor fix audio` |
| USB device not recognized | `mdoctor check -m usb` |
| Bluetooth audio issues | `mdoctor fix bluetooth` |

### Security & Privacy

| Problem | Command |
|---------|---------|
| Is my firewall on? | `mdoctor check -m security` |
| Is FileVault enabled? | `mdoctor check -m security` |
| Is SIP (System Integrity Protection) on? | `mdoctor check -m security` |
| Gatekeeper status | `mdoctor check -m security` |
| File permission issues | `mdoctor fix permissions` |

### Software & Dev Tools

| Problem | Command |
|---------|---------|
| Homebrew errors or outdated | `mdoctor check -m homebrew` |
| Update and fix Homebrew | `mdoctor fix homebrew` |
| Node.js / npm issues | `mdoctor check -m node` |
| Python / pip issues | `mdoctor check -m python` |
| Docker not running or unhealthy | `mdoctor check -m containers` |
| Git or SSH config problems | `mdoctor check -m git_config` |
| Xcode CLT missing or outdated | `mdoctor check -m devtools` |
| Shell config syntax errors | `mdoctor check -m shell` |

### Startup & Apps

| Problem | Command |
|---------|---------|
| Slow boot / too many login items | `mdoctor check -m startup` |
| App keeps crashing | `mdoctor check -m apps` |
| macOS updates pending | `mdoctor check -m updates` |

### Backup

| Problem | Command |
|---------|---------|
| Time Machine problems | `mdoctor fix timemachine` |
| Old iOS backups wasting space | `mdoctor clean -m ios_backups --force` |

---

## Cleanup Cheat Sheet

All cleanup modules are **[LOW]** risk. Dry-run by default — add `--force` to actually delete.

| Module | What it removes |
|--------|-----------------|
| `trash` | Files in Trash |
| `caches` | User-level cache directories (`~/Library/Caches`) |
| `logs` | Old log files |
| `downloads` | Large files in `~/Downloads` older than threshold |
| `crash_reports` | Old crash and diagnostic reports |
| `ios_backups` | Old iOS device backups |
| `browser` | Browser cache files |
| `dev` | Developer tool caches (Homebrew cache, Docker unused images) |
| `xcode` | Xcode DerivedData, archives, old simulators |
| `dev_caches` | Package manager caches (npm, Yarn, pnpm, pip, Composer, Gradle, Maven, Carthage, CocoaPods) |

```bash
mdoctor clean                        # Dry-run all 10 modules
mdoctor clean --force                # Run all 10 modules for real
mdoctor clean -m <module>            # Dry-run one module
mdoctor clean -m <module> --force    # Run one module for real
mdoctor clean --interactive          # Guided module selection
mdoctor clean --interactive --force  # Guided destructive run
```

---

## Fix Cheat Sheet

| Target | What it does | Risk |
|--------|-------------|------|
| `homebrew` | Update, upgrade, and cleanup Homebrew | LOW |
| `dns` | Flush DNS cache | LOW |
| `disk` | Free disk space | LOW |
| `bluetooth` | Reset Bluetooth module (devices may need re-pairing) | LOW |
| `audio` | Restart Core Audio daemon | LOW |
| `wifi` | Renew DHCP, flush DNS, cycle Wi-Fi | LOW |
| `permissions` | Reset file permissions | MED |
| `spotlight` | Rebuild Spotlight index | MED |
| `timemachine` | Verify Time Machine backups (may take a long time) | MED |

```bash
mdoctor fix <target>    # Run a specific fix
mdoctor fix all         # Run all fixes
```

---

## Tips

**Read safety + recovery guidance first** — See [SAFETY.md](SAFETY.md) for whitelist/scope controls, logs, recovery flow, and known limitations.

**Preview before deleting** — All `mdoctor clean` commands run in dry-run mode by default. Review the output, then re-run with `--force` to actually delete.

**Change the age threshold** — Cleanup modules skip files newer than 7 days. Override with:

```bash
DAYS_OLD_OVERRIDE=14 mdoctor clean --force
```

**JSON output for scripts** — Pipe check results into your tooling:

```bash
mdoctor check --json
mdoctor check --json | python3 -m json.tool   # pretty-print
```

**Run a single check** — Use `-m` to target one module:

```bash
mdoctor check -m battery
mdoctor check -m network
```

**Other commands:**

```bash
mdoctor info         # System information summary
mdoctor list         # List all modules with categories and risk levels
mdoctor history      # View health score trends over time
mdoctor benchmark    # Run disk, network, CPU speed tests
mdoctor update --check  # Check for stable updates
mdoctor update         # Apply latest stable update
```
