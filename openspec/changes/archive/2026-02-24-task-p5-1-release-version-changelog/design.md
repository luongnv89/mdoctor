# Design: task-p5-1-release-version-changelog

## Approach
1. Update `MDOCTOR_VERSION` from `2.0.0` to `2.1.0`.
2. Add `2.1.0` changelog entry (dated 2026-02-24) summarizing:
   - safety foundation + taxonomy
   - logging/debug/preflight
   - whitelist/scope controls
   - test harness + shellcheck policy + CI split
   - update command + interactive cleanup + safety docs
3. Update `openspec/tasks.md` with a small P5 release-readiness section and completion record.
4. Validate with:
   - `bash -n mdoctor`
   - `./mdoctor version`
   - `./scripts/lint_shell.sh`
   - `./tests/run.sh`
