# Architecture

## Overview

mdoctor is a modular Bash CLI toolkit for macOS diagnostics, cleanup, and fixes. It follows a plugin-like architecture where each concern is isolated in its own script file.

## Component Diagram

```
                  ┌──────────┐
                  │  mdoctor  │  Unified CLI entry point
                  └─────┬────┘
                        │
          ┌─────────────┼─────────────┐
          │             │             │
    ┌─────▼────┐  ┌─────▼────┐  ┌────▼─────┐
    │ doctor.sh │  │cleanup.sh│  │  fix     │
    │  (check)  │  │ (clean)  │  │(inline)  │
    └─────┬────┘  └─────┬────┘  └──────────┘
          │             │
    ┌─────▼────┐  ┌─────▼─────┐
    │ checks/* │  │ cleanups/* │
    │ 9 modules│  │ 6 modules │
    └─────┬────┘  └─────┬─────┘
          │             │
          └──────┬──────┘
           ┌─────▼────┐
           │   lib/*   │
           │ 3 modules │
           └──────────┘
```

## Layers

### CLI Layer (`mdoctor`)
- Parses commands and options
- Routes to the correct engine or inline handler
- Provides `--help` for each subcommand
- Resolves its own install path by following symlinks

### Engine Layer (`doctor.sh`, `cleanup.sh`)
- Orchestrates module execution
- Manages global state (scores, counters, dry-run mode)
- Generates summary reports

### Module Layer (`checks/*`, `cleanups/*`)
- Each file contains one or more related functions
- Modules are sourced (not executed) by the engine
- Modules use shared library functions for consistent output

### Library Layer (`lib/*`)
- `common.sh` -- Colors, icons, status output helpers
- `logging.sh` -- Markdown report generation and cleanup logging
- `disk.sh` -- Disk space utilities

## Data Flow

### Health Check Flow
1. `mdoctor check` invokes `doctor.sh`
2. Libraries are sourced, then all 9 check modules
3. Each check function runs and calls `status_ok`/`status_warn`/`status_fail`
4. Warnings and failures increment global counters
5. A health score is computed: `100 - (warnings * 4) - (failures * 8)`
6. A markdown report is written to `/tmp/`

### Cleanup Flow
1. `mdoctor clean` invokes `cleanup.sh`
2. Dry-run mode is default; `--force` disables it
3. Each cleanup function calls `run_cmd` which either logs or executes
4. Disk usage is measured before and after to calculate freed space

## Design Decisions

- **Pure Bash** -- No external dependencies beyond standard macOS tools
- **Read-only by default** -- `check` never modifies the system; `clean` defaults to dry-run
- **Modular sourcing** -- Modules are sourced, not subprocesses, for shared state access
- **Symlink-aware** -- The CLI resolves symlinks so it works when installed via `/usr/local/bin`
