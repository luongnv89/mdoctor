#!/usr/bin/env bash
# Single source of shell-file discovery + lint policy (Tasks 2.1, 2.2).
# Discovers: *.sh / *.bash files AND extensionless executables with a
# bash shebang (e.g. `mdoctor`). Excludes vendored/archived trees.
# Runs `bash -n` over the same list, then one `shellcheck -S warning`
# invocation (full inventory, no first-failure abort).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
    -not -path './.specify/*' \
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
