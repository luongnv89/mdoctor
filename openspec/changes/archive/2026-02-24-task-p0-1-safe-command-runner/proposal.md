# Proposal: task-p0-1-safe-command-runner

## Why
mdoctor currently routes cleanup commands through a string+`eval` path. Even when inputs are mostly internal, this design is fragile and raises risk for unsafe argument expansion or accidental command execution edge cases.

## Scope
- In scope:
  - Replace `eval`-based command execution in shared logging helper with safer command runner APIs.
  - Keep dry-run behavior unchanged from user perspective.
  - Introduce explicit command execution contract for future cleanup/fix modules.
- Out of scope:
  - Full migration of every cleanup module to deletion safety wrappers (covered in P0.2/P0.3).
  - UI/UX redesign.

## Acceptance Criteria
- [x] Core command runner no longer uses `eval`.
- [x] Existing cleanup command invocations continue to work (dry-run and force mode).
- [x] Non-zero command exits are surfaced and logged consistently.
- [x] CLI help/docs updated if invocation contract changes (no user-facing command contract change required in this task).

## Risks
- Breaking existing command strings in cleanup modules.
  - Mitigation: introduce backward-compatible wrapper (`run_cmd_legacy`) and migrate incrementally.
