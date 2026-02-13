#!/usr/bin/env bash
#
# checks/git_config.sh
# Git & SSH configuration audit (read-only, SAFE)
# Category: Software
#

check_git_config() {
  step "Git & SSH Configuration"

  # Git availability
  if ! command -v git >/dev/null 2>&1; then
    status_warn "Git is not installed."
    add_action "Install Git: xcode-select --install"
    return 0
  fi

  status_ok "Git: $(git --version 2>/dev/null)"

  # Git user.name
  local git_name
  git_name=$(git config --global user.name 2>/dev/null || echo "")
  if [ -n "$git_name" ]; then
    status_ok "Git user.name: ${git_name}"
  else
    status_warn "Git user.name is not set globally."
    add_action "Set Git name: git config --global user.name 'Your Name'"
  fi

  # Git user.email
  local git_email
  git_email=$(git config --global user.email 2>/dev/null || echo "")
  if [ -n "$git_email" ]; then
    status_ok "Git user.email: ${git_email}"
  else
    status_warn "Git user.email is not set globally."
    add_action "Set Git email: git config --global user.email 'you@example.com'"
  fi

  # Git credential helper
  local cred_helper
  cred_helper=$(git config --global credential.helper 2>/dev/null || echo "")
  if [ -n "$cred_helper" ]; then
    status_ok "Git credential helper: ${cred_helper}"
  else
    status_info "Git credential helper: not configured"
  fi

  # SSH key existence
  local ssh_dir="${HOME}/.ssh"
  if [ -d "$ssh_dir" ]; then
    local key_count=0
    local f
    for f in "${ssh_dir}"/id_*; do
      [ -f "$f" ] || continue
      # Skip .pub files
      case "$f" in *.pub) continue ;; esac
      key_count=$((key_count + 1))

      # Check permissions (should be 600 or 400)
      local perms
      perms=$(stat -f "%Lp" "$f" 2>/dev/null || stat -c "%a" "$f" 2>/dev/null || echo "")
      if [ -n "$perms" ]; then
        if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
          status_ok "SSH key $(basename "$f"): permissions ${perms} (secure)"
        else
          status_warn "SSH key $(basename "$f"): permissions ${perms} (should be 600 or 400)"
          add_action "Fix SSH key permissions: chmod 600 ${f}"
        fi
      fi
    done

    if (( key_count > 0 )); then
      status_ok "SSH keys found: ${key_count}"
    else
      status_info "No SSH private keys found in ~/.ssh/"
    fi
  else
    status_info "No ~/.ssh directory found."
  fi

  # SSH agent status
  local agent_keys
  agent_keys=$(ssh-add -l 2>/dev/null || echo "")
  if echo "$agent_keys" | grep -q "no identities"; then
    status_info "SSH agent: running, no keys loaded"
  elif echo "$agent_keys" | grep -q "Could not open"; then
    status_info "SSH agent: not running"
  elif [ -n "$agent_keys" ]; then
    local loaded
    loaded=$(echo "$agent_keys" | wc -l | tr -d ' ')
    status_ok "SSH agent: ${loaded} key(s) loaded"
  fi
}
