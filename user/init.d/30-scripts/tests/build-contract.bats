#!/usr/bin/env bats
# Focused contract tests for strict generation and Docker aliases.
# shellcheck disable=SC2016

setup() {
  BUILD_SCRIPT="$BATS_TEST_DIRNAME/../scripts/build"
  SWAG_STEP="$BATS_TEST_DIRNAME/../scripts/build.d/15-swag.sh"
  GENERATE_STEP="$BATS_TEST_DIRNAME/../scripts/build.d/20-go-generate.sh"
  FIXTURE="$BATS_TEST_TMPDIR/project"
  mkdir -p "$FIXTURE"
}

@test "strict pinned Swagger uses go run and validates required comma-delimited paths" {
  mkdir -p "$FIXTURE/backend" "$FIXTURE/bin" "$FIXTURE/docs/swagger"
  touch "$FIXTURE/backend/main.go"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_CALLS"
if [[ "$1" == run ]]; then
  while (($#)); do
    if [[ "$1" == -o ]]; then output="$2"; break; fi
    shift
  done
  printf '{"paths":{"/api/apps":{},"/api/apps/{slug}":{},"/api/config":{}}}\n' > "$output/swagger.json"
else
  exit "${MOCK_GO_GENERATE_STATUS:-0}"
fi
EOF
  chmod +x "$FIXTURE/bin/go"
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_CALLS="$FIXTURE/calls" \
    BUILD_HOOK_PROJECT_DIR="$FIXTURE" BUILD_HOOK_APP=fixture \
    BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" STEP_EVENTS_LOG="$FIXTURE/events.jsonl" \
    BUILD_HOOK_GENERATE_STRICT=true BUILD_HOOK_SWAG_VERSION=v1.16.4 \
    BUILD_HOOK_SWAG_DIR=backend BUILD_HOOK_SWAG_MAIN=main.go \
    BUILD_HOOK_SWAG_OUTPUT=docs/swagger \
    BUILD_HOOK_SWAG_REQUIRED_PATHS='/api/apps,/api/apps/{slug},/api/config' \
    BUILD_HOOK_SWAG_PARSE_DEPENDENCY=false BUILD_HOOK_SWAG_PARSE_INTERNAL=false \
    bash "$SWAG_STEP"
  [ "$status" -eq 0 ]
  [ -f "$FIXTURE/docs/swagger/swagger.json" ]
  [[ "$(<"$FIXTURE/calls")" == *'github.com/swaggo/swag/cmd/swag@v1.16.4 init'* ]]
  [[ "$output" != *'swag init'* ]]
}

@test "strict Swagger fails for missing required path and emits step_fail" {
  mkdir -p "$FIXTURE/backend" "$FIXTURE/bin"
  touch "$FIXTURE/backend/main.go"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; break; fi
  shift
done
printf '{"paths":{"/present":{}}}\n' > "$output/swagger.json"
EOF
  chmod +x "$FIXTURE/bin/go"
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" BUILD_HOOK_GENERATE_STRICT=true \
    BUILD_HOOK_SWAG_VERSION=v1.16.4 BUILD_HOOK_SWAG_DIR=backend \
    BUILD_HOOK_SWAG_MAIN=main.go BUILD_HOOK_SWAG_OUTPUT=docs/swagger \
    BUILD_HOOK_SWAG_REQUIRED_PATHS=/required bash "$SWAG_STEP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Required Swagger path missing: /required"* ]]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_fail"'* ]]
}

@test "strict Swagger fails on malformed JSON and on missing swagger.json" {
  mkdir -p "$FIXTURE/backend" "$FIXTURE/bin"
  touch "$FIXTURE/backend/main.go"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; break; fi
  shift
done
if [[ "${MOCK_NO_JSON:-0}" == 1 ]]; then exit 0; fi
printf 'not json at all\n' > "$output/swagger.json"
EOF
  chmod +x "$FIXTURE/bin/go"
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" BUILD_HOOK_GENERATE_STRICT=true \
    BUILD_HOOK_SWAG_VERSION=v1.16.4 BUILD_HOOK_SWAG_DIR=backend \
    BUILD_HOOK_SWAG_MAIN=main.go BUILD_HOOK_SWAG_OUTPUT=docs/swagger \
    bash "$SWAG_STEP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Malformed Swagger JSON"* ]]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_fail"'* ]]

  rm -f "$FIXTURE/docs/swagger/swagger.json"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_NO_JSON=1 BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" BUILD_HOOK_GENERATE_STRICT=true \
    BUILD_HOOK_SWAG_VERSION=v1.16.4 BUILD_HOOK_SWAG_DIR=backend \
    BUILD_HOOK_SWAG_MAIN=main.go BUILD_HOOK_SWAG_OUTPUT=docs/swagger \
    bash "$SWAG_STEP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Swagger JSON missing"* ]]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_fail"'* ]]
}

@test "strict Swagger trims whitespace around required paths" {
  mkdir -p "$FIXTURE/backend" "$FIXTURE/bin"
  touch "$FIXTURE/backend/main.go"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; break; fi
  shift
done
printf '{"paths":{"/api/apps":{},"/api/config":{}}}\n' > "$output/swagger.json"
EOF
  chmod +x "$FIXTURE/bin/go"
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" BUILD_HOOK_GENERATE_STRICT=true \
    BUILD_HOOK_SWAG_VERSION=v1.16.4 BUILD_HOOK_SWAG_DIR=backend \
    BUILD_HOOK_SWAG_MAIN=main.go BUILD_HOOK_SWAG_OUTPUT=docs/swagger \
    BUILD_HOOK_SWAG_REQUIRED_PATHS=' /api/apps , /api/config ' \
    bash "$SWAG_STEP"
  [ "$status" -eq 0 ]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_ok"'* ]]
}

@test "alias equal to the primary tag is not tagged or pushed twice" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker"
  : > "$FIXTURE/docker.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" \
    IMAGE_REGISTRY=registry.example IMAGE_ALIAS_TAGS=sha-abc123 IMAGE_NAME=fixture \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" \
    --docker-only --tag sha-abc123
  [ "$status" -eq 0 ]
  [ "$(grep -c '^push registry.example/fixture:sha-abc123$' "$FIXTURE/docker.calls")" -eq 1 ]
  # No alias tag invocations at all when the alias collides with the primary tag.
  if grep -q '^tag ' "$FIXTURE/docker.calls"; then
    return 1
  fi
}

@test "go generate failure warns by default and is fatal in strict mode" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/go.mod"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$FIXTURE/bin/go"
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" bash "$GENERATE_STEP"
  [ "$status" -eq 0 ]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_warn"'* ]]

  : > "$FIXTURE/events.jsonl"
  run env PATH="$FIXTURE/bin:$PATH" BUILD_HOOK_PROJECT_DIR="$FIXTURE" \
    BUILD_HOOK_APP=fixture BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" \
    STEP_EVENTS_LOG="$FIXTURE/events.jsonl" BUILD_HOOK_GENERATE_STRICT=true \
    bash "$GENERATE_STEP"
  [ "$status" -ne 0 ]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_fail"'* ]]
}

@test "go generate skips when no Go module exists" {
  : > "$FIXTURE/build.md"
  : > "$FIXTURE/events.jsonl"
  run env BUILD_HOOK_PROJECT_DIR="$FIXTURE" BUILD_HOOK_APP=fixture \
    BUILD_HOOK_LOG_FILE="$FIXTURE/build.md" STEP_EVENTS_LOG="$FIXTURE/events.jsonl" \
    bash "$GENERATE_STEP"
  [ "$status" -eq 0 ]
  [[ "$(<"$FIXTURE/events.jsonl")" == *'"event":"step_skip"'* ]]
}

@test "Docker aliases are tagged locally and in registry, pushed once, and hook runs" {
  mkdir -p "$FIXTURE/bin" "$FIXTURE/scripts/build-hooks"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  cat > "$FIXTURE/scripts/build-hooks/post-docker" <<'EOF'
#!/usr/bin/env bash
printf 'hook\n' >> "$MOCK_HOOK_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker" "$FIXTURE/scripts/build-hooks/post-docker"
  : > "$FIXTURE/docker.calls"
  : > "$FIXTURE/hook.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" \
    MOCK_HOOK_CALLS="$FIXTURE/hook.calls" IMAGE_REGISTRY=registry.example \
    IMAGE_ALIAS_TAGS=main,stable IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" \
    --docker-only --tag sha-abc123
  [ "$status" -eq 0 ]
  [ "$(grep -c '^push registry.example/fixture:sha-abc123$' "$FIXTURE/docker.calls")" -eq 1 ]
  [ "$(grep -c '^push registry.example/fixture:main$' "$FIXTURE/docker.calls")" -eq 1 ]
  [ "$(grep -c '^push registry.example/fixture:stable$' "$FIXTURE/docker.calls")" -eq 1 ]
  if grep -q '^push registry.example/fixture:v' "$FIXTURE/docker.calls"; then
    return 1
  fi
  grep -q '^tag fixture:sha-abc123 fixture:main$' "$FIXTURE/docker.calls"
  grep -q '^tag registry.example/fixture:sha-abc123 registry.example/fixture:main$' "$FIXTURE/docker.calls"
  [ "$(<"$FIXTURE/hook.calls")" = hook ]
}

@test "no-push still creates local alias but pushes neither primary nor aliases" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker"
  : > "$FIXTURE/docker.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" \
    IMAGE_ALIAS_TAGS=main IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" \
    --docker-only --tag sha-abc123 --no-push
  [ "$status" -eq 0 ]
  grep -q '^tag fixture:sha-abc123 fixture:main$' "$FIXTURE/docker.calls"
  if grep -q '^push ' "$FIXTURE/docker.calls"; then
    return 1
  fi
}

@test "invalid alias is rejected before Docker build" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker"
  : > "$FIXTURE/docker.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" \
    IMAGE_ALIAS_TAGS='valid,bad:tag' IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" --docker-only
  [ "$status" -ne 0 ]
  [[ "$output" == *'Invalid Docker alias tag: bad:tag'* ]]
  [ ! -s "$FIXTURE/docker.calls" ]
}

@test "caller IMAGE_REGISTRY overrides project .env (throwaway-registry path)" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker"
  printf 'IMAGE_REGISTRY=registry.from-dotenv\n' > "$FIXTURE/.env"
  : > "$FIXTURE/docker.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" \
    IMAGE_REGISTRY=localhost:5555 IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" \
    --docker-only --tag sha-abc123
  [ "$status" -eq 0 ]
  grep -q '^push localhost:5555/fixture:sha-abc123$' "$FIXTURE/docker.calls"
  if grep -q 'registry.from-dotenv' "$FIXTURE/docker.calls"; then
    return 1
  fi
}

@test "project .env IMAGE_REGISTRY applies when caller does not set it" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/docker"
  printf 'IMAGE_REGISTRY=registry.from-dotenv\n' > "$FIXTURE/.env"
  : > "$FIXTURE/docker.calls"
  run env -u IMAGE_REGISTRY PATH="$FIXTURE/bin:$PATH" \
    MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" \
    --docker-only --tag sha-abc123
  [ "$status" -eq 0 ]
  grep -q '^push registry.from-dotenv/fixture:sha-abc123$' "$FIXTURE/docker.calls"
}

@test "strict Swagger generation failure prevents binary and image build" {
  mkdir -p "$FIXTURE/backend" "$FIXTURE/bin"
  touch "$FIXTURE/backend/main.go" "$FIXTURE/backend/go.mod" "$FIXTURE/Dockerfile"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GO_CALLS"
exit 1
EOF
  cat > "$FIXTURE/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
EOF
  chmod +x "$FIXTURE/bin/go" "$FIXTURE/bin/docker"
  : > "$FIXTURE/go.calls"
  : > "$FIXTURE/docker.calls"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_GO_CALLS="$FIXTURE/go.calls" \
    MOCK_DOCKER_CALLS="$FIXTURE/docker.calls" BUILD_SWAG_VERSION=v1.16.4 \
    BUILD_GENERATE_STRICT=true IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT"
  [ "$status" -ne 0 ]
  grep -q '^run github.com/swaggo/swag/cmd/swag@v1.16.4 ' "$FIXTURE/go.calls"
  if grep -q '^build ' "$FIXTURE/docker.calls"; then
    return 1
  fi
}

@test "build uses configured frontend directory without falling back to repository root" {
  mkdir -p "$FIXTURE/ui/node_modules"
  cat > "$FIXTURE/ui/package.json" <<'EOF'
{"name":"fixture-ui","scripts":{"build":"mkdir -p dist && touch dist/index.html"}}
EOF
  run env IMAGE_NAME=fixture FRONTEND_DIR=ui bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" --frontend-only
  [ "$status" -eq 0 ]
  [ -f "$FIXTURE/dist/frontend/index.html" ]
  grep -Fq "Frontend Directory | $FIXTURE/ui" "$FIXTURE/build-results/latest/build.md"
}

@test "binary build defaults to the detected package and app filename" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/go.mod"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_GO_CALLS"
EOF
  chmod +x "$FIXTURE/bin/go"
  run env -u GO_BUILD_PKG -u BUILD_BINARY_NAME PATH="$FIXTURE/bin:$PATH" \
    MOCK_GO_CALLS="$FIXTURE/go.calls" IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" --binary-only
  [ "$status" -eq 0 ]
  grep -Fxq '.' "$FIXTURE/go.calls"
  grep -Fxq "$FIXTURE/dist/fixture" "$FIXTURE/go.calls"
}

@test "binary build uses project package, output filename, and cross-build settings" {
  mkdir -p "$FIXTURE/bin" "$FIXTURE/cmd/example"
  touch "$FIXTURE/go.mod"
  cat > "$FIXTURE/.env" <<'EOF'
GO_BUILD_PKG=./cmd/example
BUILD_BINARY_NAME=example-freebsd
GOOS=freebsd
GOARCH=amd64
CGO_ENABLED=0
EOF
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_GO_CALLS"
printf '%s/%s/%s\n' "$GOOS" "$GOARCH" "$CGO_ENABLED" >> "$MOCK_GO_CALLS"
EOF
  chmod +x "$FIXTURE/bin/go"
  run env -u GO_BUILD_PKG -u BUILD_BINARY_NAME -u GOOS -u GOARCH -u CGO_ENABLED \
    PATH="$FIXTURE/bin:$PATH" MOCK_GO_CALLS="$FIXTURE/go.calls" \
    IMAGE_NAME=fixture bash -c 'cd "$1" && shift && exec "$@"' _ \
    "$FIXTURE" "$BUILD_SCRIPT" --binary-only
  [ "$status" -eq 0 ]
  grep -Fxq './cmd/example' "$FIXTURE/go.calls"
  grep -Fxq "$FIXTURE/dist/example-freebsd" "$FIXTURE/go.calls"
  grep -Fxq 'freebsd/amd64/0' "$FIXTURE/go.calls"
}

@test "binary filename override cannot escape dist" {
  mkdir -p "$FIXTURE/bin"
  touch "$FIXTURE/go.mod"
  cat > "$FIXTURE/bin/go" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' > "$MOCK_GO_CALLS"
EOF
  chmod +x "$FIXTURE/bin/go"
  run env PATH="$FIXTURE/bin:$PATH" MOCK_GO_CALLS="$FIXTURE/go.calls" \
    BUILD_BINARY_NAME=../escape IMAGE_NAME=fixture bash -c \
    'cd "$1" && shift && exec "$@"' _ "$FIXTURE" "$BUILD_SCRIPT" --binary-only
  [ "$status" -ne 0 ]
  [[ "$output" == *'BUILD_BINARY_NAME must be a single filename'* ]]
  [ ! -f "$FIXTURE/go.calls" ]
}
