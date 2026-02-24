# Design: task-p3-3-ci-expansion

## Approach
1. CI workflow restructure
   - `lint` job: shellcheck policy script + bash syntax checks.
   - `test` job: `./tests/run.sh` + core command smoke checks.
   - `release-sanity` job: run installer/uninstaller against temp install/bin paths.

2. Installer/uninstaller env overrides
   - `install.sh`: allow `MDOCTOR_REPO_URL`, `MDOCTOR_INSTALL_DIR`, `MDOCTOR_BIN_DIR`, `MDOCTOR_BINARY_NAME`.
   - `uninstall.sh`: allow `MDOCTOR_INSTALL_DIR`, `MDOCTOR_BIN_LINK`.
   - Keep defaults equal to current behavior.

3. Development docs update
   - Document CI lanes and local commands that map to lint/test checks.

## Files Affected
- `.github/workflows/ci.yml`
- `install.sh`
- `uninstall.sh`
- `docs/DEVELOPMENT.md`

## Validation Plan
- `bash -n install.sh uninstall.sh .github/workflows/ci.yml`
- `./scripts/lint_shell.sh`
- `./tests/run.sh`
- local isolated install/uninstall smoke using env overrides.
