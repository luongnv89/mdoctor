# Safety & Recovery Guide

This document explains how mdoctor reduces cleanup risk, what still can go wrong, and how to recover quickly.

## Safety Model (Defense in Depth)

mdoctor cleanup uses multiple safety layers:

1. **Dry-run by default**
   - `mdoctor clean` previews actions without deleting files.
   - Real deletion requires `--force`.

2. **Force-mode preflight summary + confirmation gate**
   - Before destructive runs, mdoctor prints touched targets and reclaim
     estimates. The summary is informational only — it is not a
     review-then-approve step.
   - After the summary, a `Proceed with deletion? [y/N]` prompt is the
     approval gate: only an explicit `y` proceeds; anything else aborts
     with no files deleted.
   - `MDOCTOR_ASSUME_YES=true` skips the prompt (automation/CI). With it
     set there is no confirmation — `--force` deletes immediately after
     the summary.
   - `--force` on a non-tty without `MDOCTOR_ASSUME_YES=true` refuses
     outright and names the variable.

3. **Deletion safety primitives**
   - Cleanup modules route through guarded helpers in `lib/safety.sh`.
   - Protected targets, traversal patterns, and unsafe symlink deletes are blocked.
   - Every deletion target must sit under an allowed deletion root (see
     below); anything else is rejected even if no denylist rule matches.
   - The denylist stays as a backstop, including carve-outs for the two
     legitimate subtrees under broadly-protected parents (`/var/crash`,
     `/var/tmp`).

### Allowed deletion roots

Single source of truth: `_mdoctor_allowed_deletion_roots()` in
`lib/safety.sh`. This list mirrors it (regenerate by reading that
function if they disagree — the code wins):

- Temp: `${TMPDIR:-/tmp}`, `/tmp`, `/var/tmp`
- Crash intake: `/var/crash`
- macOS Trash / caches / logs / developer data: `~/.Trash`,
  `~/Library/Caches`, `~/Library/Logs`, `~/Library/Developer`,
  `~/Library/Application Support/MobileSync`
- Linux Trash / logs / apport / pnpm: `~/.local/share/Trash`,
  `~/.local/share/mdoctor`, `~/.local/share/apport`,
  `~/.local/share/pnpm`
- Developer caches: `~/.cache`, `~/.npm`, `~/.yarn`, `~/.m2`,
  `~/.gradle`, `~/.cargo`, `~/go`, `~/miniconda3`, `~/anaconda3`
- Stale `node_modules`: any `<project>/node_modules` under `$HOME`
  (basename rule — parents and siblings are never covered)

Deliberately excluded: `/home`, `/root`, `/opt`, `/srv`, `/mnt`,
`/media`, `/usr/local/bin`, system-wide
`/Library/Logs/DiagnosticReports` (macOS crash cleanup covers the user
domain `~/Library/Logs/DiagnosticReports` only), `~/Downloads` (no
module deletes there today), `~/.config`, `~/.local`.

### Operations outside the safety primitives

Two operations reachable from a forced clean do **not** route through
the guarded helpers, so `validate_deletion_path` and the whitelist do
**not** apply to them:

- `docker system prune -af --volumes` — `cleanups/dev_caches.sh`.
  Deletes unused containers, images **and
  named volumes** (database data, not caches). Gated by the opt-in flag
  `MDOCTOR_ALLOW_DOCKER_PRUNE=true` (Task 0.6): without it the prune is
  skipped and logged.
- `sudo apt-get clean` / `autoclean` / `autoremove -y` —
  `cleanups/apt.sh:19,22,26`. Runs the system package manager with
  privilege, including an unattended `autoremove` that uninstalls
  packages. Not filtered by any path check.

Both are additionally covered by the layer-2 confirmation gate
(Task 0.5): an interactive `--force` asks `[y/N]` after the pre-flight
summary, and a non-tty `--force` without `MDOCTOR_ASSUME_YES=true`
refuses. The gate limits *when* they run; it does not filter *what*
they touch — review the pre-flight summary before answering `y`.

4. **User protection controls**
   - Whitelist: `~/.config/mdoctor/cleanup_whitelist`
   - Scope control (dev caches): `~/.config/mdoctor/cleanup_scope.conf`

5. **Operational traceability**
   - Persistent operation log: `~/.config/mdoctor/operations.log`
   - Cleanup runtime log: `~/Library/Logs/macos_cleanup.log` (macOS) or `~/.local/share/mdoctor/mdoctor_cleanup.log` (Linux)

## Safe Operating Checklist

Before using `--force`:

- Run dry-run first: `mdoctor clean` or `mdoctor clean -m <module>`
- For guided selection, use: `mdoctor clean --interactive`
- Confirm whitelist/scope config reflects your environment
- Close apps that heavily mutate caches during cleanup (Xcode, Docker, browsers)
- Know the gate: interactive `--force` asks once per run (`[y/N]`,
  default no); non-interactive runs need `MDOCTOR_ASSUME_YES=true`, under
  which there is no confirmation and `--force` deletes immediately

## Configuration Controls

### Cleanup whitelist

Path: `~/.config/mdoctor/cleanup_whitelist`

Use it to protect important cache/model/data paths from cleanup.

Examples:

```text
~/.ollama/models
~/.cache/huggingface
~/.m2/repository/*
```

Rules:
- One path per line
- `#` comments and blank lines are ignored
- Exact path protects itself + descendants
- `/*` protects descendants under a base path

### Cleanup scope (dev_caches node_modules scan)

Path: `~/.config/mdoctor/cleanup_scope.conf`

Use it to tune stale `node_modules` scanning in `dev_caches`.

Examples:

```text
INCLUDE_PATH=~/workspace
INCLUDE_PATH=~/projects
EXCLUDE_GLOB=*important-monorepo/node_modules*
```

Rules:
- If no include paths are configured, default scan behavior is preserved
- Exclude globs are matched before deletion

## Recovery Playbook

If you suspect an unwanted cleanup:

1. **Stop additional destructive operations**
   - Do not run more `--force` commands until triage is done.

2. **Inspect operation logs**
   - `~/.config/mdoctor/operations.log`
   - `~/Library/Logs/macos_cleanup.log` (macOS) or `~/.local/share/mdoctor/mdoctor_cleanup.log` (Linux)

3. **Check recoverable locations first**
   - For user files, check the trash (`~/.Trash` on macOS, `~/.local/share/Trash/files` on Linux) and app-level recovery features.

4. **Restore from backups**
   - Use Time Machine (macOS), Timeshift (Linux), or other backups for non-recoverable deletions.

5. **Harden before next run**
   - Add missing protected paths to `cleanup_whitelist`
   - Narrow `cleanup_scope.conf` includes/excludes
   - Re-run in dry-run and confirm output before using `--force`

## Known Limitations

- `--force` deletions are not automatically undoable.
- Reclaim estimates are approximate (some command-driven cleanup cannot be sized in advance).
- Some system paths are intentionally blocked by safety policy.
- `docker system prune -af --volumes` and `sudo apt-get
  clean/autoclean/autoremove -y` run outside the safety primitives (see
  "Operations outside the safety primitives" above) — the whitelist and
  protected-path checks do not filter them; only the Docker opt-in flag
  and the confirmation gate constrain them.
- Certain macOS-protected areas (SIP/read-only zones) may report permission-like failures.
- On Linux, SELinux or AppArmor restrictions may cause similar permission-like failures.
- Scope config currently targets stale `node_modules` behavior under `dev_caches` (not every cleanup module).

## Platform Differences

| Aspect | macOS | Linux (Debian) |
|--------|-------|----------------|
| Trash location | `~/.Trash` | `~/.local/share/Trash/files` |
| User cache dir | `~/Library/Caches` | `~/.cache` |
| User log dir | `~/Library/Logs` | `~/.local/share/mdoctor` |
| Crash reports | `~/Library/Logs/DiagnosticReports` | `/var/crash`, `~/.local/share/apport` |
| Protected paths | SIP/read-only system volume | `/boot`, `/proc`, `/sys`, `/dev`, SELinux |
| Config dir | `~/.config/mdoctor/` | `~/.config/mdoctor/` (same) |

## Recommended Defaults

- Prefer module-targeted cleanup over full-force cleanup.
- Keep a current backup strategy (Time Machine on macOS, Timeshift or rsync on Linux).
- Use `mdoctor update` regularly for safety improvements.
