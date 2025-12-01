#!/usr/bin/env bash
#
# checks/shell.sh
# Shell configuration file checks
#

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

      target=$(echo "$line" | sed -E 's/^\s*(source|\.)\s+//; s/[;&|].*//')
      target=$(echo "$target" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
      target=$(echo "$target" | sed -E 's/^["'\'']//; s/["'\'']$//')

      case "$target" in
        /*)
          expanded="$target"
          ;;
        ~/*)
          expanded="${HOME}${target#\~}"
          ;;
        *)
          expanded="${HOME}/${target}"
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
