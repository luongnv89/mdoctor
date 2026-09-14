#!/usr/bin/env bash
#
# lib/history.sh
# History storage and trend display for health scores
#

# history_prune needs validate_deletion_path (issue #113): retention
# deletes route through the same lib/safety.sh validation every other
# deletion passes. is_uint comes from lib/constants.sh. The variable is
# named per-file because a sourced dependency unsets the shared
# _mdoctor_lib_dir name (issue #113).
_mdoctor_history_lib_dir="${BASH_SOURCE[0]%/*}"
if [ "$_mdoctor_history_lib_dir" = "${BASH_SOURCE[0]}" ]; then
  _mdoctor_history_lib_dir="."
fi
if ! declare -f is_uint >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_history_lib_dir}/constants.sh"
fi
if ! declare -f validate_deletion_path >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_history_lib_dir}/safety.sh"
fi
unset _mdoctor_history_lib_dir

HISTORY_DIR="${HOME}/.mdoctor/history"

# Per-process sequence suffix for history filenames (issue #113): the
# second-resolution timestamp alone collides when two runs save inside
# the same second — PID plus this counter makes every name distinct.
_HISTORY_SEQ=0

########################################
# SAVE HISTORY
########################################

# history_save SCORE RATING WARNINGS FAILURES
# Saves a summary JSON to ~/.mdoctor/history/YYYYMMDD_HHMMSS-<pid>-<seq>.json
history_save() {
  local score="$1"
  local rating="$2"
  local warnings="$3"
  local failures="$4"

  # Best-effort state (issue #113): a directory we cannot create warns and
  # skips the save — it never aborts the run under `set -e`.
  if [ ! -d "$HISTORY_DIR" ]; then
    if ! mkdir -p "$HISTORY_DIR" 2>/dev/null; then
      echo "warning: cannot create history dir '${HISTORY_DIR}' — skipping history save" >&2
      return 0
    fi
    # Task 3.4: state dirs/files are private at creation.
    chmod 700 "$HISTORY_DIR" 2>/dev/null || true
  fi

  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  _HISTORY_SEQ=$((_HISTORY_SEQ + 1))
  local file="${HISTORY_DIR}/${ts}-$$-${_HISTORY_SEQ}.json"

  local esc_rating
  esc_rating="${rating//\"/\\\"}"

  if cat > "$file" <<HISTEOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","score":${score},"rating":"${esc_rating}","warnings":${warnings},"failures":${failures}}
HISTEOF
  then
    chmod 600 "$file" 2>/dev/null || true
  else
    echo "warning: cannot write history entry '${file}' — skipping history save" >&2
    return 0
  fi

  history_prune
}

# history_prune — bound the history directory to MDOCTOR_HISTORY_KEEP
# entries (issue #113). Filenames sort chronologically (timestamp prefix),
# so the oldest overflow is removed first. Candidates are the .json files
# this process's own state dir contains; each deletion is validated by
# lib/safety.sh's validate_deletion_path (~/.mdoctor/history is an allowed
# deletion root) and the canonical path is removed directly — never via
# safe_remove, whose dry-run gate would make the bound unreachable from
# `mdoctor check`, which always runs dry and has no --force flag.
# The cleanup whitelist is still honored (review #223): it is the user's
# declared protection list, and every other deletion path consults it.
# The consult is gated on the whitelist file already existing (or the
# engine having loaded it) so a dry-run check never creates the config
# file as a side effect of pruning.
history_prune() {
  [ -d "$HISTORY_DIR" ] || return 0

  local keep="${MDOCTOR_HISTORY_KEEP:-100}"
  is_uint "$keep" || keep=100
  # 10# forces decimal — is_uint accepts "08"/"09", which are invalid
  # octal to $(( )) and would abort the prune (and the save under -e).
  keep=$((10#$keep))

  local files=()
  local f
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$HISTORY_DIR" -name '*.json' -type f 2>/dev/null | sort)

  local total=${#files[@]}
  local excess=$((total - keep))
  if (( excess <= 0 )); then
    return 0
  fi

  local whitelist_active=false
  if declare -f is_whitelisted_cleanup_path >/dev/null 2>&1 &&
    { [ -f "${MDOCTOR_CLEANUP_WHITELIST_FILE:-}" ] ||
      [ "${_MDOCTOR_WHITELIST_LOADED:-}" = "true" ]; }; then
    whitelist_active=true
  fi

  # Walk oldest-first until `excess` entries are actually gone: a
  # whitelisted (or unremovable) entry counts toward the cap rather than
  # letting the directory grow past it.
  local i=0 removed=0 canon=""
  while (( i < total && removed < excess )); do
    f="${files[$i]}"
    canon=""
    if [ "$whitelist_active" = "true" ] && is_whitelisted_cleanup_path "$f"; then
      if declare -f debug_log >/dev/null 2>&1; then
        debug_log "history prune: skipping whitelisted ${f}"
      fi
    elif validate_deletion_path "$f" canon >/dev/null 2>&1 && [ -n "$canon" ]; then
      if rm -f -- "$canon" 2>/dev/null; then
        removed=$((removed + 1))
        if declare -f debug_log >/dev/null 2>&1; then
          debug_log "history prune: removed ${canon}"
        fi
      fi
    fi
    i=$((i + 1))
  done
  return 0
}

# _history_is_uint VALUE — validates a parsed history field before any
# arithmetic or format use (Task 3.4). History files are user-writable
# state, not trusted input.
_history_is_uint() {
  case "${1-}" in
    ""|*[!0-9]*) return 1 ;;
  esac
  return 0
}

########################################
# DISPLAY HISTORY
########################################

# history_show [COUNT]
# Displays recent health scores with trend arrows
history_show() {
  local count="${1:-10}"
  local files=()
  local f

  if [ ! -d "$HISTORY_DIR" ]; then
    echo "No history yet. Run 'mdoctor check' first."
    return 0
  fi

  # Collect history files sorted by name (chronological)
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$HISTORY_DIR" -name '*.json' -type f 2>/dev/null | sort)

  local total=${#files[@]}
  if (( total == 0 )); then
    echo "No history yet. Run 'mdoctor check' first."
    return 0
  fi

  # Show header
  printf "  %-20s  %-6s  %-5s  %-18s  %s\n" "Date" "Score" "Trend" "Rating" "W/F"
  printf "  %-20s  %-6s  %-5s  %-18s  %s\n" "--------------------" "------" "-----" "------------------" "---"

  # Calculate start index
  local start=0
  if (( total > count )); then
    start=$((total - count))
  fi

  local prev_score=-1
  local i=$start
  while (( i < total )); do
    local file="${files[$i]}"
    local line
    # An unreadable file must still advance the index: `|| continue`
    # would jump back to the loop condition and retry the same entry
    # forever (Task 4.7).
    if ! line="$(cat "$file" 2>/dev/null)"; then
      i=$((i + 1))
      continue
    fi

    # Parse JSON fields using parameter expansion (pure Bash)
    local ts score rating warnings failures

    # Extract timestamp
    ts="${line#*\"timestamp\":\"}"
    ts="${ts%%\"*}"

    # Extract score
    score="${line#*\"score\":}"
    score="${score%%,*}"
    score="${score%%\}*}"

    # Extract rating
    rating="${line#*\"rating\":\"}"
    rating="${rating%%\"*}"

    # Extract warnings
    warnings="${line#*\"warnings\":}"
    warnings="${warnings%%,*}"
    warnings="${warnings%%\}*}"

    # Extract failures
    failures="${line#*\"failures\":}"
    failures="${failures%%,*}"
    failures="${failures%%\}*}"

    # Task 3.4: history files are user-writable state — validate every
    # numeric field before any arithmetic or format use. A non-conforming
    # entry is rejected with a message, never evaluated.
    if ! _history_is_uint "$score"; then
      echo "warning: skipping history entry with invalid score in ${file}" >&2
      i=$((i + 1))
      continue
    fi
    if ! _history_is_uint "$warnings"; then
      echo "warning: skipping history entry with invalid warnings in ${file}" >&2
      i=$((i + 1))
      continue
    fi
    if ! _history_is_uint "$failures"; then
      echo "warning: skipping history entry with invalid failures in ${file}" >&2
      i=$((i + 1))
      continue
    fi
    # Trend arrow
    local trend=" "
    if (( prev_score >= 0 )); then
      if (( score > prev_score )); then
        trend="^ UP"
      elif (( score < prev_score )); then
        trend="v DN"
      else
        trend="= =="
      fi
    fi

    # Format timestamp for display (remove T and Z)
    local display_ts="${ts/T/ }"
    display_ts="${display_ts%Z}"

    printf "  %-20s  %3d     %-5s  %-18s  %s/%s\n" \
      "$display_ts" "$score" "$trend" "$rating" "$warnings" "$failures"

    prev_score=$score
    i=$((i + 1))
  done

  echo

  # Detect regression
  if (( total >= 2 )); then
    local prev_file="${files[$((total - 2))]}"
    local last_file="${files[$((total - 1))]}"
    local prev_s last_s

    local prev_line last_line
    prev_line="$(cat "$prev_file" 2>/dev/null)"
    last_line="$(cat "$last_file" 2>/dev/null)"

    prev_s="${prev_line#*\"score\":}"
    prev_s="${prev_s%%,*}"
    prev_s="${prev_s%%\}*}"

    last_s="${last_line#*\"score\":}"
    last_s="${last_s%%,*}"
    last_s="${last_s%%\}*}"

    # Task 3.4: same validation for the regression comparison.
    if ! _history_is_uint "$prev_s" || ! _history_is_uint "$last_s"; then
      echo "warning: skipping regression check with invalid scores" >&2
      return
    fi

    if (( last_s < prev_s )); then
      local diff=$((prev_s - last_s))
      echo "  Warning: Score dropped from ${prev_s} to ${last_s} (down ${diff} points) since last run."
    fi
  fi
}
