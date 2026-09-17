# Architecture

## Overview

mdoctor is a modular Bash CLI for macOS and Debian/Arch-based Linux diagnostics, cleanup, fixes, and maintenance.

Core properties:
- CLI-first command router (`mdoctor`)
- Platform-aware module loading via `lib/platform.sh` (macOS, Debian, Arch/Omarchy, etc.)
- Engine scripts for full workflows (`doctor.sh`, `cleanup.sh`)
- Module-based checks/cleanups/fixes with platform-conditional sourcing
- Centralized safety + logging primitives
- Test/lint/CI quality gates (macOS, Linux, Bash 3.2)

## Component Diagram

```mermaid
graph TD
  CLI[mdoctor]

  CLI --> CHECK[doctor.sh]
  CLI --> CLEAN[cleanup.sh]
  CLI --> FIX[fixes/*.sh]
  CLI --> DIAGNOSE["diagnose → checks/diagnose_performance.sh"]
  CLI --> INFO[inline commands: info/list/history/benchmark/version/update]

  CHECK --> CHECKS[checks/*.sh (23 files)]
  CLEAN --> CLEANUPS[cleanups/*.sh (11 files)]

  CHECKS --> LIB[lib/*.sh]
  CLEANUPS --> LIB
  FIX --> LIB
  DIAGNOSE --> LIB

  LIB --> SAFETY[lib/safety.sh]
  LIB --> SCOPE[lib/cleanup_scope.sh]
  LIB --> LOGGING[lib/logging.sh]
  LIB --> METADATA[lib/metadata.sh]

  TESTS[tests/run.sh + test_*.bats] --> CLI
  CI[GitHub Actions CI] --> LINT[scripts/lint_shell.sh]
  CI --> TESTS
  CI --> RELEASE_SANITY[installer/uninstaller isolated-path sanity]
```

## Platform Abstraction

`lib/platform.sh` is sourced first by every entry point. It detects the OS at startup and exports:

| Global | Example values |
|--------|---------------|
| `MDOCTOR_PLATFORM` | `macos`, `linux` |
| `MDOCTOR_DISTRO` | `""` (macOS), `ubuntu`, `debian`, `omarchy`, `arch` |
| `MDOCTOR_DISTRO_LIKE` | `""` (macOS), `debian` (Ubuntu/Mint), `arch` (Omarchy) |
| `MDOCTOR_OS_NAME` | `macOS 15.3`, `Ubuntu 24.04 LTS` |

Predicates (`is_macos`, `is_linux`, `is_debian`, `is_arch`, `is_omarchy`) gate platform-specific module loading and logic branches. Platform-aware path helpers (`platform_trash_dir`, `platform_cache_dir`, `platform_log_dir`, `platform_crash_dirs`) abstract OS differences in file locations.

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
- Platform-specific modules are conditionally sourced (e.g., `homebrew.sh` on macOS, `apt.sh` on Debian, `pacman.sh` on Arch)
- `checks/diagnose_performance.sh` is registered in `lib/registry.sh` as the `diagnose` module type (`System`, `[SAFE]`); `mdoctor diagnose` sources and runs it directly — no `doctor.sh` engine pass — sampling the shared `lib/perf_probes.sh` probes and printing prioritized remedies without executing them

### 4) Library Layer (`lib/*`)
- `platform.sh` OS/distro detection predicates (`is_macos`, `is_linux`, `is_debian`, `is_arch`, `is_omarchy`) and platform-aware paths
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

### Diagnose flow
1. `mdoctor diagnose` → `cmd_diagnose` sources `lib/perf_probes.sh` and `checks/diagnose_performance.sh` directly (the `diagnose` module type — no `doctor.sh` pass)
2. Capture-once prefill: `perf_capture_reset` clears the `_PERF_*` snapshots, then the shared samplers run once per process — `vm_stat`, `/proc/meminfo`, `/proc/loadavg`, `nproc`, swap and the `/proc/stat` iowait sample are each read at most once, and every consumer replays the cached copy
3. Every blocking-class external probe is timeout-capped via `mdoctor_timeout`/`tcap` (`MDOCTOR_CMD_TIMEOUT_S`, `MDOCTOR_NET_TIMEOUT_S`, `MDOCTOR_DU_TIMEOUT_S`), so a wedged daemon or a huge socket table cannot stall the run
4. Read-only sections report CPU, memory, disk I/O, swap, zombies, FD limits and open connections, then a cross-check correlation
5. The Diagnosis Summary prints prioritized remedies (critical first) — it never executes them

## Safety Model (summary)

- Dry-run by default
- Force-mode pre-flight visibility
- Protected path validation + symlink restrictions
- Whitelist and scope user controls
- Structured error taxonomy and operation logs

See also: [SAFETY.md](SAFETY.md).
