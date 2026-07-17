#!/usr/bin/env bash
# project.sh — central project-resolution helper
#
# Public API:
#   PROJECT_PATHS_DEFAULT  — array element used when STACK_PATHS is unset
#   project_load_paths     — populate PROJECT_PATHS_ARR from env (idempotent)
#   project_resolve [name] — echo absolute project dir; non-zero if not found
#   project_split_path dir — echo "<name>\n<entry>" for log messages
#
# Configuration:
#   export STACK_PATHS="apps,infra"      # canonical name (preferred)
#   export PROJECT_PATHS="apps,infra"    # alias accepted for back-compat
#
# Resolution order (first match wins):
#   1. CWD first — if $PWD contains a docker-compose file, use $PWD as-is.
#   2. Explicit name — search <ee_root>/<entry>/<name>/ for each entry.
#   3. Auto-detect — if CWD is under any entry, use the first path component
#      as the project name and search for it.
#   4. Fail with a friendly error.
#
# Requires REPO_ROOT (or EE_ROOT as an alias) to be set in the caller's
# environment.

if [[ -z "${_PROJECT_SH_LOADED:-}" ]]; then
  _PROJECT_SH_LOADED=1

  PROJECT_PATHS_DEFAULT="apps"

  declare -ga PROJECT_PATHS_ARR=()

  project_load_paths() {
    local raw="${STACK_PATHS:-${PROJECT_PATHS:-$PROJECT_PATHS_DEFAULT}}"
    local parsed=() out=() p
    IFS=',' read -ra parsed <<< "$raw"
    for p in "${parsed[@]}"; do
      p="${p// /}"
      [[ -z "$p" ]] && continue
      out+=("$p")
    done
    PROJECT_PATHS_ARR=("${out[@]}")
    export PROJECT_PATHS_ARR
  }

  project_resolve() {
    local name="${1:-}"
    local cwd entry full rel
    cwd="$(pwd)"

    if [[ -f "$cwd/docker-compose.yml" || -f "$cwd/docker-compose.yaml" \
       || -f "$cwd/compose.yml"     || -f "$cwd/compose.yaml" ]]; then
      echo "$cwd"
      return 0
    fi

    for entry in "${PROJECT_PATHS_ARR[@]}"; do
      if [[ -n "$name" ]]; then
        full="${REPO_ROOT:-$EE_ROOT}/$entry/$name"
        if [[ -d "$full" ]]; then
          echo "$full"
          return 0
        fi
        continue
      fi

      if [[ "$cwd" == "${REPO_ROOT:-$EE_ROOT}/$entry/"* ]]; then
        rel="${cwd#${REPO_ROOT:-$EE_ROOT}/$entry/}"
        rel="${rel%%/*}"
        if [[ -n "$rel" ]]; then
          full="${REPO_ROOT:-$EE_ROOT}/$entry/$rel"
          if [[ -d "$full" ]]; then
            echo "$full"
            return 0
          fi
        fi
      fi
    done

    echo "ERROR: no project found" >&2
    if [[ -n "$name" ]]; then
      echo "  (looked for '$name' under: ${PROJECT_PATHS_ARR[*]})" >&2
    else
      echo "  (cwd=$cwd is not under any of: ${PROJECT_PATHS_ARR[*]})" >&2
    fi
    return 1
  }

  project_split_path() {
    local dir="$1"
    local name rel
    name="$(basename "$dir")"
    for entry in "${PROJECT_PATHS_ARR[@]}"; do
      if [[ "$dir" == "${REPO_ROOT:-$EE_ROOT}/$entry" || "$dir" == "${REPO_ROOT:-$EE_ROOT}/$entry/"* ]]; then
        if [[ "$dir" == "${REPO_ROOT:-$EE_ROOT}/$entry" ]]; then
          echo "$name"
          echo "$entry"
          return 0
        fi
        rel="${dir#${REPO_ROOT:-$EE_ROOT}/$entry/}"
        rel="${rel%/*}"
        if [[ "$rel" == "$name" ]]; then
          echo "$name"
          echo "$entry"
          return 0
        fi
      fi
    done
    echo "$name"
    echo ""
  }
fi
