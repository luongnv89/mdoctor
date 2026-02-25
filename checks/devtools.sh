#!/usr/bin/env bash
#
# checks/devtools.sh
# Developer tools checks (Xcode, Git, Docker)
#

check_dev_tools() {
  step "Developer Tools, Git & Docker"

  # Build tools
  if is_macos; then
    if xcode-select -p >/dev/null 2>&1; then
      status_ok "Xcode Command Line Tools installed: $(xcode-select -p)"
    else
      status_warn "Xcode Command Line Tools not found."
      add_action "Install Xcode Command Line Tools: run 'xcode-select --install'."
    fi
  else
    # Linux: build-essential, gcc, make
    if command -v gcc >/dev/null 2>&1; then
      status_ok "GCC: $(gcc --version 2>/dev/null | head -n1)"
    elif command -v cc >/dev/null 2>&1; then
      status_ok "C compiler: $(cc --version 2>/dev/null | head -n1)"
    else
      status_info "No C compiler found."
      add_action "Install build tools: sudo apt install build-essential"
    fi
    if command -v make >/dev/null 2>&1; then
      status_ok "Make: $(make --version 2>/dev/null | head -n1)"
    fi
  fi

  # Git
  if command -v git >/dev/null 2>&1; then
    status_ok "Git: $(git --version)"
  else
    status_warn "Git not found."
    if is_macos; then
      add_action "Install Git via Xcode CLT ('xcode-select --install') or 'brew install git'."
    else
      add_action "Install Git: sudo apt install git"
    fi
  fi

  # Docker
  if command -v docker >/dev/null 2>&1; then
    local docker_info_log="/tmp/docker_info.log"
    if docker info >"$docker_info_log" 2>&1; then
      status_ok "Docker is installed and daemon is reachable."
    else
      status_warn "Docker CLI found but daemon not reachable."
      add_action "Start Docker Desktop or ensure the Docker daemon is running, then re-run 'docker info'."
    fi
    add_log_file "$docker_info_log" "Docker info output"
  else
    status_info "Docker not installed (skipping)."
  fi
}
