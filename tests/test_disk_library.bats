#!/usr/bin/env bats
#
# Regression test for Task 8.2 (#76) and Task 9.4 (#85):
#   one size-formatter ladder, one hardened du probe with a real error
#   channel, one timestamp function.
# - format_size_kb is the single ladder; kb_to_human/human_readable_kb agree
# - du_size_kb echoes a numeric KB value but returns 0 only for a genuine
#   measurement: distinct $MDOCTOR_SIZE_ERR_* codes for not-a-directory,
#   timeout and permission-denied (dir_size_kb shares the channel)
# - no `du -sk` call site survives outside lib/disk.sh
# - no awk GB/MB formatter ladder survives outside lib/disk.sh
# - timestamp and oplog_timestamp agree (one implementation)
# - single-module pre-flight with a permission-denied subdirectory completes
#   with a numeric estimate under both cleanup.sh and mdoctor (no abort)

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME POISONED
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-disklib.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  POISONED="$TMPHOME/poisoned"
  mkdir -p "$POISONED/sub"
  echo "data" > "$POISONED/sub/file.txt"
  chmod 000 "$POISONED/sub"
}

teardown_file() {
  if [ -d "${TMPHOME:-}" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "one formatter ladder: wrappers agree with format_size_kb" {
  source "$ROOT_DIR/lib/disk.sh"
  [ "$(format_size_kb 512)" = "512 KB" ]
  [ "$(format_size_kb 2048)" = "2.00 MB" ]
  [ "$(format_size_kb 2097152)" = "2.00 GB" ]
  [ "$(kb_to_human 2097152)" = "$(format_size_kb 2097152)" ]
  [ "$(human_readable_kb 2048)" = "$(format_size_kb 2048)" ]
  [ "$(human_readable_kb -2048)" = "$(format_size_kb 2048)" ]
}

@test "du_size_kb echoes a number; 0 only for a genuine measurement" {
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/disk.sh"
  # Genuine measurements (readable dir and file) exit 0 ...
  mkdir -p "$BATS_TEST_TMPDIR/genuine"
  echo "data" > "$BATS_TEST_TMPDIR/genuine/file.txt"
  out=$(du_size_kb "$BATS_TEST_TMPDIR/genuine"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
  out=$(du_size_kb "$BATS_TEST_TMPDIR/genuine/file.txt"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
  # ... the probe always echoes a number (even for the chmod-000
  # fixture, whose status is environment-dependent), ...
  [[ "$(du_size_kb "$POISONED")" =~ ^[0-9]+$ ]]
  [[ "$(du_size_kb "$POISONED/sub/file.txt")" =~ ^[0-9]+$ ]]
  # ... while a missing path still echoes 0 but reports NOT_DIR, so
  # callers can tell failure from a genuinely empty directory.
  rc=0
  out=$(du_size_kb /nonexistent-path-xyz) || rc=$?
  [ "$out" = "0" ]
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NOT_DIR" ]
}

@test "dir-size probe reports four outcomes with distinct codes" {
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/disk.sh"
  # The three failure codes are distinct from each other and from 0.
  [ "$MDOCTOR_SIZE_ERR_NOT_DIR" -ne 0 ]
  [ "$MDOCTOR_SIZE_ERR_TIMEOUT" -ne 0 ]
  [ "$MDOCTOR_SIZE_ERR_DENIED" -ne 0 ]
  [ "$MDOCTOR_SIZE_ERR_NOT_DIR" -ne "$MDOCTOR_SIZE_ERR_TIMEOUT" ]
  [ "$MDOCTOR_SIZE_ERR_NOT_DIR" -ne "$MDOCTOR_SIZE_ERR_DENIED" ]
  [ "$MDOCTOR_SIZE_ERR_TIMEOUT" -ne "$MDOCTOR_SIZE_ERR_DENIED" ]

  probe_dir="$BATS_TEST_TMPDIR/probe"
  mkdir -p "$probe_dir/sub"
  echo "data" > "$probe_dir/sub/file.txt"

  # 1. Genuine measurement exits 0 ...
  out=$(du_size_kb "$probe_dir"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]

  # ... and so does a genuinely empty directory: 0 with status 0 is
  # data, 0 with a non-zero status is "could not determine".
  mkdir -p "$probe_dir/empty"
  out=$(du_size_kb "$probe_dir/empty"); rc=$?
  [ "$rc" -eq 0 ]
  [ "$out" = "0" ]

  # 2. Not a directory.
  rc=0
  out=$(du_size_kb "$BATS_TEST_TMPDIR/does-not-exist") || rc=$?
  [ "$out" = "0" ]
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NOT_DIR" ]

  # 3. Permission denied, via a stubbed du (deterministic as any user).
  stubbin="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$stubbin"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "du: cannot access $2: Permission denied" >&2\n'
    printf 'exit 1\n'
  } > "$stubbin/du"
  chmod +x "$stubbin/du"
  old_path="$PATH"
  PATH="$stubbin:$PATH"
  hash -r
  rc=0
  out=$(du_size_kb "$probe_dir") || rc=$?
  PATH="$old_path"
  hash -r
  [ "$out" = "0" ]
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_DENIED" ]

  # 4. Timed out, via a stubbed timeout (124 is timeout's real status).
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exit 124\n'
  } > "$stubbin/timeout"
  chmod +x "$stubbin/timeout"
  PATH="$stubbin:$PATH"
  hash -r
  rc=0
  out=$(du_size_kb "$probe_dir") || rc=$?
  PATH="$old_path"
  hash -r
  [ "$out" = "0" ]
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_TIMEOUT" ]

  # The documented alias shares the channel.
  rc=0
  out=$(dir_size_kb "$BATS_TEST_TMPDIR/does-not-exist") || rc=$?
  [ "$out" = "0" ]
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NOT_DIR" ]
}

@test "no du call site survives outside lib/disk.sh" {
  # BusyBox-grep compatible: no grep --include.
  hits=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" -not -path "$ROOT_DIR/lib/disk.sh" | xargs grep -l 'du -sk' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "no awk GB/MB formatter ladder survives outside lib/disk.sh" {
  hits=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" -not -path "$ROOT_DIR/lib/disk.sh" | xargs grep -l 'awk.*printf.*[GM]B' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "timestamp and oplog_timestamp agree" {
  source "$ROOT_DIR/lib/logging.sh"
  [ "$(oplog_timestamp)" = "$(timestamp)" ]
}

@test "cleanup.sh force preflight completes with poisoned subdir" {
  export HOME="$TMPHOME"
  export MDOCTOR_PREFLIGHT_ONLY=true
  run "$ROOT_DIR/cleanup.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Estimated reclaim size:"* ]]
}

@test "mdoctor single-module preflight completes with poisoned trash" {
  export HOME="$TMPHOME"
  mkdir -p "$TMPHOME/.local/share/Trash/files/poisoned"
  echo "data" > "$TMPHOME/.local/share/Trash/files/poisoned/file.txt"
  chmod 000 "$TMPHOME/.local/share/Trash/files/poisoned"
  out=$(printf 'n\n' | "$ROOT_DIR/mdoctor" clean -m trash --force 2>&1 || true)
  [[ "$out" == *"Pre-flight Safety Summary"* ]]
  # Readable trash prints an estimate (~X); an unreadable one honestly
  # reports "could not determine" instead of fabricating 0 (Task 9.4).
  if [[ "$out" != *"(~"* && "$out" != *"could not determine"* ]]; then
    fail "expected an estimate or a could-not-determine note: $out"
  fi
  chmod -R u+rwx "$TMPHOME/.local/share/Trash" 2>/dev/null || true
}
