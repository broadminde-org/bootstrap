#!/usr/bin/env sh
set -eu
[ "$1" = --no-modify-path ]
printf 'installer\n' >> "$TEST_LOG"
cp "$TEST_FIXTURES/uv" "$HOME/.local/bin/uv"
chmod +x "$HOME/.local/bin/uv"
