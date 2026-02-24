# mdoctor × Mole Comparison — Implementation Plan (OpenSpec-driven)

Goal: improve mdoctor using proven patterns from Mole without losing mdoctor's simpler health-first UX.

Execution rule: one task at a time via OpenSpec change folders under `openspec/changes/`.

## Phase P0 — Safety Foundation (critical)

### P0.1 Safe command execution core
- Status: ✅ Done (change: `task-p0-1-safe-command-runner`)
- Replace string+`eval` command execution with safer command runner primitives.
- Add explicit handling for dry-run, stderr reporting, and non-zero exit propagation.
- **Outcome:** no core cleanup path depends on `eval`.

### P0.2 Safe deletion primitives
- Status: ✅ Done (change: `task-p0-2-safe-deletion-primitives`)
- Add centralized safe deletion APIs (`safe_remove`, `safe_find_delete` style helpers).
- Enforce path validation (absolute paths, traversal guard, protected paths, symlink handling).
- **Outcome:** destructive operations have a single safety gate.

### P0.3 Cleanup module migration to safety APIs
- Status: ✅ Done (change: `task-p0-3-cleanup-module-safety-migration`)
- Refactor all `cleanups/*.sh` to use safety APIs.
- Remove direct `rm -rf` / risky inline find-delete usage from modules.
- **Outcome:** consistent behavior and fewer foot-guns.

### P0.4 Error taxonomy for destructive failures
- Status: ✅ Done (change: `task-p0-4-destructive-error-taxonomy`)
- Standardize error codes/categories (permission denied, SIP/readonly, invalid target, runtime failure).
- Surface actionable messages in CLI output.
- **Outcome:** faster triage and safer retries.

## Phase P1 — Reliability & Operability

### P1.1 Persistent operation logging
- Status: ✅ Done (change: `task-p1-1-persistent-operation-logging`)
- Add `~/.config/mdoctor/operations.log` with per-run start/end summary and action records.
- **Outcome:** post-mortem traceability.

### P1.2 Debug mode
- Status: ✅ Done (change: `task-p1-2-debug-mode-structured-diagnostics`)
- Introduce `--debug` for cleanup/fix/check commands with structured diagnostics.
- **Outcome:** easier support and reproducibility.

### P1.3 Pre-flight safety summary
- Status: ✅ Done (change: `task-p1-3-preflight-safety-summary`)
- Before destructive runs (`--force`), show what will be touched + estimated reclaim size.
- **Outcome:** explicit operator confirmation context.

## Phase P2 — Safe User Controls

### P2.1 Cleanup whitelist
- Status: ✅ Done (change: `task-p2-1-cleanup-whitelist`)
- Add user whitelist config to protect paths from cleanup.
- **Outcome:** avoid accidental deletion of valuable caches/models.

### P2.2 Custom cleanup scope configuration
- Status: ✅ Done (change: `task-p2-2-custom-cleanup-scope-config`)
- Add configurable scan paths/include-exclude patterns.
- **Outcome:** safer use in varied dev environments.

## Phase P3 — Quality Gates

### P3.1 Shell test harness
- Status: ✅ Done (change: `task-p3-1-shell-test-harness`)
- Add tests for command parsing, metadata routing, safety validation, and dry-run semantics.
- **Outcome:** prevent regressions in critical paths.

### P3.2 Shellcheck baseline + policy
- Status: ✅ Done (change: `task-p3-2-shellcheck-baseline-policy`)
- Add `.shellcheckrc`; clean high-severity lint; enforce in CI.
- **Outcome:** maintainable shell quality.

### P3.3 CI expansion
- Status: ✅ Done (change: `task-p3-3-ci-expansion`)
- Split CI into lint/test/release-sanity jobs.
- **Outcome:** faster feedback and clearer failures.

## Phase P4 — Product Polish

### P4.1 Update command
- Status: ✅ Done (change: `task-p4-1-update-command`)
- Add `mdoctor update` (stable channel first; nightly optional later).
- **Outcome:** easier upgrades.

### P4.2 Optional interactive cleanup mode
- Status: ✅ Done (change: `task-p4-2-interactive-cleanup-mode`)
- Add optional interactive selection mode for cleanup targets.
- **Outcome:** safer manual operation for non-expert users.

### P4.3 Safety and recovery docs
- Status: ✅ Done (change: `task-p4-3-safety-recovery-docs`)
- Improve docs on safety model, reversibility, and known limitations.
- **Outcome:** better trust and onboarding.

## Delivery order
1. P0 (mandatory before broad feature work)
2. P1
3. P2
4. P3
5. P4

## Tracking
- Mark task complete only after: code + validation + OpenSpec archive.
- Keep each change atomic to one task ID.

## Archive Log
- 2026-02-24 archived `task-p0-1-safe-command-runner` for `P0.1`
  - Outcome: removed `eval` from shared command runner and introduced explicit safe/legacy runner functions.
  - Spec impact: `openspec/specs/command-execution-safety/spec.md`.
  - Verification: `./mdoctor clean --help`, `./mdoctor clean`, `./mdoctor clean -m trash`.

- 2026-02-24 archived `task-p0-2-safe-deletion-primitives` for `P0.2`
  - Outcome: added `lib/safety.sh` with `validate_deletion_path`, `safe_remove`, `safe_remove_children`, and `safe_find_delete`.
  - Spec impact: `openspec/specs/deletion-safety-primitives/spec.md`.
  - Verification: syntax checks + temp-path smoke tests + `./mdoctor clean --help` + `./mdoctor clean -m trash`.

- 2026-02-24 archived `task-p0-3-cleanup-module-safety-migration` for `P0.3`
  - Outcome: migrated all `cleanups/*.sh` destructive paths to safety primitives and removed inline destructive patterns.
  - Spec impact: `openspec/specs/cleanup-safety-migration/spec.md`.
  - Verification: static grep checks + `bash -n` + dry-run smoke for all cleanup modules.

- 2026-02-24 archived `task-p0-4-destructive-error-taxonomy` for `P0.4`
  - Outcome: introduced standardized destructive error taxonomy + actionable hint logging and improved runtime failure handling in `safe_find_delete`.
  - Spec impact: `openspec/specs/destructive-error-taxonomy/spec.md`.
  - Verification: syntax checks + representative taxonomy smoke tests + `./mdoctor clean -m trash`.

- 2026-02-24 archived `task-p1-1-persistent-operation-logging` for `P1.1`
  - Outcome: added persistent `~/.config/mdoctor/operations.log` with session start/end summaries and action/error records.
  - Spec impact: `openspec/specs/persistent-operation-logging/spec.md`.
  - Verification: `./mdoctor clean -m trash`, `./mdoctor clean`, and log content checks.

- 2026-02-24 archived `task-p1-2-debug-mode-structured-diagnostics` for `P1.2`
  - Outcome: added `--debug` support for check/clean/fix and structured debug diagnostics across runners and runtime flows.
  - Spec impact: `openspec/specs/debug-mode-diagnostics/spec.md`.
  - Verification: `mdoctor check --debug -m battery`, `mdoctor clean --debug -m trash`, `mdoctor clean --debug`, `mdoctor fix --debug`.

- 2026-02-24 archived `task-p1-3-preflight-safety-summary` for `P1.3`
  - Outcome: added force-mode pre-flight safety summaries for module and full cleanup runs, including touched targets and estimated reclaim size.
  - Spec impact: `openspec/specs/preflight-safety-summary/spec.md`.
  - Verification: isolated-home force tests for `mdoctor clean --force -m trash` and `cleanup.sh --force --debug`, plus non-force behavior check.

- 2026-02-24 archived `task-p2-1-cleanup-whitelist` for `P2.1`
  - Outcome: added cleanup whitelist support with auto-created `~/.config/mdoctor/cleanup_whitelist`, path/subtree matching, and skip-on-whitelist behavior.
  - Spec impact: `openspec/specs/cleanup-whitelist/spec.md`.
  - Verification: isolated-home whitelist protect/delete/autocreate tests + `mdoctor clean --help` check.

- 2026-02-24 archived `task-p2-2-custom-cleanup-scope-config` for `P2.2`
  - Outcome: added configurable cleanup scope (`~/.config/mdoctor/cleanup_scope.conf`) with include paths and exclude globs for stale node_modules scanning.
  - Spec impact: `openspec/specs/custom-cleanup-scope/spec.md`.
  - Verification: isolated-home include/exclude/default fallback/autocreate tests + help text check.

- 2026-02-24 archived `task-p3-1-shell-test-harness` for `P3.1`
  - Outcome: added shell test harness (`tests/run.sh`) with regression tests for command parsing, metadata routing, safety validation/whitelist, and dry-run semantics.
  - Spec impact: `openspec/specs/shell-test-harness/spec.md`.
  - Verification: `./tests/run.sh` (4/4 tests passed).

- 2026-02-24 archived `task-p3-2-shellcheck-baseline-policy` for `P3.2`
  - Outcome: added `.shellcheckrc` baseline policy, reusable `scripts/lint_shell.sh`, and CI enforcement via shared lint entrypoint.
  - Spec impact: `openspec/specs/shellcheck-baseline-policy/spec.md`.
  - Verification: `./scripts/lint_shell.sh` passed with high-severity gate.

- 2026-02-24 archived `task-p3-3-ci-expansion` for `P3.3`
  - Outcome: split CI into lint/test/release-sanity lanes, added regression harness execution in CI, and added isolated installer/uninstaller sanity flow.
  - Spec impact: `openspec/specs/ci-expansion/spec.md`.
  - Verification: `./scripts/lint_shell.sh`, `./tests/run.sh`, and isolated install/uninstall smoke with env overrides.

- 2026-02-24 archived `task-p4-1-update-command` for `P4.1`
  - Outcome: added `mdoctor update` command (stable channel), check mode, and git-based fast-forward update flow with clear fallback messaging.
  - Spec impact: `openspec/specs/update-command/spec.md`.
  - Verification: `bash -n mdoctor`, `./mdoctor update --help`, `./mdoctor update --check`, `./scripts/lint_shell.sh`, `./tests/run.sh`.

- 2026-02-24 archived `task-p4-2-interactive-cleanup-mode` for `P4.2`
  - Outcome: added interactive cleanup selection (`mdoctor clean --interactive`) with numeric/all picks, validation, and per-module execution preserving dry-run/force behavior.
  - Spec impact: `openspec/specs/interactive-cleanup-mode/spec.md`.
  - Verification: `bash -n mdoctor tests/test_interactive_cleanup.sh`, `./scripts/lint_shell.sh`, `./tests/run.sh`.

- 2026-02-24 archived `task-p4-3-safety-recovery-docs` for `P4.3`
  - Outcome: added dedicated safety/recovery guide (`docs/SAFETY.md`) and linked it from README + guidebook for better operator trust and incident handling.
  - Spec impact: `openspec/specs/safety-recovery-docs/spec.md`.
  - Verification: docs link/path consistency checks + `./mdoctor clean --help`, `./mdoctor update --help`, `./scripts/lint_shell.sh`, `./tests/run.sh`.
