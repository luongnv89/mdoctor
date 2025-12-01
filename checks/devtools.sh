#!/usr/bin/env bash
#
# checks/devtools.sh
# Developer tools checks (Xcode, Git, Docker)
#

check_dev_tools() {
  step "Xcode Command Line Tools, Git & Docker"

  # Xcode Command Line Tools
  if xcode-select -p >/dev/null 2>&1; then
    status_ok "Xcode Command Line Tools installed: $(xcode-select -p)"
  else
    status_warn "Xcode Command Line Tools not found."
    add_action "Install Xcode Command Line Tools: run 'xcode-select --install'."
  fi

  # Git
  if command -v git >/dev/null 2>&1; then
    status_ok "Git: $(git --version)"
  else
    status_warn "Git not found."
    add_action "Install Git via Xcode CLT ('xcode-select --install') or 'brew install git'."
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
