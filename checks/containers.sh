#!/usr/bin/env bash
#
# checks/containers.sh
# Docker & container health (read-only, SAFE)
# Category: Software
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
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

  # Disk usage summary — one in-shell pass over the captured table
  # (issue #98): fields 4-5 of each keyed row, same as the three
  # retired echo|awk '{print $4, $5}' extractions.
  local disk_usage
  disk_usage=$(docker system df 2>/dev/null || true)
  if [ -n "$disk_usage" ]; then
    local images_size="" containers_size="" volumes_size=""
    local _duline _du1 _du2 _du3 _du4 _du5 _durest
    while IFS= read -r _duline; do
      read -r _du1 _du2 _du3 _du4 _du5 _durest <<< "$_duline"
      case "$_duline" in
        *Images*)         images_size="${_du4} ${_du5}" ;;
        *Containers*)     containers_size="${_du4} ${_du5}" ;;
        *"Local Volumes"*) volumes_size="${_du4} ${_du5}" ;;
      esac
    done <<< "$disk_usage"
    status_info "Docker disk usage — Images: ${images_size:-?}, Containers: ${containers_size:-?}, Volumes: ${volumes_size:-?}"
  fi

  # Dangling images — count in-shell, no wc|tr pipeline (issue #98).
  local dangling_images=0 _dc_out _dcline
  _dc_out=$(docker images -f "dangling=true" -q 2>/dev/null || true)
  while IFS= read -r _dcline; do
    [ -n "$_dcline" ] && dangling_images=$((dangling_images + 1))
  done <<< "$_dc_out"
  if (( dangling_images > 0 )); then
    status_warn "Dangling Docker images: ${dangling_images}"
    add_action "Clean dangling Docker images: docker image prune"
  else
    status_ok "No dangling Docker images."
  fi

  # Dangling volumes
  local dangling_volumes=0
  _dc_out=$(docker volume ls -f "dangling=true" -q 2>/dev/null || true)
  while IFS= read -r _dcline; do
    [ -n "$_dcline" ] && dangling_volumes=$((dangling_volumes + 1))
  done <<< "$_dc_out"
  if (( dangling_volumes > 0 )); then
    status_warn "Dangling Docker volumes: ${dangling_volumes}"
    add_action "Clean dangling Docker volumes: docker volume prune"
  else
    status_ok "No dangling Docker volumes."
  fi

  # Stopped containers
  local stopped_containers=0
  _dc_out=$(docker ps -f "status=exited" -q 2>/dev/null || true)
  while IFS= read -r _dcline; do
    [ -n "$_dcline" ] && stopped_containers=$((stopped_containers + 1))
  done <<< "$_dc_out"
  if (( stopped_containers > 0 )); then
    status_info "Stopped Docker containers: ${stopped_containers}"
  else
    status_ok "No stopped containers."
  fi
}
