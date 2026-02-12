# mdoctor - macOS Doctor

A unified CLI toolkit for checking, cleaning, fixing, and diagnosing macOS systems.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mac-doctor/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/luongnv89/mac-doctor.git ~/.mdoctor
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
mac-doctor/
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
└── gui/                 # TUI application (optional)
```

## Extending

### Add a new health check

1. Create `checks/mycheck.sh`:

```bash
check_my_feature() {
  step "My Feature Check"
  if command -v mytool >/dev/null 2>&1; then
    status_ok "mytool is installed"
  else
    status_warn "mytool not found"
    add_action "Install mytool: brew install mytool"
  fi
}
```

2. Source it in `doctor.sh` and call the function from `main()`
3. Increment `STEP_TOTAL`

### Add a new cleanup module

1. Create `cleanups/mycleanup.sh`:

```bash
clean_my_cache() {
  header "Cleaning My Cache"
  if [ -d "${HOME}/.mycache" ]; then
    run_cmd "rm -rf \"${HOME}/.mycache\"/*"
  else
    log "No cache found."
  fi
}
```

2. Source it in `cleanup.sh` and call the function
3. Increment `PROGRESS_TOTAL`

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mac-doctor/main/uninstall.sh | bash
```

Or manually:

```bash
rm -f /usr/local/bin/mdoctor
rm -rf ~/.mdoctor
```

## License

Use freely. No warranty provided.
