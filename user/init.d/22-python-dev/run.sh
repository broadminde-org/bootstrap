#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# Ruff is an isolated user tool, not a project dependency. Re-resolve its
# unpinned requirement on each dev-enabled run; never force executable replacement.
UV_CMD="$HOME/.local/bin/uv"
if [[ ! -x "$UV_CMD" ]]; then
  UV_CMD="$(command -v uv || true)"
fi
if [[ -z "$UV_CMD" || ! -x "$UV_CMD" ]]; then
  echo "ERROR: uv is required for Ruff. Run ./user/init.sh 20-python from the repository root." >&2
  exit 1
fi

python_request="cpython"
if [[ "$EE_PYTHON_VERSION" != "latest" ]]; then
  python_request="cpython@${EE_PYTHON_VERSION}"
fi
if ! python_bin="$("$UV_CMD" python find --no-project --system --managed-python \
    --no-python-downloads --no-config "$python_request")"; then
  echo "ERROR: managed CPython ${EE_PYTHON_VERSION} is required for Ruff." >&2
  echo "       Run ./user/init.sh 20-python from the repository root, then rerun this step." >&2
  exit 1
fi

echo "Installing/upgrading unpinned Ruff using ${python_bin}..."
"$UV_CMD" tool install --no-config --upgrade --python "$python_bin" \
  --managed-python --no-python-downloads ruff

# Use uv's bin directory, not a potentially unrelated Ruff on PATH.
tool_bin="$("$UV_CMD" tool dir --bin --no-config)"
"$tool_bin/ruff" --version
echo "22-python-dev: Ruff ready (uv-managed tool; project dependencies unchanged)."
