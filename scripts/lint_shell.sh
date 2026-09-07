#!/usr/bin/env bash
# ShellCheck policy linter (Task 2.1: gate at -S warning).
# Single shellcheck invocation over all discovered files: reports the
# full violation inventory instead of aborting on the first failing file.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(
  find . \( -name '*.sh' -o -name 'mdoctor' \) \
    -not -path './.specify/*' \
    -not -path './.claude/*' \
    -not -path './.codex/*' \
    -not -path './.opencode/*' \
    -not -path './openspec/*' \
    -not -name '*-old.sh' \
    | sort
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No shell files found to lint."
  exit 1
fi

echo "ShellCheck warning-severity lint on ${#files[@]} files"
printf -- '- %s\n' "${files[@]}"
shellcheck -S warning "${files[@]}"

echo "ShellCheck lint passed."
