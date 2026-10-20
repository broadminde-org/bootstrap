#!/usr/bin/env bats
# Contract tests for private GitHub package registry auth.

@test "GHCR login uses the PAT on stdin and secures Docker config" {
  local home fake_bin docker_args docker_password access_script
  home="$BATS_TEST_TMPDIR/home"
  fake_bin="$BATS_TEST_TMPDIR/bin"
  docker_args="$BATS_TEST_TMPDIR/docker-args"
  docker_password="$BATS_TEST_TMPDIR/docker-password"
  access_script="$BATS_TEST_DIRNAME/../scripts/github-access"
  mkdir -p "$fake_bin" "$home"

  cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'fixture-user\n'
EOF
  cat > "$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$GHCR_DOCKER_ARGS_FILE"
password="$(</dev/stdin)"
printf '%s' "$password" > "$GHCR_DOCKER_PASSWORD_FILE"
printf '{}\n' > "$DOCKER_CONFIG/config.json"
EOF
  chmod +x "$fake_bin/gh" "$fake_bin/docker"

  # shellcheck disable=SC2016  # $1 is expanded by the child bash, not bats.
  run env \
    HOME="$home" \
    DOCKER_CONFIG="$home/.docker" \
    GHCR_DOCKER_ARGS_FILE="$docker_args" \
    GHCR_DOCKER_PASSWORD_FILE="$docker_password" \
    PATH="$fake_bin:$PATH" \
    bash -c 'source "$1"; configure_ghcr fixture-pat' _ "$access_script"

  [ "$status" -eq 0 ]
  [[ "$output" == *"GHCR authentication configured"* ]]
  [ "$(<"$docker_args")" = "login ghcr.io --username fixture-user --password-stdin" ]
  [ "$(<"$docker_password")" = "fixture-pat" ]
  [ "$(stat -c %a "$home/.docker/config.json")" = "600" ]
}

@test "github-access clear packages works without a bootstrap checkout" {
  local home access_script
  home="$BATS_TEST_TMPDIR/clear-home"
  access_script="$BATS_TEST_DIRNAME/../scripts/github-access"
  mkdir -p "$home"

  run env HOME="$home" BOOTSTRAP_ROOT="$BATS_TEST_TMPDIR/no-bootstrap" \
    PATH="$PATH" bash "$access_script" clear packages

  [ "$status" -eq 0 ]
  [[ "$output" == *"No packages credentials stored"* ]]
}

@test "github-access setup clearly requires bootstrap checkout" {
  local home access_script
  home="$BATS_TEST_TMPDIR/setup-home"
  access_script="$BATS_TEST_DIRNAME/../scripts/github-access"
  mkdir -p "$home"

  run env HOME="$home" BOOTSTRAP_ROOT="$BATS_TEST_TMPDIR/no-bootstrap" \
    bash "$access_script" setup

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires the bootstrap checkout"* ]]
}

@test "github-access source-rw clearly requires bootstrap checkout" {
  local home access_script
  home="$BATS_TEST_TMPDIR/source-rw-home"
  access_script="$BATS_TEST_DIRNAME/../scripts/github-access"
  mkdir -p "$home"

  run env HOME="$home" BOOTSTRAP_ROOT="$BATS_TEST_TMPDIR/no-bootstrap" \
    bash "$access_script" source-rw

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires the bootstrap checkout"* ]]
}

@test "bootstrap-access clearly requires bootstrap checkout" {
  local home access_script
  home="$BATS_TEST_TMPDIR/bootstrap-access-home"
  access_script="$BATS_TEST_DIRNAME/../scripts/bootstrap-access"
  mkdir -p "$home"

  run env HOME="$home" BOOTSTRAP_ROOT="$BATS_TEST_TMPDIR/no-bootstrap" \
    bash "$access_script"

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires the bootstrap checkout"* ]]
}

setup() {
  fixture_home="$BATS_TEST_TMPDIR/fixture-home"
  fixture_bin="$BATS_TEST_TMPDIR/fixture-bin"
  missing_root="$BATS_TEST_TMPDIR/nonexistent-bootstrap"
  access_script="$BATS_TEST_DIRNAME/../scripts/github-access"
  mkdir -p "$fixture_home/.config/gh" "$fixture_home/.docker" "$fixture_bin"
  printf 'fixture-packages\n' > "$fixture_home/.config/gh/broadminde-packages.token"
  printf 'fixture-source\n' > "$fixture_home/.config/gh/broadminde-source-rw.token"
  printf '%s\n' 'other=value' '@broadminde-org:registry=https://npm.pkg.github.com' \
    '//npm.pkg.github.com/:_authToken=fixture-packages' \
    '# unrelated //npm.pkg.github.com/:_authToken=keep' > "$fixture_home/.npmrc"
  printf '%s\n' '{"auths":{"ghcr.io":{"auth":"operator-owned"}}}' > "$fixture_home/.docker/config.json"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$DOCKER_CALLS"' > "$fixture_bin/docker"
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "$*" in' \
    '  "auth status --hostname github.com") [[ "${GH_AUTH_FAIL:-}" != 1 ]] ;;' \
    '  "api user --jq "*) printf "  authenticated as fixture-user\n" ;;' \
    '  *) exit 1 ;;' \
    'esac' > "$fixture_bin/gh"
  chmod +x "$fixture_bin/docker" "$fixture_bin/gh"
  docker_calls="$BATS_TEST_TMPDIR/docker-calls"
}

run_access() {
  run env -u BROADMINDE_PACKAGES_TOKEN -u BROADMINDE_SOURCE_RW_TOKEN \
    HOME="$fixture_home" BOOTSTRAP_ROOT="$missing_root" \
    DOCKER_CALLS="$docker_calls" PATH="$fixture_bin:$PATH" \
    bash "$access_script" "$@"
}

@test "auth uses gh without the checkout and leaves credentials intact" {
  run_access auth
  [ "$status" -eq 0 ]
  [[ "$output" == *"authenticated as fixture-user"* ]]
  [ -f "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ -f "$fixture_home/.docker/config.json" ]
  [ ! -e "$docker_calls" ]
}

@test "auth fails cleanly without a terminal when gh is unauthenticated" {
  GH_AUTH_FAIL=1
  export GH_AUTH_FAIL
  run_access auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"not attached to a terminal"* ]]
  [ -f "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ ! -e "$docker_calls" ]
}

@test "status reports populated credentials without the checkout" {
  run_access status
  [ "$status" -eq 0 ]
  [[ "$output" == *"user runner not found"* ]]
  [[ "$output" == *"present: GitHub Packages"* ]]
  [[ "$output" == *"present: source RW"* ]]
  [[ "$output" == *"present: $fixture_home/.docker/config.json"* ]]
  [ ! -e "$docker_calls" ]
}

@test "clear packages removes only owned token and npm keys, never Docker auth" {
  run_access clear packages
  [ "$status" -eq 0 ]
  [ ! -e "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ -f "$fixture_home/.config/gh/broadminde-source-rw.token" ]
  [ "$(<"$fixture_home/.npmrc")" = $'other=value\n# unrelated //npm.pkg.github.com/:_authToken=keep' ]
  [ "$(<"$fixture_home/.docker/config.json")" = '{"auths":{"ghcr.io":{"auth":"operator-owned"}}}' ]
  [ ! -e "$docker_calls" ]
}

@test "clear source-rw leaves package and Docker credentials untouched" {
  run_access clear source-rw
  [ "$status" -eq 0 ]
  [ ! -e "$fixture_home/.config/gh/broadminde-source-rw.token" ]
  [ -f "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ -f "$fixture_home/.npmrc" ]
  [ -f "$fixture_home/.docker/config.json" ]
  [ ! -e "$docker_calls" ]
}

@test "clear --all is checkout-independent and preserves Docker auth" {
  run_access clear --all
  [ "$status" -eq 0 ]
  [ ! -e "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ ! -e "$fixture_home/.config/gh/broadminde-source-rw.token" ]
  [ -f "$fixture_home/.docker/config.json" ]
  [ ! -e "$docker_calls" ]
}

@test "invalid clear target fails without altering credentials" {
  run_access clear invalid
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown clear target"* ]]
  [ -f "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ -f "$fixture_home/.docker/config.json" ]
  [ ! -e "$docker_calls" ]
}

@test "all reprovision commands fail before changing credentials when checkout is missing" {
  local command
  for command in setup deploy-keys packages npm source-rw; do
    run_access "$command"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires the bootstrap checkout"* ]]
  done
  [ -f "$fixture_home/.config/gh/broadminde-packages.token" ]
  [ -f "$fixture_home/.docker/config.json" ]
  [ ! -e "$docker_calls" ]
}
