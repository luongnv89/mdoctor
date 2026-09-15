#!/usr/bin/env bats
#
# test_dev_retired.bats
# Issue #89 (10.3): the dev module is retired into dev_caches.
#
# Asserts the retirement contract end to end:
#   1. dev is gone from the registry (list/names/-m dispatch all agree);
#   2. the three unique dev targets live in clean_dev_caches;
#   3. interactive "all" issues `docker system prune` at most once,
#      pinned through the Task 6.3 docker argv-recorder stub;
#   4. cleanup.sh carries no commented-out step code, defines step()
#      once (lib/common.sh), derives its total, calls main with no
#      arguments, and is tab-free.
#
# Hermetic: HOME sandbox + helpers/bin stubs (docker records argv,
# never reaches a daemon). Bash 3.2 compatible: no associative arrays,
# no mapfile, no [[ =~ ]].

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-devretired.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "dev module is gone from the registry" {
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  register_all_modules
  names="$(registry_names cleanup)"
  case " $names " in
    *" dev "*) fail "dev still registered: $names" ;;
  esac
  ./mdoctor list >"$TMPHOME/retired-list.out" 2>&1
  assert_not_contains "$TMPHOME/retired-list.out" "clean_dev_stuff"
  if grep -q '^ *dev ' "$TMPHOME/retired-list.out"; then
    fail "dev still listed in mdoctor list"
  fi
}

@test "clean -m dev is rejected as an unknown module" {
  local rc=0
  HOME="$TMPHOME" ./mdoctor clean -m dev >"$TMPHOME/retired-dev.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "clean -m dev should fail after retirement"
  assert_contains "$TMPHOME/retired-dev.out" "Unknown cleanup module"
}

@test "the three unique dev targets now live in clean_dev_caches" {
  grep -q 'brew cleanup -s' "$ROOT_DIR/cleanups/dev_caches.sh" || fail "brew cleanup -s missing from dev_caches"
  grep -q 'brew autoremove' "$ROOT_DIR/cleanups/dev_caches.sh" || fail "brew autoremove missing from dev_caches"
  grep -q '\.cache/yarn' "$ROOT_DIR/cleanups/dev_caches.sh" || fail "Linux yarn path missing from dev_caches"
  if [ -f "$ROOT_DIR/cleanups/dev.sh" ]; then
    fail "cleanups/dev.sh should be deleted"
  fi
}

@test "interactive all skips docker prune without the opt-in" {
  : >"$TMPHOME/retired-prune-off.log"
  printf 'all\n' | MDOCTOR_STUB_LOG="$TMPHOME/retired-prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --interactive --force >"$TMPHOME/retired-all-off.out" 2>&1 || true
  assert_not_contains "$TMPHOME/retired-prune-off.log" "docker system prune"
}

@test "interactive all issues docker system prune at most once with the opt-in" {
  : >"$TMPHOME/retired-prune-on.log"
  printf 'all\n' | MDOCTOR_STUB_LOG="$TMPHOME/retired-prune-on.log" MDOCTOR_ALLOW_DOCKER_PRUNE=true MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --interactive --force >"$TMPHOME/retired-all-on.out" 2>&1 || true
  prune_count="$(grep -c 'docker system prune -af --volumes' "$TMPHOME/retired-prune-on.log" || true)"
  [ "${prune_count:-0}" -le 1 ] || fail "docker system prune ran $prune_count times on interactive all (want at most 1)"
  [ "${prune_count:-0}" -eq 1 ] || fail "docker system prune ran $prune_count times on interactive all with opt-in (want exactly 1)"
}

@test "cleanup.sh has no commented-out step code" {
  commented="$(grep -c '^# *step ' "$ROOT_DIR/cleanup.sh" || true)"
  [ "${commented:-0}" -eq 0 ] || fail "$commented commented-out step lines remain in cleanup.sh"
  commented_calls="$(grep -c '^# *clean_' "$ROOT_DIR/cleanup.sh" || true)"
  [ "${commented_calls:-0}" -eq 0 ] || fail "$commented_calls commented-out clean_ calls remain in cleanup.sh"
}

@test "step() is defined once with a derived total; main takes no arguments" {
  defs="$(grep -h '^step()' "$ROOT_DIR/cleanup.sh" "$ROOT_DIR/lib/common.sh" | wc -l | tr -d ' ')"
  [ "${defs:-0}" -eq 1 ] || fail "step() defined $defs times across cleanup.sh + lib/common.sh (want 1)"
  if grep -q 'PROGRESS_TOTAL=' "$ROOT_DIR/cleanup.sh"; then
    fail "hand-maintained PROGRESS_TOTAL literal survives in cleanup.sh"
  fi
  grep -q 'STEP_TOTAL="${#CLEANUP_STEPS\[@\]}"' "$ROOT_DIR/cleanup.sh" || fail "STEP_TOTAL is not derived from CLEANUP_STEPS"
  grep -q '^main$' "$ROOT_DIR/cleanup.sh" || fail "cleanup.sh does not call main with no arguments"
  grep -q '^main$' "$ROOT_DIR/doctor.sh" || fail "doctor.sh does not call main with no arguments"
  tabs="$(grep -Pc '^\t' "$ROOT_DIR/cleanup.sh" || true)"
  [ "${tabs:-0}" -eq 0 ] || fail "$tabs tab-indented lines remain in cleanup.sh"
}
