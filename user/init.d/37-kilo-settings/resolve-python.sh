#!/usr/bin/env bash

# Resolve an existing Python 3.10+ without installing anything or creating a
# project environment. Prefer python3 on PATH, then uv-managed installations.
resolve_kilo_python() {
  local candidate uv_cmd=''

  if candidate="$(command -v python3 2>/dev/null)" &&
      "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -x "$HOME/.local/bin/uv" ]]; then
    uv_cmd="$HOME/.local/bin/uv"
  elif candidate="$(command -v uv 2>/dev/null)"; then
    uv_cmd="$candidate"
  fi
  if [[ -n "$uv_cmd" ]]; then
    candidate="$("$uv_cmd" python find --no-project --managed-python --no-python-downloads '>=3.10' 2>/dev/null)" || candidate=''
    if [[ -n "$candidate" ]] &&
        "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  echo 'ERROR: no existing Python 3.10+ found; run ./user/init.sh 20-python to install a uv-managed interpreter.' >&2
  echo '       Alternatively, put an existing Python 3.10+ on PATH as python3.' >&2
  return 1
}
