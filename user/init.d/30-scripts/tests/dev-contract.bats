#!/usr/bin/env bats

setup() {
  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project/.dev" "$project/frontend"
  printf '{"private":true}\n' > "$project/frontend/package.json"
  AIR_STEP="$BATS_TEST_DIRNAME/../scripts/dev.d/40-air.sh"
  BACKEND_STEP="$BATS_TEST_DIRNAME/../scripts/dev.d/45-backend.sh"
  DEV_SCRIPT="$BATS_TEST_DIRNAME/../scripts/dev"
}

@test "invalid HMR hostname fails before dev startup" {
  run env HOME="$BATS_TEST_TMPDIR/home" FRONTEND_HMR_HOST=portal..example \
    bash -c 'cd "$1" && exec "$2"' _ "$project" "$DEV_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid FRONTEND_HMR_HOST hostname"* ]]
}

@test "Caddy HMR discovery fails clearly when central config is missing" {
  run env HOME="$BATS_TEST_TMPDIR/home" DEV_CADDY_HOST_PREFIX=portal.dev \
    bash -c 'cd "$1" && exec "$2"' _ "$project" "$DEV_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEV_CADDY_HOST_PREFIX requires"*"central.json"* ]]
}

@test "custom backend configuration prevents Air from starting" {
  touch "$project/.air.toml"
  run env PROJECT_DIR="$project" DEV_DIR="$project/.dev" \
    FRONTEND_DIR="$project/frontend" DETECTED_APP=fixture DEV_BACKEND_CMD=true \
    bash "$AIR_STEP" up
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_BACKEND_CMD takes precedence over Air"* ]]
  [ ! -f "$project/.dev/backend.pid" ]
}

@test "failed custom backend startup reports its log path and cleans up" {
  run env PROJECT_DIR="$project" DEV_DIR="$project/.dev" \
    FRONTEND_DIR="$project/frontend" DETECTED_APP=fixture DEV_BACKEND_CMD=false \
    LISTEN_ADDR=:59173 BACKEND_PORT_FILE="$project/.dev/backend.port" \
    FRONTEND_PORT_FILE="$project/.dev/frontend.port" \
    bash "$BACKEND_STEP" up
  [ "$status" -ne 0 ]
  [[ "$output" == *"backend.log"* ]]
  [ -f "$project/.dev/backend.log" ]
  # The failed process must not be left running; its pidfile is removed.
  [ ! -f "$project/.dev/backend.pid" ]
  [ ! -f "$project/.dev/backend.pid.pgid" ]
}

@test "Caddy HMR discovery fails clearly on invalid central.json" {
  home="$BATS_TEST_TMPDIR/home2"
  mkdir -p "$home/infra/caddy"
  printf 'not json\n' > "$home/infra/caddy/central.json"
  run env HOME="$home" DEV_CADDY_HOST_PREFIX=portal.dev \
    bash -c 'cd "$1" && exec "$2"' _ "$project" "$DEV_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or invalid base_domain"* ]]
}

@test "absolute FRONTEND_DIR is honored in root detection diagnostics" {
  empty_project="$BATS_TEST_TMPDIR/empty-project"
  mkdir -p "$empty_project"
  run env HOME="$BATS_TEST_TMPDIR/home3" FRONTEND_DIR=/elsewhere/ui \
    bash -c 'cd "$1" && exec "$2"' _ "$empty_project" "$DEV_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a project root"* ]]
  [[ "$output" == *"/elsewhere/ui/package.json"* ]]
  [[ "$output" != *"$empty_project//elsewhere"* ]]
}
