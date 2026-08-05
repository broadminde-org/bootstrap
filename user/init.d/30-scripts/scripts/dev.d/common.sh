# shellcheck shell=bash
# common.sh — Shared helpers for dev and dev.d/* steps
#
# Source at the top of any dev.d/ step:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# The caller (scripts/dev) must export: PROJECT_DIR, DEV_DIR, FRONTEND_DIR.

# Colors (disabled when stdout is not a TTY)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log()      { echo -e "${BLUE}==>${NC} $*"; }
ok()       { echo -e "${GREEN}  ✓${NC} $*"; }
warn()     { echo -e "${YELLOW}  ⚠${NC} $*"; }
log_skip() { echo -e "${YELLOW}  ⏭${NC} $*"; }
fail()     { echo -e "${RED}  ✗${NC} $*" >&2; }

# wait_for_port <port> [host] [timeout_s] [label] — TCP connect probe loop.
wait_for_port() {
  local port="$1" host="${2:-localhost}" timeout="${3:-30}" label="${4:-service}"
  local start
  start=$(date +%s)
  while true; do
    if bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
      ok "${label} ready on :${port} ($(( $(date +%s) - start ))s)"
      return 0
    fi
    if [[ $(( $(date +%s) - start )) -ge $timeout ]]; then
      fail "${label} not ready after ${timeout}s"
      return 1
    fi
    sleep 1
  done
}

# wait_for_healthz <port> [pid] [timeout_s] [label] [path] — health probe
# loop (default path /healthz); fails early if the given pid dies.
wait_for_healthz() {
  local port="$1" pid="${2:-}" timeout="${3:-30}" label="${4:-Go backend}" path="${5:-/healthz}"
  local start
  start=$(date +%s)
  while true; do
    if curl -sf "http://localhost:${port}${path}" >/dev/null 2>&1; then
      ok "${label} ready on :${port} ($(( $(date +%s) - start ))s)"
      return 0
    fi
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      fail "${label} exited unexpectedly"
      return 1
    fi
    if [[ $(( $(date +%s) - start )) -ge $timeout ]]; then
      fail "${label} not ready after ${timeout}s"
      return 1
    fi
    sleep 1
  done
}

# kill_pid <pidfile> <label> — kill a process recorded in a pidfile,
# including its whole process group when it was started via setsid.
kill_pid() {
  local pidfile="$1" label="$2"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid=$(cat "$pidfile" 2>/dev/null || echo "")
    if [[ -n "$pid" ]]; then
      local pgid
      pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || echo "")
      if [[ -n "$pgid" && "$pgid" != "0" ]]; then
        echo "Stopping ${label} (PID ${pid}, PGID ${pgid})..."
        kill -- "-${pgid}" 2>/dev/null || true
        for _ in $(seq 1 10); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.5
        done
        kill -0 "$pid" 2>/dev/null && kill -9 -- "-${pgid}" 2>/dev/null || true
      elif kill -0 "$pid" 2>/dev/null; then
        echo "Stopping ${label} (PID ${pid})..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$pidfile"
  fi
}

# rotate_log <file> — mv non-empty log to .1, truncate the original.
rotate_log() {
  local log="$1"
  if [[ -f "$log" ]]; then
    local size
    size=$(stat --format=%s "$log" 2>/dev/null || echo 0)
    if [[ "$size" -gt 0 ]]; then
      mv -f "$log" "${log}.1"
    fi
  fi
  : > "$log"
}

# own_port_pids <port> — print PIDs owned by the current user on a port.
own_port_pids() {
  local port="$1"
  lsof -ti -a -u "${USER}" ":${port}" 2>/dev/null || true
}

# compose_cmd <args...> — docker compose against the project's compose file.
compose_cmd() {
  docker compose -f "${PROJECT_DIR}/docker-compose.yml" "$@"
}

has_compose()  { [[ -f "${PROJECT_DIR}/docker-compose.yml" ]]; }
has_air()            { [[ -f "${PROJECT_DIR}/.air.toml" || -f "${PROJECT_DIR}/backend/.air.toml" ]]; }
has_uv_project()     { [[ -f "${PROJECT_DIR}/pyproject.toml" || -f "${PROJECT_DIR}/backend/pyproject.toml" ]]; }
has_custom_backend() { [[ -n "${DEV_BACKEND_CMD:-}" ]]; }
has_frontend() { [[ -f "${FRONTEND_DIR}/package.json" ]]; }
