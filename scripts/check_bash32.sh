#!/usr/bin/env bash
# scripts/check_bash32.sh — Bash 3.2 floor policy check (Task 5.1, W3).
#
# Fails if any tracked shell file uses a Bash 4+ construct that Apple's
# vendored Bash 3.2.57 cannot parse or execute. The floor is deliberate
# (see docs/DEVELOPMENT.md "Bash 3.2 compatibility floor"): this project
# ships no Bash of its own, the 3.2 path executes only on macOS where the
# system Bash cannot be upgraded by this project, and raising the floor
# would break the zero-dependencies promise on the primary platform.
#
# Banned constructs (exactly the policy list):
#   1. associative arrays (declare -A)
#   2. namerefs (declare -n)
#   3. mapfile / readarray
#   4. ${var^^} / ${var,,} case modification
#   5. &>> redirection
#   6. coproc
#
# Usage:
#   ./scripts/check_bash32.sh [FILE...]
# With no args, discovers shell files with the same exclusion set as
# scripts/lint_shell.sh (the single source of shell-file discovery).
# Called with a file list, it checks exactly those files (used by
# lint_shell.sh so discovery is not duplicated).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  while IFS= read -r f; do
    case "$f" in
      *.sh|*.bash)
        files+=("$f")
        ;;
      *)
        if [ -f "$f" ] && head -n 1 "$f" 2>/dev/null | grep -q '^#!/.*\bbash\b'; then
          files+=("$f")
        fi
        ;;
    esac
  done < <(
    find . -type f \
      -not -path './.git/*' \
      -not -path './.specify/*' \
      -not -path './.claude/*' \
      -not -path './.codex/*' \
      -not -path './.opencode/*' \
      -not -path './openspec/*' \
      -not -path './node_modules/*' \
      -not -path './gui/node_modules/*' \
      | sort
  )
fi

# The check script itself names every banned construct in its comments and
# patterns, so it must never be scanned — otherwise it always fails.
filtered=()
for f in "${files[@]}"; do
  case "$f" in
    ./scripts/check_bash32.sh|scripts/check_bash32.sh) continue ;;
    *) filtered+=("$f") ;;
  esac
done
files=("${filtered[@]}")

if [ "${#files[@]}" -eq 0 ]; then
  echo "check_bash32: no shell files to check."
  exit 1
fi

failures=0

report_hits() {
  local label="$1"
  local hits="$2"
  if [ -n "$hits" ]; then
    echo "check_bash32 FAIL: $label"
    echo "$hits"
    failures=$((failures + 1))
  fi
}

# 1. Associative arrays: declare -A (flags may combine, e.g. -rA).
hits="$(grep -n -E 'declare[[:space:]]+-[A-Za-z]*A' "${files[@]}" 2>/dev/null || true)"
report_hits "associative array (declare -A) is Bash 4+; use indexed arrays or case dispatch" "$hits"

# 2. Namerefs: declare -n.
hits="$(grep -n -E 'declare[[:space:]]+-[A-Za-z]*n' "${files[@]}" 2>/dev/null || true)"
# Filter out false positives that contain 'n' only as part of a longer
# flag word without nameref intent is not possible by regex alone; the
# repo convention is to never use -n with declare, so any hit is a fail.
report_hits "nameref (declare -n) is Bash 4.3+; pass values explicitly instead" "$hits"

# 3. mapfile / readarray.
hits="$(grep -n -w -E 'mapfile|readarray' "${files[@]}" 2>/dev/null || true)"
report_hits "mapfile/readarray is Bash 4+; use 'while IFS= read -r' loops" "$hits"

# 4. ${var^^} / ${var,,} case modification.
hits="$(grep -n -E '\$\{[^}]*(\^\^|,,)' "${files[@]}" 2>/dev/null || true)"
report_hits "\${var^^}/\${var,,} is Bash 4+; use 'tr' or case dispatch" "$hits"

# 5. &>> redirection.
hits="$(grep -n -F '&>>' "${files[@]}" 2>/dev/null || true)"
report_hits "'&>>' is Bash 4+; use '>>file 2>&1'" "$hits"

# 6. coproc. Word match; the script self-exclusion above keeps this check honest.
hits="$(grep -n -w 'coproc' "${files[@]}" 2>/dev/null || true)"
report_hits "'coproc' is Bash 4+; use explicit background jobs or fifos" "$hits"

if [ "$failures" -gt 0 ]; then
  echo "check_bash32: $failures banned-construct class(es) found in ${#files[@]} files."
  exit 1
fi

echo "check_bash32: OK (${#files[@]} files, no Bash 4+ constructs)."
