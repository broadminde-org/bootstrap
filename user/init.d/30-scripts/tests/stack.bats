#!/usr/bin/env bats

setup() {
  root="$BATS_TEST_TMPDIR/project with spaces"
  mkdir -p "$root/bin" "$root/scripts/stack-hooks"
  touch "$root/compose.yaml"
  printf 'name: compose-name\nservices:\n  api:\n    image: registry.invalid/api:latest\n' > "$root/compose.yaml"
  cat > "$root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
printf '<%s>\n' "$@" >> "$DOCKER_ARGV"
if [[ "$1" == compose ]]; then
  case " $* " in
    *" config --profiles "*) printf 'api\nworker\n' ;;
    *" config --services "*) printf 'api\n' ;;
    *" config --images "*) printf 'registry.invalid/api:latest\n' ;;
    *" config --format json "*)
      if [[ "${MOCK_FAIL_CONFIG_JSON:-0}" == 1 ]]; then exit 1; fi
      printf '{"name":"compose-name","services":{"api":{"image":"registry.invalid/api:latest"}}}\n' ;;
    *" config --no-interpolate "*) printf 'effective-config\n' ;;
    *" ps -q "*) : ;;
    *" ps "*) printf 'NAME STATUS\n' ;;
  esac
elif [[ "$1" == ps ]]; then
  printf 'container-id\n'
fi
MOCK
  chmod +x "$root/bin/docker"
  export DOCKER_CALLS="$BATS_TEST_TMPDIR/docker-calls"
  export DOCKER_ARGV="$BATS_TEST_TMPDIR/docker-argv"
  : > "$DOCKER_CALLS"
  : > "$DOCKER_ARGV"
  export PATH="$root/bin:$PATH"
  export STACK_SCRIPT="$BATS_TEST_DIRNAME/../scripts/stack"
}

@test "config preserves spaced compose path and passes config flags" {
  run bash -c 'cd "$1" && bash "$STACK_SCRIPT" config --no-interpolate' _ "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"effective-config"* ]]
  [[ "$(<"$DOCKER_CALLS")" == *"-f $root/compose.yaml config --no-interpolate"* ]]
}

@test "force cleanup uses explicit Compose project name" {
  run bash -c 'cd "$1" && printf chosen-project\\n | bash "$STACK_SCRIPT" -p chosen-project down' _ "$root"
  [ "$status" -eq 0 ]
  [[ "$(<"$DOCKER_CALLS")" == *"label=com.docker.compose.project=chosen-project"* ]]
}

@test "force cleanup honors COMPOSE_PROJECT_NAME over Compose name" {
  # shellcheck disable=SC2016 # The shell command expands in the child bash.
  run env COMPOSE_PROJECT_NAME=environment-project bash -c \
    'cd "$1" && printf environment-project\\n | bash "$STACK_SCRIPT" down' _ "$root"
  [ "$status" -eq 0 ]
  [[ "$(<"$DOCKER_CALLS")" == *"label=com.docker.compose.project=environment-project"* ]]
}

@test "force cleanup uses top-level Compose name before directory basename" {
  run bash -c 'cd "$1" && printf compose-name\\n | bash "$STACK_SCRIPT" down' _ "$root"
  [ "$status" -eq 0 ]
  [[ "$(<"$DOCKER_CALLS")" == *"label=com.docker.compose.project=compose-name"* ]]
}

@test "compose file path with spaces stays a single argument" {
  run bash -c 'cd "$1" && bash "$STACK_SCRIPT" config --no-interpolate' _ "$root"
  [ "$status" -eq 0 ]
  # The compose path must appear as ONE argv element, not word-split pieces.
  grep -Fx "<$root/compose.yaml>" "$DOCKER_ARGV"
  if grep -Fx '<project>' "$DOCKER_ARGV" || grep -Fx '<with>' "$DOCKER_ARGV"; then
    return 1
  fi
}

@test "down --volumes without confirmation deletes nothing" {
  run bash -c 'cd "$1" && printf wrong-name\\n | bash "$STACK_SCRIPT" down --volumes' _ "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Confirmation failed"* ]]
  # No compose down invocation at all.
  if grep -Eq '^compose .* down ' "$DOCKER_CALLS"; then
    return 1
  fi
}

@test "down --volumes with confirmation runs volume teardown via wrapper flag" {
  for hook in pre-teardown post-teardown; do
    # shellcheck disable=SC2016 # The generated hook intentionally expands at runtime.
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${0##*/}" >> "$HOOK_CALLS"\n' > "$root/scripts/stack-hooks/$hook"
    chmod +x "$root/scripts/stack-hooks/$hook"
  done
  export HOOK_CALLS="$BATS_TEST_TMPDIR/hooks"
  : > "$HOOK_CALLS"
  run bash -c 'cd "$1" && printf compose-name\\n | bash "$STACK_SCRIPT" down --volumes' _ "$root"
  [ "$status" -eq 0 ]
  # Wrapper adds -v itself; --volumes must not leak through as a pass-through arg.
  grep -Eq '^compose .* down -v --remove-orphans$' "$DOCKER_CALLS"
  if grep -q -- '--volumes' "$DOCKER_CALLS"; then
    return 1
  fi
  [ "$(<"$HOOK_CALLS")" = $'pre-teardown\npost-teardown' ]
}

@test "down -v short flag still requires confirmation" {
  run bash -c 'cd "$1" && printf wrong-name\\n | bash "$STACK_SCRIPT" down -v' _ "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Confirmation failed"* ]]
  if grep -Eq '^compose .* down ' "$DOCKER_CALLS"; then
    return 1
  fi
}

@test "quoted STACK_PROFILES value keeps its space as one profile argument" {
  printf 'STACK_PROFILES="my profile",beta\n' > "$root/.env"
  run bash -c 'cd "$1" && printf compose-name\\n | bash "$STACK_SCRIPT" down' _ "$root"
  [ "$status" -eq 0 ]
  grep -Fx '<my profile>' "$DOCKER_ARGV"
  grep -Fx '<beta>' "$DOCKER_ARGV"
  if grep -Fx '<myprofile>' "$DOCKER_ARGV"; then
    return 1
  fi
}

@test "project-name resolution warns when Compose config cannot be read" {
  export MOCK_FAIL_CONFIG_JSON=1
  run bash -c 'cd "$1" && printf y\\n | bash "$STACK_SCRIPT" down' _ "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not resolve Compose configuration"* ]]
  [[ "$output" == *"Falling back to directory name"* ]]
  [[ "$(<"$DOCKER_CALLS")" == *"label=com.docker.compose.project=project with spaces"* ]]
}

@test "update pull-first runs pull hooks once" {
  for hook in pre-pull post-pull; do
    # shellcheck disable=SC2016 # The generated hook intentionally expands at runtime.
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${0##*/}" >> "$HOOK_CALLS"\n' > "$root/scripts/stack-hooks/$hook"
    chmod +x "$root/scripts/stack-hooks/$hook"
  done
  export HOOK_CALLS="$BATS_TEST_TMPDIR/hooks"
  : > "$HOOK_CALLS"
  run bash -c 'cd "$1" && bash "$STACK_SCRIPT" update --pull-first' _ "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOOK_CALLS")" -eq 2 ]
}
