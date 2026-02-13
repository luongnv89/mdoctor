#!/usr/bin/env bash
#
# lib/history.sh
# History storage and trend display for health scores
#

HISTORY_DIR="${HOME}/.mdoctor/history"

########################################
# SAVE HISTORY
########################################

# history_save SCORE RATING WARNINGS FAILURES
# Saves a summary JSON to ~/.mdoctor/history/YYYYMMDD_HHMMSS.json
history_save() {
  local score="$1"
  local rating="$2"
  local warnings="$3"
  local failures="$4"

  mkdir -p "$HISTORY_DIR"

  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local file="${HISTORY_DIR}/${ts}.json"

  local esc_rating
  esc_rating="${rating//\"/\\\"}"

  cat > "$file" <<HISTEOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","score":${score},"rating":"${esc_rating}","warnings":${warnings},"failures":${failures}}
HISTEOF
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
    line="$(cat "$file" 2>/dev/null)" || continue

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

    if (( last_s < prev_s )); then
      local diff=$((prev_s - last_s))
      echo "  Warning: Score dropped from ${prev_s} to ${last_s} (down ${diff} points) since last run."
    fi
  fi
}
