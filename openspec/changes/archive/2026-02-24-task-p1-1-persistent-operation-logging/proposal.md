# Proposal: task-p1-1-persistent-operation-logging

## Why
mdoctor currently logs to transient or command-local logs. We need durable operation traces with run boundaries and per-action records for debugging and auditability.

## Scope
- In scope:
  - Add persistent operation log file at `~/.config/mdoctor/operations.log`.
  - Add operation session lifecycle (`start` / `end`) with duration and counters.
  - Record key operation events from command execution and safety deletion helpers.
  - Wire session lifecycle into `mdoctor clean` execution paths.
- Out of scope:
  - Rich log query command/UI.
  - Rotation policy tuning beyond lightweight defaults.

## Acceptance Criteria
- [x] Operation log file is created automatically when mdoctor cleanup runs.
- [x] Each cleanup run writes a session start and session end summary.
- [x] Action records are appended during operation execution.
- [x] Error records are captured with category + target.
- [x] Dry-run module and full cleanup still work.

## Risks
- Too much logging noise.
  - Mitigation: only record operation-level events (not every stdout line).
