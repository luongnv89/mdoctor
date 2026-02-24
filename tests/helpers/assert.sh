#!/usr/bin/env bash

fail() {
  echo "❌ $*" >&2
  return 1
}

pass() {
  echo "✅ $*"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -q -- "$needle" "$file" || fail "Expected '$needle' in $file"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -q -- "$needle" "$file"; then
    fail "Did not expect '$needle' in $file"
  fi
}

assert_file_exists() {
  local file="$1"
  [ -f "$file" ] || fail "Expected file to exist: $file"
}

assert_file_not_exists() {
  local file="$1"
  [ ! -f "$file" ] || fail "Expected file to be absent: $file"
}

assert_dir_exists() {
  local dir="$1"
  [ -d "$dir" ] || fail "Expected directory to exist: $dir"
}
