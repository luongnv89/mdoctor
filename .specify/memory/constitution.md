<!--
SYNC IMPACT REPORT
==================
Version change: 0.0.0 → 1.0.0 (Initial ratification)
Modified principles: N/A (initial version)
Added sections:
  - Core Principles (5 principles)
  - Technology Standards
  - Development Workflow
  - Governance

Templates requiring updates:
  - .specify/templates/plan-template.md: N/A (generic, no constitution-specific refs)
  - .specify/templates/spec-template.md: N/A (generic, no constitution-specific refs)
  - .specify/templates/tasks-template.md: N/A (generic, no constitution-specific refs)

Follow-up TODOs: None
-->

# macOS Doctor & Cleanup Constitution

## Core Principles

### I. Modular Architecture

Every feature MUST be implemented as a focused, single-responsibility module.

- Shared utilities reside in `lib/` to prevent code duplication
- Health checks reside in `checks/` with one concern per file
- Cleanup tasks reside in `cleanups/` with one concern per file
- Modules MUST declare their dependencies in file headers
- Main scripts (`doctor.sh`, `cleanup.sh`) orchestrate modules without containing business logic

**Rationale**: Modularity enables independent testing, isolated bug fixes, and easy feature additions without modifying core logic.

### II. Safe by Default

All operations MUST be non-destructive unless explicitly requested.

- `doctor.sh` MUST be read-only; it MUST NOT modify the system
- `cleanup.sh` MUST default to dry-run mode; actual deletions require `--force` flag
- Dry-run output MUST clearly indicate what WOULD be affected without making changes
- Any new cleanup module MUST respect the `DRY_RUN` global flag

**Rationale**: Users trust system utilities. Accidental data loss or system modification destroys that trust permanently.

### III. CLI Text Protocol

All scripts MUST follow Unix CLI conventions for input and output.

- Input via command-line arguments and stdin
- Normal output to stdout; errors and warnings to stderr
- Support both human-readable output (default) and structured formats (Markdown reports)
- Exit codes MUST be meaningful: 0 for success, non-zero for failures
- Status indicators MUST use consistent icons: check for success, warning for attention needed, cross for failure

**Rationale**: Text-based I/O ensures debuggability, scriptability, and integration with standard Unix tools.

### IV. Extensibility First

Adding new checks or cleanup tasks MUST NOT require modifying existing code beyond sourcing and invocation.

- New modules MUST follow the established function naming conventions: `check_*` for health checks, `clean_*` for cleanup tasks
- Module addition requires only: (1) create module file, (2) source in main script, (3) call function, (4) update step counter
- Configuration thresholds (e.g., `DAYS_OLD`, file size limits) MUST be centralized and documented

**Rationale**: The toolkit's value grows with community contributions. Low friction for adding features encourages ecosystem growth.

### V. Actionable Output

Every diagnostic MUST provide clear, actionable guidance when issues are detected.

- Health checks MUST call `add_action()` with specific remediation commands when problems are found
- Cleanup scans MUST report exact paths and sizes for user decision-making
- The final summary MUST include a health score, issue counts, and prioritized action list
- Reports MUST be saved to accessible locations with timestamps

**Rationale**: A diagnostic that only identifies problems without solutions creates frustration, not value.

## Technology Standards

### Shell Scripting

- **Interpreter**: `#!/usr/bin/env bash` for portability
- **Strict Mode**: `set -euo pipefail` for cleanup scripts; `set -uo pipefail` for doctor (no `-e` to continue on individual check failures)
- **Compatibility**: Target macOS default bash (3.2+) unless documented otherwise
- **Style**: Use functions for all non-trivial logic; avoid inline complex pipelines

### File Organization

```
mac-doctor/
├── lib/           # Shared utilities (colors, logging, disk helpers)
├── checks/        # Health check modules (one file per concern)
├── cleanups/      # Cleanup task modules (one file per concern)
├── doctor.sh      # Main health audit script (orchestration only)
└── cleanup.sh     # Main cleanup script (orchestration only)
```

### Output Formats

- **Console**: Colored output via `tput` with graceful fallback when unavailable
- **Reports**: Markdown format saved to `/tmp/` with timestamped filenames
- **Logs**: Timestamped entries in `~/Library/Logs/` for cleanup operations

## Development Workflow

### Adding New Features

1. **Check Modules**: Create `checks/<name>.sh` with a `check_<name>()` function
2. **Cleanup Modules**: Create `cleanups/<name>.sh` with a `clean_<name>()` function
3. **Document Dependencies**: List required library sources in file header comments
4. **Update Counters**: Increment `STEP_TOTAL` or `PROGRESS_TOTAL` in main scripts
5. **Test Independently**: Source required libs and test module in isolation before integration

### Testing Requirements

- All check modules MUST be testable by sourcing libs and calling the check function directly
- Cleanup modules MUST be tested in dry-run mode before any force-mode testing
- New features MUST NOT break existing functionality; test full script execution after changes

### Code Review Checklist

- [ ] Module follows single-responsibility principle
- [ ] Dry-run mode respected for any destructive operations
- [ ] Consistent status reporting via `status_ok/status_warn/status_fail`
- [ ] Actionable recommendations provided via `add_action()` for detected issues
- [ ] Dependencies documented in file header
- [ ] Step counter updated in main script

## Governance

This constitution defines the non-negotiable principles for the macOS Doctor & Cleanup project.

### Amendment Process

1. Propose changes via pull request with clear rationale
2. Changes to Core Principles require explicit justification
3. All amendments MUST include migration guidance for affected code
4. Version number MUST be incremented according to semantic versioning:
   - MAJOR: Principle removal or incompatible redefinition
   - MINOR: New principle or significant guidance expansion
   - PATCH: Clarifications and non-semantic refinements

### Compliance

- All pull requests MUST comply with these principles
- Complexity beyond established patterns MUST be justified in PR description
- Runtime development guidance available in project README

**Version**: 1.0.0 | **Ratified**: 2025-12-01 | **Last Amended**: 2025-12-01
