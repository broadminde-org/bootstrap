#!/usr/bin/env bash
# lib/caps.sh — capability-gating for init.d steps.
#
# Source this file from a bootstrap runner (init.sh) and call
# `load_caps <config_file>` once before iterating steps. Then use
# `step_requires_caps <step_dir>` to decide whether a step should
# run.
#
# Config format (YAML):
#
#   capabilities:
#     docker: true
#     kvm: false
#     dev: false
#
# A step directory may contain a `.requires` file with one capability
# name per line (blank lines and #-comments are ignored). A step runs
# only when ALL listed capabilities are enabled. If `.requires` is
# absent, the step always runs.
#
# When the config file is missing, every capability is treated as
# enabled — backward-compatible with hosts that predate the
# capability system.

# Guard against double-sourcing.
[ -n "${_CAPS_SH_LOADED:-}" ] && return 0
export _CAPS_SH_LOADED=1

declare -A _CAP_ENABLED

# load_caps <config_file>
#
# Parses the YAML config and populates _CAP_ENABLED. Safe to call
# with a non-existent file — treats all capabilities as enabled.
load_caps() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  local cap
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([a-z_]+):[[:space:]]*true[[:space:]]*$ ]]; then
      cap="${BASH_REMATCH[1]}"
      _CAP_ENABLED["$cap"]=1
    elif [[ "$line" =~ ^[[:space:]]*([a-z_]+):[[:space:]]*false[[:space:]]*$ ]]; then
      cap="${BASH_REMATCH[1]}"
      _CAP_ENABLED["$cap"]=0
    fi
  done < "$config_file"
}

# cap_enabled <name>
#
# Returns 0 (true) if the named capability is enabled, 1 otherwise.
# Capabilities not declared in the config are treated as enabled
# (the config may only list capabilities it wants to disable).
cap_enabled() {
  local cap="$1"

  if [[ ! -v _CAP_ENABLED[$cap] ]]; then
    return 0
  fi
  [[ "${_CAP_ENABLED[$cap]}" == "1" ]]
}

# step_requires_caps <step_dir>
#
# Reads <step_dir>/.requires (if it exists) and returns 0 when every
# listed capability is enabled. Returns 1 (skip the step) when any
# required capability is disabled.
step_requires_caps() {
  local step_dir="$1"
  local requires_file="$step_dir/.requires"

  if [[ ! -f "$requires_file" ]]; then
    return 0
  fi

  local cap
  while IFS= read -r cap; do
    [[ -z "$cap" || "$cap" =~ ^[[:space:]]*# ]] && continue
    cap="${cap## }"; cap="${cap%% }"
    if ! cap_enabled "$cap"; then
      return 1
    fi
  done < "$requires_file"
  return 0
}
