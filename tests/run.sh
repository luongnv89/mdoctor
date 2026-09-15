#!/usr/bin/env bash
#
# tests/run.sh — the suite entry point (Task 6.2): delegates to bats-core
# for per-assertion reporting, a named filter, JUnit output for CI and a
# per-file watchdog so a hanging test fails instead of blocking the run.
#
# Usage: ./tests/run.sh [-f PATTERN] [--shard I/N] [--list] [file.bats ...]
#   -f PATTERN    only run tests whose name matches the extended regex
#   --shard I/N   run only shard I of N (1-based; files split round-robin
#                 over the resolved list — issue #206, the macOS CI legs)
#   --list        print the resolved .bats file list and exit (runs nothing)
#   files...      run only these .bats files (default: tests/*.bats)
#
# The runner self-provisions bats-core at a pinned SHA into the user cache
# on first use (no vendored dependency; MDOCTOR_BATS_BIN overrides the
# lookup for offline/CI-pinned environments).

# Errexit posture (issue #113): intentionally NO `set -e` — the runner
# aggregates per-file failures into the summary; aborting on the first
# non-zero rc would hide every later file's result. See CONTRIBUTING.md
# "Errexit posture".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BATS_SHA="7868b95ea08b22bc76f2585e51cf4b7b3ff124ef" # bats-core v1.14.0
BATS_REPO="https://github.com/bats-core/bats-core.git"
FILE_TIMEOUT="${MDOCTOR_TEST_FILE_TIMEOUT:-600}"

# Hermetic suite (Task 0.1): shadow `docker`, `apt-get` and `sudo` with
# stubs that record argv instead of reaching a real daemon or the package
# system, so no test file can destroy external state. Individual tests may
# set MDOCTOR_STUB_LOG to a file to assert on intercepted invocations.
export PATH="$SCRIPT_DIR/helpers/bin:$PATH"

# Shared home-scoped fixture root (issue #73): every test sandbox is a
# `mktemp -d` under this root (see tests/helpers/fixture.bash) — never a
# bare $HOME child, never the repo tree, never $TMPDIR. MDOCTOR_RUN_ID
# gives this run a sweepable prefix; ad-hoc `bats` runs without run.sh
# fall back to an adhoc-<pid> id inside the helper.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/helpers/fixture.bash"
MDOCTOR_FIXTURE_ROOT="${MDOCTOR_FIXTURE_ROOT:-${HOME}/.mdoctor-test-fixtures}"
export MDOCTOR_FIXTURE_ROOT
MDOCTOR_FIXTURE_RUN_ID="${MDOCTOR_FIXTURE_RUN_ID:-run-$$-$(date +%s)}"
export MDOCTOR_FIXTURE_RUN_ID
mkdir -p "$MDOCTOR_FIXTURE_ROOT" || exit 1
# Startup sweep: remove stale fixture dirs from runs no trap could catch
# (e.g. kill -9); the EXIT/INT/TERM traps below cover this run's own dirs.
fixture_sweep_stale 1440 || true

_mdoctor_run_cleanup() {
  fixture_sweep_run || true
  fixture_sweep_stale 1440 || true
}
_mdoctor_run_signal() {
  # _MDOCTOR_CHILD is only set while a per-file bats run is in flight;
  # killing it first lets the trap fire promptly (bash would otherwise
  # keep waiting on the foreground child) and the child's own INT/TERM
  # trap cleans its file sandbox before our sweep runs.
  if [ -n "${_MDOCTOR_CHILD:-}" ]; then
    kill -TERM "$_MDOCTOR_CHILD" 2>/dev/null || true
  fi
  _mdoctor_run_cleanup
  exit "$1"
}
trap '_mdoctor_run_signal 130' INT
trap '_mdoctor_run_signal 143' TERM
# The EXIT trap is installed after RESULT_DIR exists (single EXIT
# registration — a second `trap ... EXIT` would replace this chain).

FILTER=""
SHARD=""
LIST_ONLY=0
FILES=()
_MDOCTOR_CHILD=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--filter)
      FILTER="${2-}"
      shift 2
      ;;
    --shard)
      SHARD="${2-}"
      shift 2
      ;;
    --shard=*)
      SHARD="${1#*=}"
      shift
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

# --- Collect test files ----------------------------------------------------
if [ "${#FILES[@]}" -eq 0 ]; then
  shopt -s nullglob
  FILES=("$SCRIPT_DIR"/test_*.bats)
  shopt -u nullglob
fi

# --- Shard selection (issue #206) -------------------------------------------
# `--shard I/N` keeps only the files whose 1-based position p in the resolved
# list satisfies (p - I) % N == 0 — round-robin over the sorted glob (or the
# caller's explicit list), so each of the N parallel CI legs runs ~1/N of the
# suite and files added later distribute themselves without a manifest.
if [ -n "$SHARD" ]; then
  case "$SHARD" in
    */*) ;;
    *)
      echo "Invalid --shard spec '$SHARD' (expected I/N, 1 <= I <= N)" >&2
      exit 2
      ;;
  esac
  shard_i="${SHARD%/*}"
  shard_n="${SHARD#*/}"
  case "$shard_i" in ''|*[!0-9]*)
    echo "Invalid --shard spec '$SHARD' (I must be a number)" >&2
    exit 2
    ;;
  esac
  case "$shard_n" in ''|*[!0-9]*)
    echo "Invalid --shard spec '$SHARD' (N must be a number)" >&2
    exit 2
    ;;
  esac
  if [ "$shard_n" -lt 1 ] || [ "$shard_i" -lt 1 ] || [ "$shard_i" -gt "$shard_n" ]; then
    echo "Invalid --shard spec '$SHARD' (expected 1 <= I <= N)" >&2
    exit 2
  fi
  _sharded=()
  _pos=0
  for _f in ${FILES[@]+"${FILES[@]}"}; do
    _pos=$((_pos + 1))
    if [ $(( (_pos - shard_i) % shard_n )) -eq 0 ]; then
      _sharded+=("$_f")
    fi
  done
  FILES=(${_sharded[@]+"${_sharded[@]}"})
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No test files found in $SCRIPT_DIR"
  exit 1
fi

# --list resolves the file list (default glob + shard) without provisioning
# or running bats — the CI legs and tests assert the partition from this.
if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s\n' "${FILES[@]}"
  exit 0
fi

# --- Locate or provision bats-core (pinned) -------------------------------
if [ -n "${MDOCTOR_BATS_BIN:-}" ] && [ -x "${MDOCTOR_BATS_BIN:-}" ]; then
  BATS_BIN="$MDOCTOR_BATS_BIN"
elif command -v bats >/dev/null 2>&1; then
  BATS_BIN="$(command -v bats)"
else
  BATS_HOME="${MDOCTOR_BATS_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/mdoctor/bats-$BATS_SHA}"
  if [ ! -x "$BATS_HOME/bin/bats" ]; then
    echo "Provisioning bats-core v1.14.0 ($BATS_SHA) into $BATS_HOME ..." >&2
    mkdir -p "$(dirname "$BATS_HOME")" || exit 1
    if [ -d "$BATS_HOME" ]; then
      rm -rf "$BATS_HOME"
    fi
    if ! git clone --quiet --filter=blob:none "$BATS_REPO" "$BATS_HOME" 2>&1; then
      echo "ERROR: could not provision bats-core (network clone failed)." >&2
      echo "       Install bats-core manually or set MDOCTOR_BATS_BIN." >&2
      exit 1
    fi
    git -C "$BATS_HOME" checkout --quiet "$BATS_SHA" || exit 1
  fi
  BATS_BIN="$BATS_HOME/bin/bats"
fi

RESULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mdoctor-bats-results.XXXXXX")"
trap '_mdoctor_run_cleanup; rm -rf "$RESULT_DIR"' EXIT

pass_count=0
fail_count=0
junit_written=0

for test_file in "${FILES[@]}"; do
  echo
  echo "== Running $(basename "$test_file") =="

  # Named-filter pre-gate: a filter that matches nothing in this file must
  # not execute the file at all (bats loads setup_file only for files with
  # matching tests, but a 0-count run would still exit non-zero).
  if [ -n "$FILTER" ]; then
    n="$("$BATS_BIN" -c --filter "$FILTER" "$test_file" 2>/dev/null || echo 0)"
    if [ "$n" -eq 0 ]; then
      echo "   (no tests match filter; skipping file)"
      continue
    fi
  fi

  # Per-file watchdog: a deliberately hanging test fails within the
  # timeout instead of blocking the run. (ponytail: per-FILE watchdog,
  # not per-test — bats-core has no native per-test timeout; upgrade when
  # bats ships one or a per-test watchdog helper is added.)
  rc=0
  # Pretty formatter uses tput; CI runs without $TERM — fall back to TAP.
  local_fmt=pretty
  [ -t 1 ] || local_fmt=tap
  BATS_ARGS=(--formatter "$local_fmt" --report-formatter junit --output "$RESULT_DIR" --print-output-on-failure)
  [ -n "$FILTER" ] && BATS_ARGS+=(--filter "$FILTER")
  # Background + wait (not a plain foreground exec) so a trapped INT/TERM
  # interrupts this script immediately instead of after the child exits:
  # the signal trap kills _MDOCTOR_CHILD, sweeps this run's fixture dirs
  # and exits, leaving nothing behind (issue #73).
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FILE_TIMEOUT" "$BATS_BIN" "${BATS_ARGS[@]}" "$test_file" & _MDOCTOR_CHILD=$!
  else
    "$BATS_BIN" "${BATS_ARGS[@]}" "$test_file" & _MDOCTOR_CHILD=$!
  fi
  wait "$_MDOCTOR_CHILD" || rc=$?
  _MDOCTOR_CHILD=""

  if [ "$rc" -eq 0 ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "   (file failed with rc=$rc)"
  fi
  if [ -f "$RESULT_DIR/report.xml" ]; then
    mv "$RESULT_DIR/report.xml" "$RESULT_DIR/junit-$(basename "$test_file" .bats).xml"
    junit_written=$((junit_written + 1))
  fi
done

# --- Merge per-file JUnit XML into one CI-consumable report ---------------
if [ "$junit_written" -gt 0 ]; then
  mkdir -p "$ROOT_DIR/test-results"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<testsuites>'
    cat "$RESULT_DIR"/junit-*.xml | grep -v '^<?xml' | grep -v '^<testsuites' | grep -v '^</testsuites>'
    echo '</testsuites>'
  } > "$ROOT_DIR/test-results/junit.xml"
  echo
  echo "JUnit report: test-results/junit.xml"
fi

echo
printf "Test summary: %d file(s) passed, %d file(s) failed\n" "$pass_count" "$fail_count"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
