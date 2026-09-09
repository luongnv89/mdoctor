#!/usr/bin/env bash
#
# tests/helpers/fixture.bash
# Shared home-scoped fixture root (issue #73, F-TEST-012/013/017).
#
# Every test sandbox lives under one home-scoped root
# (${MDOCTOR_FIXTURE_ROOT:-$HOME/.mdoctor-test-fixtures}) and is created
# with `mktemp -d` — never as a bare $HOME child, never inside the repo
# working tree, and never under $TMPDIR (on macOS TMPDIR canonicalizes to
# /var/folders/..., which the protected-path policy in lib/safety.sh
# rejects, so a TMPDIR sandbox could never be force-cleaned there).
#
# Usage from a .bats setup_file:
#   load 'helpers/fixture'
#   FIXTURE_ROOT="$(fixture_root)"
#   TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-<lane>.$(fixture_run_id).XXXXXX")"
#   fixture_trap_cleanup "$TEST_TMP"
# teardown_file keeps its plain `rm -rf` (the normal path). The INT/TERM
# trap covers interrupted runs — an EXIT-only trap is not enough because
# bash does not run EXIT handlers for an untrapped SIGTERM, which is
# exactly how CI timeout wrappers kill. (EXIT itself is deliberately left
# to bats' own teardown chain plus tests/run.sh's EXIT trap: replacing
# bats' EXIT handler would skip teardown_file entirely.) A startup sweep
# removes stale run directories left by kills no trap could catch.
#
# tests/run.sh exports MDOCTOR_FIXTURE_ROOT and MDOCTOR_FIXTURE_RUN_ID
# (run-<pid>-<epoch>) so every file in a run shares one sweepable prefix;
# ad-hoc `bats` invocations fall back to an adhoc-<pid> run id so
# concurrent runs never share a prefix.
#
# Bash 3.2 compatible: indexed arrays and while-read loops only, no [[ =~ ]].

# Per-process dir registered via fixture_trap_cleanup (one registration
# per setup_file is the convention).
_FIXTURE_TRAP_DIR=""

# fixture_root — print the shared root, creating it first. Also sweeps
# stale run directories so every setup_file backstops interrupted runs,
# not just tests/run.sh startup.
fixture_root() {
  local root="${MDOCTOR_FIXTURE_ROOT:-${HOME}/.mdoctor-test-fixtures}"
  mkdir -p "$root" || return 1
  fixture_sweep_stale 1440 || true
  printf '%s\n' "$root"
}

# fixture_run_id — the current run's sweepable id segment.
fixture_run_id() {
  printf '%s\n' "${MDOCTOR_FIXTURE_RUN_ID:-adhoc-$$}"
}

# fixture_sweep_stale [MAX_AGE_MIN] — remove abandoned fixture dirs older
# than MAX_AGE_MIN minutes (default 1440, i.e. one day). Matches only our
# own mdoctor-test-* prefix at depth 1; the root itself is never removed.
fixture_sweep_stale() {
  local root="${MDOCTOR_FIXTURE_ROOT:-${HOME}/.mdoctor-test-fixtures}"
  local max_age="${1:-1440}"
  [ -d "$root" ] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -name 'mdoctor-test-*' -mmin +"$max_age" -exec rm -rf {} + 2>/dev/null || true
}

# fixture_sweep_run — remove this run's fixture dirs. The run-id segment
# makes the prefix precise, so concurrent runs are never touched. Called
# by tests/run.sh traps (EXIT/INT/TERM) and safe to call repeatedly.
fixture_sweep_run() {
  local root="${MDOCTOR_FIXTURE_ROOT:-${HOME}/.mdoctor-test-fixtures}"
  local run_id
  run_id="$(fixture_run_id)"
  [ -d "$root" ] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -name "mdoctor-test-*.${run_id}.*" -exec rm -rf {} + 2>/dev/null || true
}

# _fixture_cleanup_fire — remove the registered dir, if it still exists.
_fixture_cleanup_fire() {
  if [ -n "$_FIXTURE_TRAP_DIR" ] && [ -e "$_FIXTURE_TRAP_DIR" ]; then
    rm -rf "$_FIXTURE_TRAP_DIR"
  fi
  return 0
}

# fixture_trap_cleanup DIR — remove DIR on INT and TERM (in addition to
# the EXIT-path cleanup that teardown_file and tests/run.sh provide).
# Installs from setup_file, which runs in the per-file bats process, so a
# signal to that process cleans the file's sandbox. Never touches EXIT,
# which belongs to bats' teardown chain here.
fixture_trap_cleanup() {
  _FIXTURE_TRAP_DIR="${1:-}"
  [ -n "$_FIXTURE_TRAP_DIR" ] || return 1
  trap '_fixture_cleanup_fire; trap - INT; kill -INT $$' INT
  trap '_fixture_cleanup_fire; trap - TERM; kill -TERM $$' TERM
}
