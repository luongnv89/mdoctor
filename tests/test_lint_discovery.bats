#!/usr/bin/env bats
# Task 2.2: scripts/lint_shell.sh is the single source of shell-file
# discovery — an extensionless executable with a bash shebang is picked
# up by every gate that uses it.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PROBE OUT
  PROBE="$ROOT_DIR/tmp_probe_lint_gate"
  printf '#!/usr/bin/env bash\necho "probe ok"\n' >"$PROBE"
  chmod +x "$PROBE"
  OUT="$ROOT_DIR/tmp_probe_lint_gate.out"
}

teardown_file() {
  rm -f "$PROBE" "$OUT"
}

@test "lint discovery covers extensionless executables" {
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "lint discovery test requires shellcheck"
  fi
  ./scripts/lint_shell.sh >"$OUT" 2>&1
  assert_contains "$OUT" "tmp_probe_lint_gate"
  # ... while archived trees stay excluded.
  if ls openspec/*.sh >/dev/null 2>&1; then
    _excluded="$(ls openspec/*.sh | head -n 1)"
    assert_not_contains "$OUT" "$_excluded"
  fi
}
