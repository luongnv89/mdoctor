# Safety & Recovery Guide

This document explains how mdoctor reduces cleanup risk, what still can go wrong, and how to recover quickly.

## Safety Model (Defense in Depth)

mdoctor cleanup uses multiple safety layers:

1. **Dry-run by default**
   - `mdoctor clean` previews actions without deleting files.
   - Real deletion requires `--force`.

2. **Force-mode preflight summaries**
   - Before destructive runs, mdoctor prints touched targets and reclaim estimates.

3. **Deletion safety primitives**
   - Cleanup modules route through guarded helpers in `lib/safety.sh`.
   - Protected targets, traversal patterns, and unsafe symlink deletes are blocked.

4. **User protection controls**
   - Whitelist: `~/.config/mdoctor/cleanup_whitelist`
   - Scope control (dev caches): `~/.config/mdoctor/cleanup_scope.conf`

5. **Operational traceability**
   - Persistent operation log: `~/.config/mdoctor/operations.log`
   - Cleanup runtime log: `~/Library/Logs/macos_cleanup.log`

## Safe Operating Checklist

Before using `--force`:

- Run dry-run first: `mdoctor clean` or `mdoctor clean -m <module>`
- For guided selection, use: `mdoctor clean --interactive`
- Confirm whitelist/scope config reflects your environment
- Close apps that heavily mutate caches during cleanup (Xcode, Docker, browsers)

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
   - `~/Library/Logs/macos_cleanup.log`

3. **Check recoverable locations first**
   - For user files, check `~/.Trash` and app-level recovery features.

4. **Restore from backups**
   - Use Time Machine or other backups for non-recoverable deletions.

5. **Harden before next run**
   - Add missing protected paths to `cleanup_whitelist`
   - Narrow `cleanup_scope.conf` includes/excludes
   - Re-run in dry-run and confirm output before using `--force`

## Known Limitations

- `--force` deletions are not automatically undoable.
- Reclaim estimates are approximate (some command-driven cleanup cannot be sized in advance).
- Some system paths are intentionally blocked by safety policy.
- Certain macOS-protected areas (SIP/read-only zones) may report permission-like failures.
- Scope config currently targets stale `node_modules` behavior under `dev_caches` (not every cleanup module).

## Recommended Defaults

- Prefer module-targeted cleanup over full-force cleanup.
- Keep a current backup strategy (Time Machine strongly recommended).
- Use `mdoctor update` regularly for safety improvements.
