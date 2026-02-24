#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mapfile -t files < <(
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

echo "ShellCheck high-severity lint on ${#files[@]} files"

for f in "${files[@]}"; do
  echo "- $f"
  shellcheck -S error "$f"
done

echo "ShellCheck lint passed."
