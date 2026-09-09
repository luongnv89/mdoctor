#!/usr/bin/env bash
# Single source of shell-file discovery + lint policy (Tasks 2.1, 2.2).
# Discovers: *.sh / *.bash files AND extensionless executables with a
# bash shebang (e.g. `mdoctor`). Excludes vendored/archived trees.
# Runs `bash -n` over the same list, then one `shellcheck -S warning`
# invocation (full inventory, no first-failure abort).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# MDOCTOR_LINT_ROOT overrides the discovery root (tests point it at a
# throwaway sandbox so the lint-discovery test never writes into the repo
# working tree). Defaults to the repo root; every other gate behaves as
# before when the variable is unset.
LINT_ROOT="${MDOCTOR_LINT_ROOT:-$ROOT_DIR}"
cd "$LINT_ROOT" || exit 1

files=()
while IFS= read -r f; do
  case "$f" in
    *.sh|*.bash)
      files+=("$f")
      ;;
    *)
      # Extensionless candidate: pick it up iff it has a bash shebang.
      if [ -f "$f" ] && head -n 1 "$f" 2>/dev/null | grep -q '^#!/.*\bbash\b'; then
        files+=("$f")
      fi
      ;;
  esac
done < <(
  find . -type f \
    -not -path './.git/*' \
    -not -path './.claude/*' \
    -not -path './.codex/*' \
    -not -path './.opencode/*' \
    -not -path './openspec/*' \
    -not -path './node_modules/*' \
    -not -path './gui/node_modules/*' \
    | sort
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No shell files found to lint."
  exit 1
fi

echo "Bash syntax check on ${#files[@]} files"
for f in "${files[@]}"; do
  bash -n "$f"
done
echo "Bash syntax OK."

echo "ShellCheck warning-severity lint on ${#files[@]} files"
printf -- '- %s\n' "${files[@]}"
shellcheck -S warning "${files[@]}"

echo "ShellCheck lint passed."

# Task 5.1 (W3): Bash 3.2 floor policy check over the same file list
# (single discovery source — pass the list, don't re-discover). Absolute
# paths when a lint-root override is active (check_bash32.sh re-roots
# itself, so relative paths would resolve against the wrong tree).
_abs_files=()
for _f in "${files[@]}"; do
  case "$_f" in
    /*) _abs_files+=("$_f") ;;
    *) _abs_files+=("$LINT_ROOT/${_f#./}") ;;
  esac
done
"$SCRIPT_DIR/check_bash32.sh" "${_abs_files[@]}"
