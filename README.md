# macOS Doctor & Cleanup Scripts

A modular system health check and cleanup toolkit for macOS.

## Overview

This toolkit consists of two main scripts:
- **doctor.sh** - System health audit (read-only)
- **cleanup.sh** - System cleanup (with dry-run mode)

## Project Structure

```
doctor/
├── lib/                    # Shared library modules
│   ├── common.sh          # Colors, icons, UI helpers
│   ├── logging.sh         # Logging and markdown reports
│   └── disk.sh            # Disk utilities
├── checks/                # Doctor check modules
│   ├── system.sh          # System & OS checks
│   ├── disk.sh            # Disk health checks
│   ├── updates.sh         # Update status checks
│   ├── homebrew.sh        # Homebrew checks
│   ├── node.sh            # Node.js & npm checks
│   ├── python.sh          # Python & pip checks
│   ├── devtools.sh        # Xcode, Git, Docker checks
│   ├── shell.sh           # Shell config checks
│   └── network.sh         # Network connectivity checks
├── cleanups/              # Cleanup modules
│   ├── trash.sh           # Trash cleanup
│   ├── caches.sh          # User caches cleanup
│   ├── logs.sh            # Old logs cleanup
│   ├── downloads.sh       # Large files in Downloads
│   ├── browser.sh         # Browser caches (optional)
│   └── dev.sh             # Developer tools cleanup
├── doctor.sh              # Main doctor script
└── cleanup.sh             # Main cleanup script
```

## Usage

### Doctor Script

Run system health checks:

```bash
./doctor.sh
```

This will:
- Check system information (OS, uptime, memory)
- Check disk health and free space
- Check for macOS updates
- Check Homebrew, Node.js, Python, and dev tools
- Check shell configurations
- Check network connectivity
- Generate a health score and markdown report
- Provide actionable recommendations

The script is **read-only** and makes no changes to your system.

### Cleanup Script

Run in dry-run mode (default, shows what would be deleted):

```bash
./cleanup.sh
```

Run in force mode (actually deletes):

```bash
./cleanup.sh --force
```

This will:
- Empty Trash
- Clean user caches
- Clean old logs (older than 7 days)
- List large files in Downloads (>500MB, older than 7 days)

Optional cleanups (commented out by default):
- Browser caches
- Developer tools (Homebrew, npm, pip, Docker, Xcode)

## Customization

### Adding New Health Checks

1. Create a new module in `checks/` directory
2. Implement your check function
3. Source the module in `doctor.sh`
4. Call your function from `main()`
5. Update `STEP_TOTAL` in `doctor.sh`

Example:

```bash
# checks/mycheck.sh
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

### Adding New Cleanup Tasks

1. Create a new module in `cleanups/` directory
2. Implement your cleanup function
3. Source the module in `cleanup.sh`
4. Call your function from `main()`
5. Update `PROGRESS_TOTAL` in `cleanup.sh`

Example:

```bash
# cleanups/mycleanup.sh
clean_my_cache() {
  header "Cleaning My Cache"
  if [ -d "${HOME}/.mycache" ]; then
    run_cmd "rm -rf \"${HOME}/.mycache\"/*"
  else
    log "No cache found."
  fi
}
```

### Configuring Cleanup Thresholds

Edit `cleanup.sh` to adjust:
- `DAYS_OLD` - Age threshold for log/file cleanup (default: 7 days)
- `LOGFILE` - Location of cleanup log file

## Benefits of Modular Architecture

### Maintainability
- Each module focuses on a single concern
- Easier to locate and fix bugs
- Changes are isolated to specific modules

### Reusability
- Shared utilities in `lib/` prevent code duplication
- Modules can be tested independently
- Easy to use modules in other scripts

### Extensibility
- Add new checks without modifying core logic
- Enable/disable features by commenting/uncommenting
- Mix and match modules as needed

### Readability
- Small, focused files are easier to understand
- Clear separation between concerns
- Consistent naming conventions

## Files

### Original Scripts (Backup)
- `doctor-old.sh` - Original monolithic doctor script (654 lines)
- `cleanup-old.sh` - Original monolithic cleanup script (268 lines)

### New Modular Scripts
- `doctor.sh` - New modular doctor script (~160 lines)
- `cleanup.sh` - New modular cleanup script (~120 lines)
- Total module lines: ~800 lines across 18 files

## Development

### Testing Individual Modules

Source the required libraries and test a module:

```bash
source lib/common.sh
source lib/logging.sh
source lib/disk.sh

# Initialize globals
STEP_CURRENT=0
STEP_TOTAL=1
ACTIONS=()
WARN_COUNT=0
FAIL_COUNT=0
LOG_PATHS=()
LOG_DESCS=()
REPORT_MD=""

init_colors
md_init

source checks/homebrew.sh
check_homebrew
```

### Adding Dependencies

If a module needs additional dependencies, document them in the module header:

```bash
#!/usr/bin/env bash
#
# checks/mycheck.sh
# My custom check
#
# Dependencies:
#   - lib/common.sh
#   - lib/logging.sh
#
```

## License

Use freely. No warranty provided.

## Contributing

To improve these scripts:
1. Keep modules small and focused
2. Use consistent naming conventions
3. Add error handling
4. Document dependencies
5. Test both dry-run and force modes for cleanup scripts
