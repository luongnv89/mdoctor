#!/usr/bin/env bash
# Task 2.2: scripts/lint_shell.sh is the single source of shell-file
# discovery — an extensionless executable with a bash shebang is picked
# up by every gate that uses it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: lint discovery test requires shellcheck" >&2
  exit 0
fi

# Temporary extensionless executable at the repo root (no .sh suffix).
PROBE="$ROOT_DIR/tmp_probe_lint_gate"
trap 'rm -f "$PROBE"' EXIT
printf '#!/usr/bin/env bash\necho "probe ok"\n' >"$PROBE"
chmod +x "$PROBE"

out="$ROOT_DIR/tmp_probe_lint_gate.out"
trap 'rm -f "$PROBE" "$out"' EXIT
./scripts/lint_shell.sh >"$out" 2>&1
assert_contains "$out" "tmp_probe_lint_gate"
# ... while archived trees stay excluded.
if ls openspec/*.sh >/dev/null 2>&1; then
  _excluded="$(ls openspec/*.sh | head -n 1)"
  assert_not_contains "$out" "$_excluded"
fi

pass "lint discovery covers extensionless executables"
