# CLAUDE.md

@AGENTS.md

Claude-specific project context for mdoctor (pure-Bash macOS/Linux
system-health tool). Full agent-environment rationale lives in
`docs/AGENT_ENVIRONMENT.md`; this file keeps the commands Claude needs
every session.

## Build

No compiler, no manifest. Build equivalent is the `bash -n` sweep (must
report 0 errors):

```bash
find . \( -name '*.sh' -o -name 'mdoctor' -o -name 'cleanup.sh' -o -name 'doctor.sh' -o -name 'install.sh' -o -name 'uninstall.sh' \) \
  -not -path './.git/*' \
  -not -path './.specify/*' \
  -not -path './openspec/*' \
  -exec bash -n {} + && echo BUILD-OK
```

## Test

Command of record: `./tests/run.sh` (runs all `tests/test_*.sh`, must
pass 9/9 once Task 0.1 lands).

**Destructive until Task 0.1:** the full runner executes
`tests/test_force_preflight_resilience.sh`, which runs
`./cleanup.sh --force`. The `HOME` sandbox in that test does NOT cover
`docker system prune -af --volumes` or `sudo apt-get autoremove -y` —
never run the full suite on a real machine until 0.1. Until then, run
the safe subset only:

```bash
for f in tests/test_*.sh; do
  case "$f" in
    *test_force_preflight_resilience.sh) echo "SKIP (destructive until 0.1): $f" ;;
    *) echo "== $f =="; bash "$f" ;;
  esac
done
```

## Lint

```bash
./scripts/lint_shell.sh
```

Runs `shellcheck -S error` over every tracked shell file. ShellCheck is
not vendored — install first (`brew install shellcheck` on macOS,
`sudo apt install -y shellcheck` on Debian/Ubuntu). Gate rises to
`-S warning` under Task 2.1.

Also run once per checkout: `pre-commit install` (plus
`pre-commit install --hook-type pre-push`).

## Bash 3.2 floor

Target Bash is **3.2** (macOS system Bash). Bash 4+ constructs are
**banned**: `declare -A`, `mapfile`/`readarray`, `&>>`, `globstar`
(`**`), `${var,,}`/`${var^^}`, newer `read` options. See
`docs/AGENT_ENVIRONMENT.md` for the full banned list and the
`bash:3.2` docker parity check.

## Config surface

No `.env` file exists and none is loaded. All knobs are environment
variables (`mdoctor --help` → "Environment Variables", e.g.
`DAYS_OLD_OVERRIDE`, `MDOCTOR_DEBUG`).
