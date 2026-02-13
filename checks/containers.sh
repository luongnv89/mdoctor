#!/usr/bin/env bash
#
# checks/containers.sh
# Docker & container health (read-only, SAFE)
# Category: Software
#

check_containers() {
  step "Docker & Containers"

  # Check if Docker is installed
  if ! command -v docker >/dev/null 2>&1; then
    status_info "Docker is not installed. Skipping container checks."
    return 0
  fi

  # Docker version
  local docker_ver
  docker_ver=$(docker --version 2>/dev/null || echo "Unknown")
  status_info "Docker: ${docker_ver}"

  # Check if Docker daemon is running
  if ! docker info >/dev/null 2>&1; then
    status_warn "Docker is installed but the daemon is not running."
    add_action "Start Docker Desktop or run: open -a Docker"
    return 0
  fi

  status_ok "Docker daemon is running."

  # Disk usage summary
  local disk_usage
  disk_usage=$(docker system df 2>/dev/null || true)
  if [ -n "$disk_usage" ]; then
    local images_size containers_size volumes_size
    images_size=$(echo "$disk_usage" | awk '/Images/ {print $4, $5}')
    containers_size=$(echo "$disk_usage" | awk '/Containers/ {print $4, $5}')
    volumes_size=$(echo "$disk_usage" | awk '/Local Volumes/ {print $4, $5}')
    status_info "Docker disk usage — Images: ${images_size:-?}, Containers: ${containers_size:-?}, Volumes: ${volumes_size:-?}"
  fi

  # Dangling images
  local dangling_images
  dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
  if (( dangling_images > 0 )); then
    status_warn "Dangling Docker images: ${dangling_images}"
    add_action "Clean dangling Docker images: docker image prune"
  else
    status_ok "No dangling Docker images."
  fi

  # Dangling volumes
  local dangling_volumes
  dangling_volumes=$(docker volume ls -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
  if (( dangling_volumes > 0 )); then
    status_warn "Dangling Docker volumes: ${dangling_volumes}"
    add_action "Clean dangling Docker volumes: docker volume prune"
  else
    status_ok "No dangling Docker volumes."
  fi

  # Stopped containers
  local stopped_containers
  stopped_containers=$(docker ps -f "status=exited" -q 2>/dev/null | wc -l | tr -d ' ')
  if (( stopped_containers > 0 )); then
    status_info "Stopped Docker containers: ${stopped_containers}"
  else
    status_ok "No stopped containers."
  fi
}
