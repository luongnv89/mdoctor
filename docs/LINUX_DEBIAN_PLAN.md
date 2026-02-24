# Linux Support Plan (Debian-based first)

Status: Planning
Scope: Debian-based Linux only (Debian, Ubuntu, Pop!_OS, Linux Mint, etc.)

## Goals

- Add Linux support without regressing macOS behavior.
- Keep safety model consistent (dry-run default, guarded deletion).
- Deliver incrementally with CI validation on Ubuntu.

## Non-goals (for initial rollout)

- Non-Debian distros (Fedora, Arch, Alpine, etc.).
- Full feature parity in v1 of Linux support.
- Systemd service management automation.

## Phase Plan

### P6.1 Platform abstraction foundation
- Add OS/distro detection helpers (`lib/platform.sh`).
- Route platform-specific commands through adapters.
- Keep explicit unsupported-message path for non-Debian Linux.

**Acceptance gate:**
- `mdoctor info` reports platform type/distro reliably.

### P6.2 Debian check modules (read-only first)
- Port/implement Linux-safe checks first:
  - system, disk, updates, security, startup, network, performance, storage
  - homebrew equivalent detection replaced with apt-native package checks where relevant
- Keep unsupported notices for macOS-only checks when needed.

**Acceptance gate:**
- `mdoctor check` completes on Ubuntu/Debian without hard failures from missing macOS tools.

### P6.3 Debian cleanup baseline
- Add Debian-safe cleanup targets (dry-run default):
  - user cache directories, logs, trash equivalents, apt cache (careful), dev caches
- Reuse safety primitives and whitelist controls.

**Acceptance gate:**
- `mdoctor clean` dry-run and `--force` module mode work on Debian with no protected-path regressions.

### P6.4 Debian fix targets
- Add Debian-compatible fix set:
  - DNS cache handling (resolver-specific), disk recommendations, package manager health checks
- Preserve explicit risk labels.

**Acceptance gate:**
- `mdoctor fix <target>` provides actionable behavior or clear unsupported guidance.

### P6.5 Installer/update hardening for Linux
- Extend installer/uninstaller for Debian paths and permissions.
- Validate `mdoctor update` flow in Debian environment.

**Acceptance gate:**
- install → run → update → uninstall works on Ubuntu CI lane.

### P6.6 CI matrix and regression gates
- Add Ubuntu job matrix alongside macOS.
- Run lint + regression tests + smoke checks on both platforms.

**Acceptance gate:**
- CI green on macOS and Ubuntu for baseline command set.

### P6.7 Docs and release readiness
- Document Debian support scope, caveats, and supported commands.
- Update guidebook and troubleshooting entries.

**Acceptance gate:**
- docs + changelog clearly state Debian support level and limitations.

## Risk Controls

- Never relax safety checks for Linux convenience.
- Keep destructive operations module-scoped and tested.
- Use feature gating + clear unsupported messaging rather than silent failures.

## Suggested Execution Order

1. P6.1 platform abstraction
2. P6.2 check modules
3. P6.3 cleanup baseline
4. P6.4 fix targets
5. P6.5 installer/update
6. P6.6 CI matrix
7. P6.7 docs/release
