#!/usr/bin/env bash
# lib/conf.sh — unified bootstrap configuration reader.
#
# Parses a single bootstrap.conf.yml that contains two sections:
#
#   capabilities:        # feature flags (true/false)
#     docker: true
#     dev: false
#
#   versions:            # tool version pins
#     python: "3.13"
#     go: "latest"
#
# Replaces the former caps.sh (capabilities only, bash-regex parser) and
# user/init.d/lib/versions.sh (versions only, standalone awk parser).
# Both sections are now parsed by a single section-aware awk function.
#
# Public interface:
#   load_conf [config_file]          parse and cache the config; safe to call
#                                    multiple times (idempotent after first load)
#   cap_enabled <name>               returns 0 if capability is enabled
#   step_requires_caps <step_dir>    returns 0 if all .requires caps pass
#   get_pinned_version <tool> [def]  returns pinned version string or default
#
# When no config_file is provided, load_conf infers the path from this
# script's own location: conf.sh lives at bootstrap/init.d/lib/conf.sh,
# so the default config is bootstrap/bootstrap.conf.yml.
#
# get_pinned_version auto-calls load_conf (from the default location) if the
# config has not been loaded yet — this covers step subshells that source
# lib/common.sh without the runner's explicit load_conf call being inherited.

# Guard against double-sourcing within the same shell process.
# Not exported: step sub-processes (./run.sh) must re-source conf.sh to get
# their own function definitions and array state. Exporting the guard would
# cause the guard to fire in child processes, leaving conf.sh's functions
# undefined in those shells.
[ -n "${_BOOTSTRAP_CONF_SH_LOADED:-}" ] && return 0
_BOOTSTRAP_CONF_SH_LOADED=1

declare -A _CAP_ENABLED
declare -A _TOOL_VERSION
_CONF_LOADED=0

# Infer default config path from this file's own location.
# conf.sh: bootstrap/init.d/lib/conf.sh → ../../ → bootstrap/bootstrap.conf.yml
_CONF_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEFAULT_CONF="$(cd "$_CONF_SH_DIR/../.." && pwd)/bootstrap.conf.yml"

# _parse_section <file> <section>
#
# Prints "key=value" pairs from the named YAML section using section-aware awk.
# Strips leading whitespace, inline comments, and surrounding double-quotes from
# values. Exits the section when a new top-level key (unindented) is encountered.
_parse_section() {
  local file="$1" section="$2"
  awk -v section="$section" '
    $0 ~ "^" section ":"            { in_section=1; next }
    in_section && /^[a-z_]/         { in_section=0 }
    in_section && /^[[:space:]]+[a-z_]+:/ {
      sub(/^[[:space:]]+/, "")
      key = substr($0, 1, index($0, ":") - 1)
      val = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]*#.*$/, "", val)
      gsub(/"/, "", val)
      if (key != "" && val != "") print key "=" val
    }
  ' "$file"
}

# load_conf [config_file]
#
# Parses both the capabilities: and versions: sections and caches results in
# _CAP_ENABLED and _TOOL_VERSION. Idempotent: a second call in the same shell
# process is a no-op. If no file is given, uses _DEFAULT_CONF.
#
# When the config file is missing, _CONF_LOADED remains 0: cap_enabled returns
# false for all capabilities (steps with .requires are skipped) and
# get_pinned_version returns its default (usually "latest").
load_conf() {
  [[ "$_CONF_LOADED" == "1" ]] && return 0

  local config_file="${1:-$_DEFAULT_CONF}"

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    echo "Warning: bootstrap.conf.yml not found — all capabilities disabled, versions default to 'latest'." >&2
    return 0
  fi

  echo "Using bootstrap config: $config_file" >&2
  _CONF_LOADED=1

  local key val
  while IFS='=' read -r key val; do
    [[ -n "$key" ]] && _CAP_ENABLED["$key"]="$val"
  done < <(_parse_section "$config_file" "capabilities")

  while IFS='=' read -r key val; do
    [[ -n "$key" ]] && _TOOL_VERSION["$key"]="$val"
  done < <(_parse_section "$config_file" "versions")
}

# cap_enabled <name>
#
# Returns 0 (true) if the named capability is enabled. Returns 1 otherwise.
# If no config was loaded, all capabilities are disabled.
# Capabilities not present in the config are treated as enabled (opt-in
# gating: the config only needs to name capabilities it wants to disable).
cap_enabled() {
  local cap="$1"

  if [[ "$_CONF_LOADED" == "0" ]]; then
    return 1
  fi
  if [[ ! -v _CAP_ENABLED[$cap] ]]; then
    return 0
  fi
  [[ "${_CAP_ENABLED[$cap]}" == "true" ]]
}

# step_requires_caps <step_dir>
#
# Reads <step_dir>/.requires (if present) and returns 0 when every listed
# capability is enabled. Returns 1 (skip the step) when any required
# capability is disabled. Blank lines and # comments are ignored.
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

# get_pinned_version <tool> [default]
#
# Returns the pinned version string for <tool> from the versions: section,
# or <default> (which itself defaults to "latest") if the tool is not found.
# Auto-calls load_conf from the default location if not already loaded —
# this ensures step subshells that do not inherit the runner's load_conf call
# still get correct version data.
get_pinned_version() {
  local tool="$1"
  local default="${2:-latest}"

  if [[ "$_CONF_LOADED" == "0" ]]; then
    load_conf
  fi

  if [[ -v _TOOL_VERSION[$tool] && -n "${_TOOL_VERSION[$tool]}" ]]; then
    echo "${_TOOL_VERSION[$tool]}"
  else
    echo "$default"
  fi
}
