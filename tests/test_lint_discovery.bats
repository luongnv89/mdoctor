#!/usr/bin/env bats
# Task 2.2: scripts/lint_shell.sh is the single source of shell-file
# discovery — an extensionless executable with a bash shebang is picked
# up by every gate that uses it.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  # Sandbox-scoped discovery (issue #73): the lint gate honors
  # MDOCTOR_LINT_ROOT, so this file exercises the real discovery code
  # without writing into the repo working tree.
  export SANDBOX OUT
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  SANDBOX="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-lintdisc.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$SANDBOX"
  mkdir -p "$SANDBOX/openspec"
  printf '#!/usr/bin/env bash\necho "probe ok"\n' >"$SANDBOX/tmp_probe_lint_gate"
  chmod +x "$SANDBOX/tmp_probe_lint_gate"
  printf '#!/usr/bin/env bash\necho "archived"\n' >"$SANDBOX/openspec/archived.sh"
  OUT="$SANDBOX/tmp_probe_lint_gate.out"
}

teardown_file() {
  rm -rf "$SANDBOX"
}

@test "lint discovery covers extensionless executables" {
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "lint discovery test requires shellcheck"
  fi
  MDOCTOR_LINT_ROOT="$SANDBOX" ./scripts/lint_shell.sh >"$OUT" 2>&1
  assert_contains "$OUT" "tmp_probe_lint_gate"
  # ... while archived trees stay excluded.
  assert_not_contains "$OUT" "archived.sh"
}
