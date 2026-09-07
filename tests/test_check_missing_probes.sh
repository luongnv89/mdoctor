#!/usr/bin/env bash
# Task 2.5: host-binary guards report skips (never errors), and the ping
# timeout is constructed per platform (macOS -W is ms, Linux -W is s).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

cd "$ROOT_DIR"

# --- Unit: ping argv per platform (stub records, never executes) ---
mkdir -p "$TMPD/stubbin"
cat >"$TMPD/stubbin/ping" <<'EOF'
#!/usr/bin/env bash
printf 'ping %s\n' "$*" >>"$MDOCTOR_STUB_LOG"
exit 0
EOF
chmod +x "$TMPD/stubbin/ping"
source "$ROOT_DIR/checks/network.sh"

: >"$TMPD/ping-linux.log"
MDOCTOR_STUB_LOG="$TMPD/ping-linux.log" PATH="$TMPD/stubbin:$PATH" \
  MDOCTOR_PLATFORM=linux ping_host 1.1.1.1
assert_contains "$TMPD/ping-linux.log" "ping -c 1 -W 1 1.1.1.1"

: >"$TMPD/ping-macos.log"
MDOCTOR_STUB_LOG="$TMPD/ping-macos.log" PATH="$TMPD/stubbin:$PATH" \
  MDOCTOR_PLATFORM=macos ping_host 1.1.1.1
assert_contains "$TMPD/ping-macos.log" "ping -c 1 -W 1000 1.1.1.1"

# --- Integration: sparse PATH without ping/nslookup/ss/ps ---
mkdir -p "$TMPD/farm" "$TMPD/home"
for _d in /usr/bin /bin /usr/sbin /sbin; do
  [ -d "$_d" ] || continue
  for _f in "$_d"/*; do
    [ -f "$_f" ] || continue
    _b="$(basename "$_f")"
    case "$_b" in
      ping|nslookup|ss|ps) continue ;;
    esac
    [ -e "$TMPD/farm/$_b" ] || ln -s "$_f" "$TMPD/farm/$_b"
  done
done

set +e
PATH="$TMPD/farm" HOME="$TMPD/home" timeout 280 ./mdoctor check >"$TMPD/check.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { tail -n 20 "$TMPD/check.out"; fail "Expected mdoctor check exit 0 with missing probe binaries, got $rc"; }

for _skip in \
  "Skipping connectivity probe: ping not found." \
  "Skipping DNS timing probe: nslookup not found." \
  "Skipping listening-ports probe: ss not found." \
  "Skipping top-CPU probe: ps not found." \
  "Skipping top-memory probe: ps not found." \
  "Skipping zombie probe: ps not found."; do
  assert_contains "$TMPD/check.out" "$_skip"
done

# The connection/top-CPU/zombie probes of `diagnose` degrade the same way.
set +e
PATH="$TMPD/farm" HOME="$TMPD/home" timeout 280 ./mdoctor diagnose >"$TMPD/diag.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { tail -n 20 "$TMPD/diag.out"; fail "Expected mdoctor diagnose exit 0 with missing probe binaries, got $rc"; }
for _skip in \
  "Skipping connection-count probe: ss not found." \
  "Skipping top-CPU probe: ps not found." \
  "Skipping zombie probe: ps not found."; do
  assert_contains "$TMPD/diag.out" "$_skip"
done

pass "host-binary guards + platform ping timeout"
