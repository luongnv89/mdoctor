# Agent Environment Notes (Pre.1)

Facts about this repo an agent cannot infer from code alone. Canonical
source for the build / test / lint commands also recorded in `CLAUDE.md`.

mdoctor is pure Bash. There is no package manifest (`package.json`,
`Makefile`, `pyproject.toml`, etc.), so there is no `npm test` / `make`
equivalent. The commands below are the complete workflow.

## 1. Build equivalent: `bash -n` syntax sweep

There is no compiler. The build equivalent is a syntax check over every
shell file:

```bash
find . \( -name '*.sh' -o -name 'mdoctor' -o -name 'cleanup.sh' -o -name 'doctor.sh' -o -name 'install.sh' -o -name 'uninstall.sh' \) \
  -not -path './.git/*' \
  -not -path './openspec/*' \
  -exec bash -n {} + && echo BUILD-OK
```

It must report 0 errors.

## 2. Test: safe subset (full runner is destructive until Task 0.1)

The test command of record is:

```bash
./tests/run.sh
```

The suite is hermetic since Task 0.1 (force test stops after its
pre-flight summary via `MDOCTOR_PREFLIGHT_ONLY=true`; `docker`,
`apt-get` and `sudo` are stubbed on `PATH` by `tests/run.sh`), so
`./tests/run.sh` is safe to run on a developer machine. The historical
safe subset (every test file except the force-resilience one) is still
available when you want a quicker signal:
```bash
for f in tests/test_*.sh; do
  case "$f" in
    *test_force_preflight_resilience.sh) echo "SKIP (destructive until 0.1): $f" ;;
    *) echo "== $f =="; bash "$f" ;;
  esac
done
```

## 3. Lint: `scripts/lint_shell.sh` (ShellCheck installed separately)

The real lint entry point is:

```bash
./scripts/lint_shell.sh
```

It runs `shellcheck -S error` over every tracked shell file. ShellCheck
is **not** vendored: `command -v shellcheck` fails on a clean machine.
Install it first:

```bash
# macOS
brew install shellcheck
# Debian/Ubuntu
sudo apt install -y shellcheck
```

Current gate is `-S error` (Task 2.1 raises it to `-S warning`).

## 4. Pre-commit: install the hooks

No tracked document mentioned this step before these notes (F-CI-010).
Install once per checkout:

```bash
pip install pre-commit  # or: brew install pre-commit
pre-commit install
pre-commit install --hook-type pre-push
```

This wires the `bash-syntax` check, the ShellCheck hook, and the
`test-suite` pre-push hook (Task 0.1 re-points the pre-push hook away
from the destructive full suite).

## 5. Bash 3.2 compatibility floor

Target Bash is **3.2** (ships with macOS). The floor is deliberate: this
project ships no Bash of its own, the 3.2 path executes only on macOS
where Apple's vendored Bash 3.2.57 cannot be upgraded by this project,
and raising the floor would break the zero-dependencies promise on the
primary platform. A full-text sweep of all 70 shell files found zero
uses of any Bash 4+ construct. Bash 4+ constructs are banned:

- associative arrays (`declare -A`)
- namerefs (`declare -n`)
- `mapfile` / `readarray`
- `&>>` redirection (use `>>file 2>&1`)
- `globstar` (`**`)
- `[[ ... ]]` regex subtleties beyond 3.2 support; prefer `case`
- `${var,,}` / `${var^^}` case modification
- `read -i`, `read -t 0`-style newer options
- `coproc`
- process substitution edge cases (`<( )` is OK in 3.2 but keep minimal)

Enforced by `./scripts/check_bash32.sh` (the six policy constructs
above are exactly what it greps for; the extra style bullets here are
convention, not grep-enforced). It runs inside
`./scripts/lint_shell.sh`, as a local pre-commit hook, and as a CI
step — see `docs/DEVELOPMENT.md` "Bash 3.2 compatibility floor
(policy)" for the canonical policy.

Parity check (useful before CI changes):

```bash
docker run --rm -v "$PWD":/repo -w /repo bash@sha256:3a13e5da38baa575985778cd09ce8ac736d4b4dafc91a430e71271f6e5311b89 bash ./tests/run.sh
```

## 6. No `.env` surface

There is no `.env` file and no dotenv loading. All configuration is via
environment variables, listed in `mdoctor --help` under "Environment
Variables" (e.g. `DAYS_OLD_OVERRIDE`, `MDOCTOR_DEBUG`). Grep for the
`"${VAR:-default}"` pattern to find every knob; never create or read a
`.env` file.
