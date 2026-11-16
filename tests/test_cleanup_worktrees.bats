#!/usr/bin/env bats
#
# test_cleanup_worktrees.bats
# `clean -m worktrees`: scan git worktrees under the cleanup scope roots
# and remove only the ones that are safe to delete.
#
# Hermetic: HOME sandbox, real git on throwaway repos, identity via env
# (the sandbox HOME has no gitconfig). Each test builds its own repo so
# force runs never leak state between tests.
# Bash 3.2 compatible: no associative arrays, no mapfile, no [[ =~ ]].

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
}

setup() {
  command -v git >/dev/null 2>&1 || skip "git not installed"
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-worktrees.$(fixture_run_id).XXXXXX")"
  TMPHOME="$(cd "$TMPHOME" && pwd -P)"
  export TMPHOME
  mkdir -p "$TMPHOME/.config/mdoctor" "$TMPHOME/Projects"
  printf '# empty whitelist for test\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export GIT_CONFIG_NOSYSTEM=1
  REPO="$TMPHOME/Projects/repo"
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b main
  echo a > "$REPO/a"
  printf 'node_modules/\n.env\n' > "$REPO/.gitignore"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm init
}

teardown() {
  [ -n "${TMPHOME:-}" ] && rm -rf "$TMPHOME"
}

# add_wt NAME — linked worktree ../wt-NAME on a new branch NAME.
add_wt() {
  git -C "$REPO" worktree add -q "$TMPHOME/Projects/wt-$1" -b "$1"
}

# age_all — push every mtime 30 days back so the inactivity rule passes.
age_all() {
  local stamp
  stamp="$(date -r "$(( $(date +%s) - 30 * 86400 ))" +%Y%m%d%H%M 2>/dev/null ||
    date -d "@$(( $(date +%s) - 30 * 86400 ))" +%Y%m%d%H%M)"
  find "$TMPHOME/Projects" -exec touch -t "$stamp" {} +
}

run_wt() {
  HOME="$TMPHOME" MDOCTOR_ASSUME_YES=true ./mdoctor clean -m worktrees "$@" >"$TMPHOME/out" 2>&1
}

@test "worktrees is a registered cleanup module, excluded from the full run" {
  HOME="$TMPHOME" ./mdoctor clean --help >"$TMPHOME/help" 2>&1
  assert_contains "$TMPHOME/help" "worktrees"
  run grep -E '^[[:space:]]*CLEANUP_STEPS.*worktrees' cleanup.sh
  [ "$status" -ne 0 ]
}

@test "dry-run lists a clean inactive worktree but removes nothing" {
  add_wt clean
  age_all
  run_wt
  assert_contains "$TMPHOME/out" "Safe to remove: ~/Projects/wt-clean"
  assert_contains "$TMPHOME/out" "\\[DRY RUN\\] git"
  assert_dir_exists "$TMPHOME/Projects/wt-clean"
}

@test "--force removes a clean inactive worktree and keeps its branch" {
  add_wt clean
  mkdir -p "$TMPHOME/Projects/wt-clean/node_modules"
  echo x > "$TMPHOME/Projects/wt-clean/node_modules/f"
  age_all
  run_wt --force
  assert_contains "$TMPHOME/out" "Worktree \\[clean\\]"
  [ ! -d "$TMPHOME/Projects/wt-clean" ]
  git -C "$REPO" rev-parse --verify -q refs/heads/clean >/dev/null
}

@test "--force keeps dirty, untracked, locked, .env and recent worktrees" {
  add_wt dirty
  add_wt untracked
  add_wt locked
  add_wt envf
  echo y >> "$TMPHOME/Projects/wt-dirty/a"
  touch "$TMPHOME/Projects/wt-untracked/new"
  git -C "$REPO" worktree lock "$TMPHOME/Projects/wt-locked"
  touch "$TMPHOME/Projects/wt-envf/.env"
  age_all
  add_wt recent
  run_wt --force
  assert_contains "$TMPHOME/out" "wt-dirty \\[dirty\\] — uncommitted or untracked changes"
  assert_contains "$TMPHOME/out" "wt-untracked \\[untracked\\] — uncommitted or untracked changes"
  assert_contains "$TMPHOME/out" "wt-locked \\[locked\\] — locked"
  assert_contains "$TMPHOME/out" "wt-envf \\[envf\\] — ignored files would be lost (.env)"
  assert_contains "$TMPHOME/out" "wt-recent \\[recent\\] — active within the last 7 days"
  local d
  for d in dirty untracked locked envf recent; do
    assert_dir_exists "$TMPHOME/Projects/wt-$d"
  done
}

@test "--force keeps a detached HEAD whose commits no ref contains" {
  git -C "$REPO" worktree add -q --detach "$TMPHOME/Projects/wt-det"
  echo z > "$TMPHOME/Projects/wt-det/z"
  git -C "$TMPHOME/Projects/wt-det" add z
  git -C "$TMPHOME/Projects/wt-det" commit -qm detached
  age_all
  run_wt --force
  assert_contains "$TMPHOME/out" "detached HEAD has commits no branch, tag or remote contains"
  assert_dir_exists "$TMPHOME/Projects/wt-det"
}

@test "--force prunes a stale entry whose directory is gone" {
  add_wt gone
  rm -rf "$TMPHOME/Projects/wt-gone"
  run_wt --force
  assert_contains "$TMPHOME/out" "Stale entry: ~/Projects/wt-gone"
  run git -C "$REPO" worktree list --porcelain
  [[ "$output" != *wt-gone* ]]
}

@test "whitelisted worktree is kept" {
  add_wt keepme
  age_all
  printf '%s\n' "$TMPHOME/Projects/wt-keepme" >> "$TMPHOME/.config/mdoctor/cleanup_whitelist"
  run_wt --force
  assert_contains "$TMPHOME/out" "wt-keepme \\[keepme\\] — whitelisted"
  assert_dir_exists "$TMPHOME/Projects/wt-keepme"
}

@test "a worktree containing the current directory is kept" {
  add_wt here
  age_all
  (cd "$TMPHOME/Projects/wt-here" && HOME="$TMPHOME" MDOCTOR_ASSUME_YES=true "$ROOT_DIR/mdoctor" clean -m worktrees --force) >"$TMPHOME/out" 2>&1
  assert_contains "$TMPHOME/out" "wt-here \\[here\\] — current directory is inside it"
  assert_dir_exists "$TMPHOME/Projects/wt-here"
}
