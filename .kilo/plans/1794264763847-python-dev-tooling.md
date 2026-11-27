# Python Developer Tool Provisioning

## Goal And Decisions

- Keep `user/init.d/20-python` unconditional and dedicated to uv plus managed CPython.
- Add `user/init.d/22-python-dev/` with `.requires` containing only `dev`. The user selected a separate step rather than an internal gate.
- Provision only Ruff initially, available across repositories for the running deploy user. All installations remain under that user's home; no root-tier changes or privilege escalation.
- Install or upgrade unpinned Ruff on every enabled provisioning run. The user selected upgrade-on-rerun. Let uv resolve the latest release compatible with the selected Python interpreter; add no Ruff version key, environment pin, custom release lookup, constraints file, or transitive dependency pins.
- Python does not bundle Ruff: the existing Python major/minor request selects the interpreter, while uv resolves the separate tool package.
- Retain existing uv/Python configuration and override precedence. Do not introduce a new Python patch-upgrade policy as part of this change; an installed matching managed interpreter may continue to satisfy a partial request.
- Keep mypy, pytest, coverage, and project dependencies project-owned. Do not provision pyright without a separate concrete need. Corvid changes and missing fixture assets are out of scope.

## Implementation

1. Correct `user/init.d/20-python/run.sh` runtime provisioning.
   - Preserve the standalone uv installer and existing uv version policy.
   - Resolve Python `latest` only after the uv installation/update and final uv executable selection. Use that uv's catalog; remove the hardcoded fresh-host fallback and fail clearly if no stable CPython candidate is available.
   - Restrict the installed-interpreter check to uv-managed CPython. System Python must not satisfy the managed install check.
   - Match numeric version components literally, with boundaries supporting existing major/minor and exact requests; avoid unescaped version dots in the current regex.
   - Preserve a matching managed interpreter on rerun, install when absent, and report actual managed state truthfully. Do not delete system Python, old managed interpreters, or user-created executable links.
   - Correct stale comments about install destinations and interpreter executables as needed to match actual supported uv behavior.

2. Add `user/init.d/22-python-dev/run.sh` and `.requires`.
   - Use the established Bash step format and source `../lib/common.sh` for strict mode, non-root enforcement, shared config, and version exports.
   - Use the existing `dev` capability; do not introduce a new capability or modify the runner.
   - Prefer the known user-local uv executable, consistently with step 20.
   - Require an installed uv-managed interpreter matching the configured Python request. For `latest`, select an installed managed CPython using uv's discovery after step 20. Inspect the installed uv CLI help during implementation to confirm exact discovery flags.
   - Fail clearly if uv or the required managed interpreter is absent, with remediation to run `./user/init.sh 20-python` from the repository root. Step 22 must not source or execute step 20, use system Python as a fallback, or silently download another interpreter.
   - Pass the selected interpreter explicitly to uv's tool installation. Use an unversioned `ruff` request with upgrade enabled, without forced executable replacement. The installed uv help already exposes `uv tool install --upgrade --python` and `--no-python-downloads`.
   - Resolve upgrades through uv rather than maintaining custom version comparison or a second release API. Repeated runs may check the registry but must not reinstall an already-current tool unnecessarily.
   - Report completion and CLI version truthfully. Fail nonzero on registry, resolution, installation, or executable-collision failures; do not report successful convergence after a failed upgrade.
   - Keep tool environments isolated from projects. Do not install Ruff into a project `.venv` or change any project's lockfile.

3. Update existing documentation and capability maps.
   - `AGENTS.md`: add `user/init.d/22-python-dev` to the `dev` mapping and describe its Ruff-only scope where useful.
   - `README.md`: update the step tree, behavior summary, developer-tool scope, no-pin upgrade policy, and operator commands.
   - `docs/codemap.md`: update step ordering, user-step inventory, and the `dev` capability map. Keep its existing diagram consistent without adding a new report.
   - `example.bootstrap.conf.yml`: update the existing `dev` comment to include the new step and clarify Python major/minor support where the existing version guidance contradicts the example.
   - No host config value changes are needed: this reuses `dev`, which is already enabled in the local config. Update tracked host-config descriptive comments only if necessary; do not modify private config values or secrets.

## Failure Modes And Migration

- The user runner collects failures and continues: step 22 must check prerequisites even in a full run where step 20 failed.
- `dev: false` or omitted: the runner skips step 22 and leaves previously installed Ruff intact. Capability gating controls provisioning, not removal.
- Existing system-only Python: step 20 now installs managed Python instead of incorrectly skipping it.
- Existing uv-managed interpreter matching `3.13`: reuse it; Ruff resolves against that actual interpreter.
- Existing uv-installed Ruff: converge to the unpinned upgrade policy. Verify that a previous exact uv tool constraint is replaced by the new unversioned install request rather than preserved by a plain `uv tool upgrade`.
- Existing non-uv executable named Ruff: fail rather than overwrite it using `--force`; require operator resolution.
- Changing the configured Python series: rerunning 20 then 22 must bind Ruff to the selected interpreter. Do not prune older interpreters because other tool environments may depend on them.
- Registry access is required for enabled tool update runs. Offline upgrade failures remain visible and nonzero even if an older Ruff still works.

## Validation

1. Run Bash syntax checks and ShellCheck on changed/new scripts. Add a small focused shell regression harness using stubbed uv/network commands and isolated home/config paths, not a broad new test framework.
2. Cover system-only versus matching managed Python, literal partial/exact version matching, and fresh-host `latest` resolution after uv installation. Cover resolution failure without a hardcoded fallback.
3. Cover step 22 missing prerequisites, explicit interpreter selection, unpinned install/upgrade arguments, already-current reruns, install failures, and preservation of unrelated executables. Test a previously pinned tool migrating to the unpinned policy.
4. Test runner discovery and gating in an isolated fixture: selector `22` and `22-python-dev`, `dev` enabled/disabled/omitted, and resume ordering from 20. Test direct prerequisite failures independently; `.requires` gating is the runner's responsibility, consistent with existing steps.
5. Keep test scratch under unique directories in `$HOME/.tmpdir/`; never use host-global temporary directories. Do not run full bootstrap/resume commands on the current host merely to test selection.
6. On a disposable environment as a non-root deploy user, manually run `./user/init.sh 20-python`, then `./user/init.sh 22-python-dev` twice. Verify managed Python listing, `uv tool list`, `ruff --version`, lint/format CLI availability, and unchanged Ruff version on an already-current rerun. Check disabled-dev behavior using an isolated config and verify the existing tool remains installed.
7. Validate tools through their executable and uv inventory, not imports in `uv run --no-project -- python`. Do not run an import check that creates a project environment or infer project dependencies from a host CLI.

## Acceptance Criteria

- Baseline hosts receive uv and genuinely managed Python; only dev-enabled hosts provision Ruff.
- Ruff installs and upgrades without a maintained version pin, using the selected managed Python and no root access.
- Project environments, test runners, dependency declarations, fixture assets, and unrelated worktree changes remain untouched.
- Documentation matches the new step and gating. No commit or push is authorized by this plan.

Implementation requires switching to an implementation-capable agent. Only this plan file is created during planning.
