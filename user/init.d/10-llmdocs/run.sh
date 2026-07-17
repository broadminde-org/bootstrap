#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 10-llmdocs — Deploy the llmdocs framework and make it host-wide.
#
# llmdocs/ is a stdlib-only Python framework for turning upstream
# Sphinx/Markdown/XML docs into LLM-friendly markdown. It ships with
# this step under init.d/10-llmdocs/llmdocs/ and is meant to be reused
# across any docs-source project on the host — i.e., repo-agnostic.
#
# This step copies llmdocs/ to $HOME/llmdocs/ (so the deployed copy is
# independent of the bootstrap repo location) and installs a thin wrapper
# at $HOME/.local/bin/llmdocs that invokes:
#
#   uv run --project $HOME/llmdocs python -m llmdocs …
#
# Idempotent: overwrites on every run (re-running picks up any changes
# made to the source llmdocs/ inside the bootstrap step dir).
#
# Run as the deploy user (./user/init.sh 10-llmdocs).

LLMDOCS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/llmdocs"
LLMDOCS_DST="$HOME/llmdocs"
WRAPPER="$HOME/.local/bin/llmdocs"

if [[ ! -d "$LLMDOCS_SRC" ]]; then
  echo "ERROR: llmdocs/ not found at ${LLMDOCS_SRC}" >&2
  echo "       init.d/10-llmdocs/llmdocs/ must exist alongside this run.sh." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Copy llmdocs/ to $HOME/llmdocs/
# ---------------------------------------------------------------------------

rm -rf "$LLMDOCS_DST"
cp -r "$LLMDOCS_SRC" "$LLMDOCS_DST"
echo "Copied llmdocs/ to ${LLMDOCS_DST}/"

# ---------------------------------------------------------------------------
# 2. Install wrapper at $HOME/.local/bin/llmdocs
# ---------------------------------------------------------------------------

mkdir -p "$HOME/.local/bin"

# The wrapper references the deployed $HOME/llmdocs copy — no dependency
# on the bootstrap repo path after this point.
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
# Installed by 10-llmdocs. Re-run user/init.sh 10-llmdocs to refresh.
exec uv run --project "$HOME/llmdocs" python -m llmdocs "$@"
EOF
chmod +x "$WRAPPER"

echo "Installed llmdocs wrapper at ${WRAPPER}"
echo "  -> llmdocs framework: ${LLMDOCS_DST}"
echo "Run 'llmdocs --help' to list available commands."
