# Proposal: task-p3-2-shellcheck-baseline-policy

## Why
We need a stable ShellCheck baseline and explicit lint policy to prevent high-severity shell regressions and keep CI enforcement consistent.

## Scope
- In scope:
  - Add project `.shellcheckrc` baseline policy.
  - Add reusable lint script for shell files.
  - Enforce high-severity shellcheck checks in CI via the lint script.
  - Verify high-severity lint is clean.
- Out of scope:
  - Fix every warning-level style issue in one pass.
  - Full CI job split redesign (P3.3).

## Acceptance Criteria
- [x] `.shellcheckrc` exists with project baseline policy.
- [x] `scripts/lint_shell.sh` runs shellcheck consistently across repo shell files.
- [x] CI shellcheck job uses the lint script.
- [x] Local high-severity shellcheck run passes.

## Risks
- CI/runtime drift if lint file selection differs across environments.
  - Mitigation: single lint script used both locally and in CI.
