# Proposal: task-p3-3-ci-expansion

## Why
The CI pipeline currently verifies shell scripts but does not clearly separate lint, regression tests, and release-sanity checks. Splitting these concerns improves signal quality and shortens triage time.

## Scope
- In scope:
  - Restructure CI into explicit `lint`, `test`, and `release-sanity` jobs.
  - Use shared local scripts for parity (`scripts/lint_shell.sh`, `tests/run.sh`).
  - Add release-sanity checks that validate installer/uninstaller flow in isolated paths.
  - Add minimal env overrides in install/uninstall scripts to enable isolated CI install paths.
- Out of scope:
  - Cross-platform matrix expansion beyond macOS.
  - Packaging/signing/release publishing automation.

## Acceptance Criteria
- [x] CI workflow contains separate jobs for lint, test, and release-sanity.
- [x] Test job runs shell regression harness.
- [x] Release-sanity job validates install/uninstall in isolated temp paths.
- [x] Installer/uninstaller support env overrides required by CI isolated paths.
- [x] Local syntax + regression checks pass after CI changes.

## Risks
- Installer changes could alter user-facing behavior.
  - Mitigation: keep defaults unchanged; only add optional env overrides.
