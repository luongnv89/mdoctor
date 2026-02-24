# Proposal: task-p1-2-debug-mode-structured-diagnostics

## Why
mdoctor lacked a consistent debug mode across check/clean/fix commands, making troubleshooting slower when a command failed or behaved unexpectedly.

## Scope
- In scope:
  - Add `--debug` option to `check`, `clean`, and `fix` command flows.
  - Add structured debug logging primitives and command-runner instrumentation.
  - Propagate debug mode into full cleanup and full doctor execution paths.
- Out of scope:
  - Log viewer command.
  - Remote telemetry.

## Acceptance Criteria
- [x] `mdoctor check --debug` works for module and full-run paths.
- [x] `mdoctor clean --debug` works for module and full-run paths.
- [x] `mdoctor fix --debug` is accepted and emits structured diagnostics.
- [x] Debug logs include structured `[DEBUG]` lines.
- [x] Existing non-debug behavior remains unchanged.

## Risks
- More verbose output in debug mode.
  - Mitigation: debug output only when explicitly enabled.
