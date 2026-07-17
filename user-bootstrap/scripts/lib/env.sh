# env.sh — derive SCRIPT_ROOT and EE_ROOT for maintain scripts
#
# Lives at $HOME/scripts/lib/env.sh. Sets SCRIPT_ROOT and EE_ROOT
# so maintain.d steps can source lib/maintain-common.sh.
#
# Idempotent — uses _MAINTAIN_ENV_LOADED sentinel. The ee monorepo's
# env.sh uses _EE_ENV_LOADED; we use a different sentinel so both can
# coexist when a shell sources both (unusual but defensive).
[ -n "${_MAINTAIN_ENV_LOADED:-}" ] && return 0
export _MAINTAIN_ENV_LOADED=1

_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$_ENV_SH_DIR/.." && pwd)"
EE_ROOT="$SCRIPT_ROOT"

export SCRIPT_ROOT EE_ROOT

# Source project.sh so scripts that reference project_paths() still work.
# shellcheck source=./project.sh
source "${SCRIPT_ROOT}/lib/project.sh"
project_load_paths
