# Design: task-p0-3-cleanup-module-safety-migration

## Approach
Migrate each cleanup module deletion point:

- Directory wipe patterns (`rm -rf <dir>/*`) → `safe_remove_children <dir>`
- Find+delete patterns (`find ... -delete`, `find ... -exec rm -rf`) → `safe_find_delete <base> <predicates>`
- Single target deletion (`rm -rf <path>`) → `safe_remove <path>`

Non-destructive command invocations remain as command-runner operations. Where practical, use `run_cmd_args` for clearer command handling.

## Files Affected
- `cleanups/trash.sh`
- `cleanups/caches.sh`
- `cleanups/logs.sh`
- `cleanups/downloads.sh`
- `cleanups/browser.sh`
- `cleanups/dev.sh`
- `cleanups/dev_caches.sh`
- `cleanups/crash_reports.sh`
- `cleanups/ios_backups.sh`
- `cleanups/xcode.sh`

## Decisions
- Decision: add `|| true` around safety helper calls in module flows.
- Rationale: cleanup should continue even if one path is blocked by policy.
- Tradeoff: command exit will not fail-fast on a single blocked target.

## Validation Plan
- Static:
  - `grep` for direct destructive patterns in `cleanups/*.sh`.
  - `bash -n` for modified scripts.
- Runtime dry-run smoke:
  - `./mdoctor clean -m <module>` for all cleanup modules.
