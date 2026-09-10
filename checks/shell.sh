#!/usr/bin/env bash
#
# checks/shell.sh
# Shell configuration file checks
#

# Expand $VAR and ${VAR} references using only values from the current
# environment. Never executes command substitution ($(...), backticks),
# process substitution (<(...)), or arithmetic expansion — identifier-shaped
# $NAME / ${NAME} lookups are replaced via prefix/suffix surgery only, so
# anything else (including malicious payloads in the audited rc file) stays
# literal. Unset/unknown vars expand to empty, matching default shell
# expansion. The loop is bounded (32 passes per form) so self-referential
# values terminate. Bash 3.2 compatible: no associative arrays, no
# case-modifying expansion, no read-into-array builtin.

# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
expand_source_target_vars() {
  local input
  local output
  local raw
  local varname
  local varvalue
  local prefix
  local suffix
  local count
  input="${1-}"
  output="$input"
  if ! command -v printenv >/dev/null 2>&1; then
    printf '%s' "$input"
    return 0
  fi
  count=0
  while echo "$output" | grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*\}'; do
    count=$((count + 1))
    if [ "$count" -gt 32 ]; then
      break
    fi
    raw="$(echo "$output" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' | head -n 1 || true)"
    varname="$(echo "$raw" | sed -E 's/^\$\{//; s/\}$//' || true)"
    case "$varname" in
      ""|*[!A-Za-z0-9_]*)
        break
        ;;
    esac
    varvalue="$(printenv "$varname" 2>/dev/null || true)"
    prefix="${output%%\${"$varname"\}*}"
    suffix="${output#*\${"$varname"\}}"
    if [ "$prefix" = "$output" ] && [ "$suffix" = "$output" ]; then
      break
    fi
    output="${prefix}${varvalue}${suffix}"
  done
  count=0
  while echo "$output" | grep -qE '\$[A-Za-z_][A-Za-z0-9_]*'; do
    count=$((count + 1))
    if [ "$count" -gt 32 ]; then
      break
    fi
    raw="$(echo "$output" | grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' | head -n 1 || true)"
    varname="${raw#\$}"
    case "$varname" in
      ""|*[!A-Za-z0-9_]*)
        break
        ;;
    esac
    varvalue="$(printenv "$varname" 2>/dev/null || true)"
    prefix="${output%%\$"$varname"*}"
    suffix="${output#*\$"$varname"}"
    if [ "$prefix" = "$output" ] && [ "$suffix" = "$output" ]; then
      break
    fi
    output="${prefix}${varvalue}${suffix}"
  done
  printf '%s' "$output"
}

check_one_shell_file() {
  local name="${1-}"
  local shell_type="${2-}"
  local file="${HOME}/${name}"

  if [ -z "${name}" ]; then
    return
  fi

  if [ ! -f "$file" ]; then
    status_info "No ${name} found (this is fine if you don't customize ${shell_type})."
    return
  fi

  status_ok "Found ${name}"

  # Syntax check
  if [ "$shell_type" = "zsh" ] && command -v zsh >/dev/null 2>&1; then
    if zsh -n "$file" >/dev/null 2>&1; then
      status_ok "Syntax OK for ${name} (zsh -n)."
    else
      status_warn "Possible syntax errors in ${name} (zsh -n failed)."
      add_action "Open ${file} and fix syntax errors reported by 'zsh -n ${file}'."
    fi
  elif [ "$shell_type" = "bash" ] && command -v bash >/dev/null 2>&1; then
    if bash -n "$file" >/dev/null 2>&1; then
      status_ok "Syntax OK for ${name} (bash -n)."
    else
      status_warn "Possible syntax errors in ${name} (bash -n failed)."
      add_action "Open ${file} and fix syntax errors reported by 'bash -n ${file}'."
    fi
  fi

  # Look for 'source' or '.' commands that reference missing files
  while IFS= read -r line; do
    case "$line" in
      \#*|"") continue ;;
    esac

    if echo "$line" | grep -qE '^\s*(source|\.)\s+'; then
      local target expanded

      # Portable whitespace class: BSD sed (macOS) does not match \s,
      # which left the `source` keyword attached and warned on every line.
      target=$(echo "$line" | sed -E 's/^[[:space:]]*(source|\.)[[:space:]]+//; s/[;&|].*//')
      target=$(echo "$target" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
      target=$(echo "$target" | sed -E 's/^["'\'']//; s/["'\'']$//')

      # Expand shell variables first (e.g. $ZSH, $NVM_DIR, $HOME).
      # SAFE: env-value substitution only — no eval, so command
      # substitution in the audited file can never execute.
      local expanded_raw
      expanded_raw="$(expand_source_target_vars "$target")"

      case "$expanded_raw" in
        /*)
          expanded="$expanded_raw"
          ;;
        ~/*)
          expanded="${HOME}${expanded_raw#\~}"
          ;;
        *)
          expanded="${HOME}/${expanded_raw}"
          ;;
      esac

      if [ -n "$expanded" ] && [ ! -e "$expanded" ]; then
        status_warn "In ${name}: sources missing file '${target}'."
        add_action "Edit ${file} to fix or remove 'source ${target}' (file does not exist at ${expanded})."
      fi
    fi
  done < "$file"
}

check_shell_configs() {
  step "Shell configuration files (.zshrc, .bashrc, etc.)"

  check_one_shell_file ".zshrc" "zsh"
  check_one_shell_file ".bashrc" "bash"
  check_one_shell_file ".bash_profile" "bash"
  check_one_shell_file ".profile" "sh"
}
