# Architecture

## Overview

mdoctor is a modular Bash CLI for macOS diagnostics, cleanup, fixes, and maintenance updates.

Core properties:
- CLI-first command router (`mdoctor`)
- engine scripts for full workflows (`doctor.sh`, `cleanup.sh`)
- module-based checks/cleanups/fixes
- centralized safety + logging primitives
- test/lint/CI quality gates

## Component Diagram

```mermaid
graph TD
  CLI[mdoctor]

  CLI --> CHECK[doctor.sh]
  CLI --> CLEAN[cleanup.sh]
  CLI --> FIX[fixes/*.sh]
  CLI --> INFO[inline commands: info/list/history/benchmark/version/update]

  CHECK --> CHECKS[checks/*.sh (21)]
  CLEAN --> CLEANUPS[cleanups/*.sh (10)]

  CHECKS --> LIB[lib/*.sh]
  CLEANUPS --> LIB
  FIX --> LIB

  LIB --> SAFETY[lib/safety.sh]
  LIB --> SCOPE[lib/cleanup_scope.sh]
  LIB --> LOGGING[lib/logging.sh]
  LIB --> METADATA[lib/metadata.sh]

  TESTS[tests/run.sh + test_*.sh] --> CLI
  CI[GitHub Actions CI] --> LINT[scripts/lint_shell.sh]
  CI --> TESTS
  CI --> RELEASE_SANITY[installer/uninstaller isolated-path sanity]
```

## Layer Responsibilities

### 1) CLI Layer (`mdoctor`)
- Parses subcommands/options
- Dispatches to engines/modules
- Handles command-level UX (`--help`, `--debug`, `--interactive`, `update`)

### 2) Engine Layer (`doctor.sh`, `cleanup.sh`)
- Runs full check/cleanup workflows
- Coordinates shared state and summaries
- Produces reports and logs

### 3) Module Layer (`checks/*`, `cleanups/*`, `fixes/*`)
- Each file is focused on one concern
- Modules are sourced (shared state, no extra process boundaries)

### 4) Library Layer (`lib/*`)
- `common.sh` UI/status/progress helpers
- `logging.sh` report + operation session logging
- `safety.sh` guarded deletion APIs and destructive error taxonomy
- `cleanup_scope.sh` include/exclude scope config for dev cache scans
- `metadata.sh`, `json.sh`, `history.sh`, `benchmark.sh`, `disk.sh`

## Key Runtime Flows

### Health check flow
1. `mdoctor check` → `doctor.sh`
2. Check modules execute read-only diagnostics
3. Warning/failure counters build health score
4. Report/log output is generated

### Cleanup flow
1. `mdoctor clean` defaults to dry-run
2. Optional `--force` enables deletion after pre-flight summary
3. Cleanup modules call centralized safety primitives (`safe_remove*`, `safe_find_delete`)
4. Whitelist/scope controls are applied where relevant
5. Operation session is recorded to `~/.config/mdoctor/operations.log`

### Update flow
1. `mdoctor update --check` fetches and compares `origin/main`
2. `mdoctor update` fast-forwards checkout when updates exist

## Safety Model (summary)

- Dry-run by default
- Force-mode pre-flight visibility
- Protected path validation + symlink restrictions
- Whitelist and scope user controls
- Structured error taxonomy and operation logs

See also: [SAFETY.md](SAFETY.md).
