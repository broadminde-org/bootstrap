#!/usr/bin/env bats

setup() {
  COMMON="$BATS_TEST_DIRNAME/../../lib/common.sh"
  RELEASE="$BATS_TEST_DIRNAME/../scripts/release"
}

make_repo() {
  local dir="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.name Fixture
  git -C "$dir" config user.email fixture@example.invalid
  printf '0.1.0\n' > "$dir/VERSION"
  printf '# Changelog\n\n## [Unreleased]\n' > "$dir/CHANGELOG.md"
  git -C "$dir" add VERSION CHANGELOG.md
  git -C "$dir" commit -qm initial
  printf '%s\n' "$dir"
}

@test "sync reports extra executables but not ordinary files or pycache" {
  local src="$BATS_TEST_TMPDIR/src" dst="$BATS_TEST_TMPDIR/dst"
  mkdir -p "$src" "$dst/__pycache__"
  printf '#!/bin/sh\nexit 0\n' > "$src/managed-tool"
  chmod 0755 "$src/managed-tool"
  printf 'extra\n' > "$dst/local-tool"
  chmod 0755 "$dst/local-tool"
  printf 'ordinary\n' > "$dst/local.txt"
  printf 'runtime\n' > "$dst/__pycache__/module.pyc"

  run bash -c '. "$1"; sync_dir_preserve "$2" "$3"' _ "$COMMON" "$src" "$dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unmanaged destination executable: local-tool"* ]]
  [[ "$output" != *"unmanaged destination executable: managed-tool"* ]]
  [[ "$output" != *"local.txt"* ]]
  [[ "$output" != *"module.pyc"* ]]
}

@test "sync normalizes copied executable and library modes" {
  local src="$BATS_TEST_TMPDIR/src" dst="$BATS_TEST_TMPDIR/dst"
  mkdir -p "$src" "$dst"
  printf '#!/bin/sh\nexit 0\n' > "$src/tool"
  printf 'library\n' > "$src/library.sh"
  chmod 0700 "$src/tool"
  chmod 0600 "$src/library.sh"

  run bash -c '. "$1"; sync_dir_preserve "$2" "$3"' _ "$COMMON" "$src" "$dst"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$dst/tool")" = 755 ]
  [ "$(stat -c %a "$dst/library.sh")" = 644 ]
}

@test "sync does not write through destination symlinks" {
  local src="$BATS_TEST_TMPDIR/src" dst="$BATS_TEST_TMPDIR/dst" outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$src" "$dst" "$outside"
  printf 'managed\n' > "$src/file"
  ln -s "$outside" "$dst/linkdir"
  mkdir -p "$src/linkdir"
  printf 'unsafe\n' > "$src/linkdir/file"

  run bash -c '. "$1"; sync_dir_preserve "$2" "$3"' _ "$COMMON" "$src" "$dst"
  [ "$status" -ne 0 ]
  [[ "$output" == *"skipping unsafe symlink"* ]]
  [ ! -e "$outside/file" ]
}

@test "sync fails when its required source is missing" {
  local dst="$BATS_TEST_TMPDIR/dst"

  run bash -c '. "$1"; sync_dir_preserve "$2" "$3"' _ "$COMMON" "$BATS_TEST_TMPDIR/missing" "$dst"
  [ "$status" -ne 0 ]
  [[ "$output" == *"required source"* ]]
  [ ! -e "$dst" ]
}

@test "release refuses dirty worktree without changing release files" {
  local repo
  repo="$(make_repo dirty)"
  printf 'local work\n' > "$repo/notes.txt"
  git -C "$repo" add notes.txt
  printf 'untracked work\n' > "$repo/untracked.txt"

  run bash -c 'cd "$1" && "$2" patch --yes' _ "$repo" "$RELEASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Working tree has staged or unstaged changes"* ]]
  [ "$(<"$repo/VERSION")" = 0.1.0 ]
  [ ! -e "$repo/.tmp" ]
}

@test "release refuses an existing target tag before modifying files" {
  local repo
  repo="$(make_repo tagged)"
  git -C "$repo" tag v0.1.1

  run bash -c 'cd "$1" && "$2" patch --yes' _ "$repo" "$RELEASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Target tag already exists: v0.1.1"* ]]
  [ "$(<"$repo/VERSION")" = 0.1.0 ]
}

@test "release commits and tags in an isolated repo and cleans repo-local temps" {
  local repo
  repo="$(make_repo clean)"

  run bash -c 'cd "$1" && "$2" patch --yes --from-commits' _ "$repo" "$RELEASE"
  [ "$status" -eq 0 ]
  [ "$(<"$repo/VERSION")" = 0.1.1 ]
  [ "$(git -C "$repo" describe --tags --exact-match)" = v0.1.1 ]
  [ -d "$repo/.tmp" ]
  [ -z "$(compgen -G "$repo/.tmp/release.*")" ]
}

@test "release safely supports repositories without a changelog" {
  local repo
  repo="$(make_repo no-changelog)"
  git -C "$repo" rm -q CHANGELOG.md
  git -C "$repo" commit -qm 'remove changelog fixture'

  run bash -c 'cd "$1" && "$2" patch --yes' _ "$repo" "$RELEASE"
  [ "$status" -eq 0 ]
  [ "$(<"$repo/VERSION")" = 0.1.1 ]
  [ "$(git -C "$repo" describe --tags --exact-match)" = v0.1.1 ]
}

@test "release dirty override commits only release files and preserves staged work" {
  local repo
  repo="$(make_repo override)"
  printf 'keep staged\n' > "$repo/notes.txt"
  git -C "$repo" add notes.txt

  run bash -c 'cd "$1" && "$2" patch --yes --allow-dirty' _ "$repo" "$RELEASE"
  [ "$status" -eq 0 ]
  [ "$(<"$repo/VERSION")" = 0.1.1 ]
  [[ "$(git -C "$repo" status --porcelain)" == *"A  notes.txt"* ]]
}
