# Development Guide

## Prerequisites

- macOS (any recent version) **or** Debian-based Linux (Ubuntu, Pop!_OS, Mint, etc.)
- Bash 3.2+ (ships with macOS; install via `sudo apt install bash` on Linux)
- Git

No build tools, package managers, or runtimes are required. mdoctor is pure Bash.

## Local Setup

```bash
git clone https://github.com/luongnv89/mdoctor.git
cd mdoctor
chmod +x mdoctor doctor.sh cleanup.sh
```

## Running Locally

```bash
# Run directly without installing
./mdoctor help
./mdoctor check
./mdoctor info

# Or install the symlink
./install.sh
mdoctor help
```

## Test Harness (recommended)

Run the shell regression suite:

```bash
./tests/run.sh
```

The suite is hermetic (Task 0.1) and safe to run on a developer machine:

- each test redirects `HOME` to a temp dir, so filesystem deletions land
  in a sandbox;
- the force path stops after its pre-flight summary when
  `MDOCTOR_PREFLIGHT_ONLY=true` (used by
  `tests/test_force_preflight_resilience.sh`), so `--force` tests assert
  on pre-flight output alone;
- `tests/run.sh` prepends `tests/helpers/bin` to `PATH`, where `docker`,
  `apt-get` and `sudo` stubs record argv to `$MDOCTOR_STUB_LOG` instead
  of reaching a real daemon or the package system.

No git hook runs the suite automatically: the old `pre-push`
`test-suite` hook was removed (Task 0.1). CI runs the full suite from a
clean checkout; developers run it explicitly with the command above.

Current coverage includes:
- command parsing/help behavior
- metadata/list routing checks
- safety validation + whitelist protection
- dry-run vs force cleanup semantics
- interactive cleanup selection behavior

Run shell lint policy (high-severity gate):

```bash
./scripts/lint_shell.sh
```

CI lanes map to local commands:
- **Lint** → `./scripts/lint_shell.sh` + repository `bash -n` syntax pass
- **Test (macOS)** → `./tests/run.sh` + smoke commands (`mdoctor help/version/info/check/clean`)
- **Test (Linux)** → same regression suite + smoke commands on Ubuntu
- **Test (Bash 3.2)** → `bash@sha256:3a13e5da…` container (`image: bash@sha256:` pinned in `ci.yml`) running `./tests/run.sh`
- **Release Sanity** → isolated installer/uninstaller flow using env-overridden temp paths

Optional Bash 3.2 parity check (useful before CI changes):

```bash
docker run --rm -v "$PWD":/repo -w /repo bash@sha256:3a13e5da38baa575985778cd09ce8ac736d4b4dafc91a430e71271f6e5311b89 bash ./tests/run.sh
```

For local installer sanity on non-macOS environments (CI/dev only), use:

```bash
MDOCTOR_SKIP_PLATFORM_CHECK=true \
MDOCTOR_REPO_URL="$PWD" \
MDOCTOR_INSTALL_DIR="$(mktemp -d)/install" \
MDOCTOR_BIN_DIR="$(mktemp -d)" \
./install.sh
```

Run tests in an Ubuntu container (useful for cross-platform validation):

```bash
docker run --rm -v "$PWD":/repo -w /repo ubuntu:latest bash ./tests/run.sh
```

## Testing Individual Modules

You can test a single check or cleanup module in isolation. Available modules vary by platform — run `mdoctor list` to see what's available on your system:

```bash
# Test a specific check
./mdoctor check -m network
./mdoctor check -m disk

# Test a specific cleanup (dry-run)
./mdoctor clean -m trash
./mdoctor clean -m caches --force
```

Or source modules manually:

```bash
source lib/common.sh
source lib/logging.sh
source lib/disk.sh

STEP_CURRENT=0 STEP_TOTAL=1
ACTIONS=() WARN_COUNT=0 FAIL_COUNT=0
LOG_PATHS=() LOG_DESCS=()
REPORT_MD=""

init_colors

source checks/network.sh
check_network
```

## Debugging

Use `bash -x` to trace execution:

```bash
bash -x ./mdoctor check -m disk
```

Or add `set -x` temporarily inside a specific module.

## Code Style

- Shebang: `#!/usr/bin/env bash`
- Error handling: `set -uo pipefail` (add `e` for cleanup scripts)
- Always quote variables: `"$var"`
- Use library functions for output consistency
- One concern per module file
- Functions named `check_*` for checks, `clean_*` for cleanups, `fix_*` for fixes

## Adding New Functionality

See [CONTRIBUTING.md](../CONTRIBUTING.md) for step-by-step guides on adding check modules, cleanup modules, and fix targets.
