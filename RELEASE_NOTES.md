## v3.0.0 — Machine Doctor: Cross-Platform Release

mdoctor is now **Machine Doctor** — no longer macOS-only. This release adds full support for Debian-based Linux (Ubuntu, Pop!_OS, Mint, Raspbian, and more), a comprehensive end-to-end test suite, and a hardened CI pipeline.

### Features
- **Linux (Debian/Ubuntu) cross-platform support** — platform detection layer (`lib/platform.sh`), platform-aware paths, and conditional module loading across all engines (`4788678`)
- New Linux-specific modules: `checks/apt.sh`, `cleanups/apt.sh`, `fixes/apt.sh`
- Platform-aware health checks: `system`, `disk`, `updates`, `security`, `startup`, `network`, `performance`, `storage`, `devtools`, `apps` all adapted for Linux
- Platform-aware cleanup modules: `trash`, `caches`, `logs`, `downloads`, `browser`, `dev`, `crash_reports`, `dev_caches` all adapted for Linux paths
- Installer now supports Debian-family distros with auto-detection via `/etc/os-release`
- Rebranded from "System Doctor" to **"Machine Doctor"** to reflect cross-platform scope

### Testing
- End-to-end safe mode test (`test_e2e_safe_mode.sh`) — 25+ assertions exercising every safe CLI command with timeout guards (`0421d20`)
- All existing tests made cross-platform: platform-aware trash paths, conditional module assertions (`e547e1d`)

### CI/CD
- New **Test (Linux/Ubuntu)** CI job on `ubuntu-latest` with timeout guards (`12c7540`)
- New **Test (Bash 3.2 compat)** CI job via Docker (`91e4405`)
- Pre-commit hooks enhanced: shellcheck severity aligned to project policy, `bash -n` syntax check, test suite on `pre-push` (`91e4405`)
- Fixed CI hangs on Linux runners caused by `docker info`/`nslookup` in minimal environments (`ba44f60`)
- Executable permissions fixed on 7 files with shebangs

### Documentation
- README: updated tagline, platform badges, cross-platform module tables, Linux install instructions, project structure
- ARCHITECTURE: new Platform Abstraction section documenting `lib/platform.sh` globals and predicates
- DEVELOPMENT: Linux prerequisites, Ubuntu Docker testing, updated CI lane descriptions
- DEPLOYMENT: documented platform detection and distro whitelist
- SAFETY: cross-platform paths table, Linux-specific limitations (SELinux/AppArmor)
- CHANGELOG: Linux support milestones added to [Unreleased]

### Bug Fixes
- Bash 3.2 empty-array edge cases in `lib/safety.sh` whitelist matching and `mdoctor clean` dispatch (`875fc6e`, `e98b328`)
- Shell lint script made Bash 3.2 compatible (`31b2c84`)
- Test harness portability fixes for macOS temp directory handling (`501a556`, `3f0c5b9`)

### Stats
- **60 files changed**, +2,295 / -678 lines
- **6 regression tests** (up from 5), all passing on macOS, Linux, and Bash 3.2
- **5 CI jobs**: Lint, Test (macOS), Test (Linux), Test (Bash 3.2), Release Sanity

**Full Changelog**: https://github.com/luongnv89/mdoctor/compare/v2.1.0...v3.0.0
