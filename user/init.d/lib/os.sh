#!/usr/bin/env bash
# os.sh — portable OS/arch detection and small shims for user-tier steps.
#
# Sourced after lib/common.sh. Provides:
#   BOOTSTRAP_OS     — "darwin" or "linux" (lowercased uname -s).
#                      IMPORTANT: this value is LOWER-CASE, and is also
#                      interpolated into download filenames (go tarballs,
#                      woodpecker-cli assets), so it must never be
#                      title-cased. When comparing against it, use
#                      lowercase ("darwin"), NOT the raw `uname -s`
#                      spelling "Darwin" — the two are not interchangeable.
#   is_darwin        — true (0) when running on macOS. Prefer this for
#                      plain OS-branch tests so callers never depend on
#                      the case of BOOTSTRAP_OS.
#   sed_i ...        — portable in-place sed (BSD sed needs `-i ''`)
#   sha256_verify FILE EXPECTED_HEX
#                    — verify a file against a hex digest, using sha256sum
#                      when present and falling back to `shasum -a 256`.
#   run_with_timeout SECONDS CMD [ARGS...]
#                    — `timeout` when present, else gtimeout (brew
#                      coreutils), else run without a timeout.

BOOTSTRAP_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

is_darwin() {
  [[ "$BOOTSTRAP_OS" == "darwin" ]]
}

# stat_perm FILE — print the octal permission mode (e.g. "600") in a
# BSD/GNU-portable way: `stat -f %Lp` on macOS, `stat -c %a` on Linux.
stat_perm() {
  if is_darwin; then
    stat -f %Lp "$1" 2>/dev/null
  else
    stat -c %a "$1" 2>/dev/null
  fi
}

sed_i() {
  if [[ "$BOOTSTRAP_OS" == "darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

sha256_verify() {
  local file="$1" expected="$2" actual
  # Tolerate a CRLF/whitespace-padded .sha256 file (subshell trimming only
  # strips trailing newlines, not \r or spaces).
  expected="${expected//[$'\t\r ']/}"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: SHA256 mismatch for $file" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
  fi
}

run_with_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}
