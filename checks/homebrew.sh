#!/usr/bin/env bash
#
# checks/homebrew.sh
# Homebrew health and update checks
#

check_homebrew() {
  step "Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    status_warn "Homebrew is not installed."
    add_action "Install Homebrew (if you need a package manager): /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    return
  fi

  local brew_ver
  brew_ver=$(brew --version 2>/dev/null | head -n1)
  status_ok "Found Homebrew: ${brew_ver}"

  # brew doctor
  local brew_doctor_log="/tmp/brew_doctor.log"
  if brew doctor >"$brew_doctor_log" 2>&1; then
    status_ok "brew doctor reports no major issues."
  else
    status_warn "brew doctor found issues – see ${brew_doctor_log}."
    add_action "Open ${brew_doctor_log} and follow 'brew doctor' suggestions to fix Homebrew issues."
  fi
  add_log_file "$brew_doctor_log" "Homebrew doctor output"

  # outdated formulae – log full list and show short summary
  local outdated_file="/tmp/brew_outdated.log"
  brew outdated >"$outdated_file" 2>/dev/null || true
  local outdated_count
  outdated_count=$(wc -l <"$outdated_file" 2>/dev/null | tr -d ' ' || echo 0)

  if [[ "$outdated_count" == "0" ]]; then
    status_ok "No outdated Homebrew formulae."
  else
    status_warn "${outdated_count} outdated Homebrew formula(e) found."
    status_info "Sample outdated formulae:"
    head -n 5 "$outdated_file" | sed 's/^/    - /'
    [ "$outdated_count" -gt 5 ] && status_info "    … see full list in ${outdated_file}"

    add_action "Update Homebrew packages:
       1) 'brew update'
       2) 'brew upgrade'
       3) Optionally 'brew cleanup -s' to remove old versions.
       Full outdated list: ${outdated_file}"

    add_log_file "$outdated_file" "Outdated Homebrew formulae"
  fi
}
