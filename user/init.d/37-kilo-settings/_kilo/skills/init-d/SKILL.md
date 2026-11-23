---
name: init-d
description: >-
  Format and conventions for the init.sh + init.d/ numbered drop-in
  provisioning system. USE FOR creating a new init.sh runner, adding or
  modifying init.d steps, initializing a new repo/project with a provisioning
  routine, reviewing init scripts. DO NOT USE FOR editing the contents of a
  specific existing step (just edit it directly).
---

# init.sh + init.d/ format

A shell-based provisioning pattern: `init.sh` is a runner that programmatically
discovers numbered entries in a sibling `init.d/` folder and executes them in
numeric order.

## Layout

```
init.sh                 # the runner
init.d/
  10-some-step.sh       # flat-file step (alternative format)
  20-some-step/         # directory step
    run.sh              # entry point (required)
    ...                 # any other files the step needs
  30-skipped.disabled   # .disabled suffix → always skipped
  lib/                  # shared helpers (not a step — no numeric prefix)
```

## Step rules

- Name prefix is `NN-` (numeric, dash). Sorting/execution order is numeric.
- Two formats, treated identically by the runner:
  - Flat file: `init.d/NN-name.sh`
  - Directory: `init.d/NN-name/run.sh`
- Directory steps run with `cd` into their own directory; they may carry
  arbitrary contents (templates, Dockerfiles, assets) — the runner does not care.
- A step may include a `.requires` file (one capability name per line). The
  runner skips it unless every listed capability is enabled in the project's
  config file (e.g. `bootstrap.conf.yml`, loaded via `init.d/lib/conf.sh`).
  Steps without `.requires` always run.
- Steps must be **non-interactive** by default. Interaction only in special,
  documented circumstances.
- Inspect the actual runner before describing failure behavior or executing it.
  In bootstrap, the root runner applies `chmod +x` and stops on the first failed
  step (including chmod failure); the user runner collects step-script failures
  and exits nonzero after the summary. User-runner preflight/chmod failures can
  stop it earlier under `set -e`. Other projects must declare their own policy.

## Runner contract (`init.sh`)

- **Privilege mode is one or the other, decided up front:**
  - *Root mode* — refuses to run unless EUID=0. For host/system-level
    provisioning (apt packages, docker, users, firewall).
  - *User mode* — refuses to run as root. For per-user dev tooling installed
    into `$HOME` (python, node, shell config). Never mixes: if a step needs
    root, it belongs in the root-mode init.d, and vice versa.
- Root mode describes manual operator provisioning, not agent authority to
  escalate. Chat agents must never execute sudo or equivalent direct/indirect
  escalation; provide exact operator commands, working directory, expected
  result, and non-privileged verification when root access is required.
- **Standard CLI** (adhere to this exact set):
  - `./init.sh` — run all steps in numeric order
  - `./init.sh --from N` — run from step N onward
  - `./init.sh N` — run only step N
  - `./init.sh --help` — print usage
- Bootstrap also accepts a step name such as `50-docker`. Compare numbers
  numerically (`5` selects `05-...`); reject unmatched bare selectors, unknown
  arguments, and missing/non-numeric `--from` operands rather than falling back
  to all steps or a silent no-op.
- Discovery uses `find ... -maxdepth 1` on `init.d`, skipping `*.disabled`,
  collecting both flat files and dirs into a map keyed by numeric prefix.
- Loads capability config before running steps; prefers a
  `$(hostname).conf.yml` over the default conf when both exist (optional).
- In bootstrap, config and its `capabilities:` block are required; unlisted
  capabilities are disabled. Validate names, duplicates, requirements, and
  enabled features' prerequisites before steps. Disabling a capability skips
  provisioning, never uninstalls existing state. Both tiers export the same
  runner-selected `BOOTSTRAP_CONFIG_FILE` to step subshells.

## Configuration and secrets

- Resolve deployment parameters through the project's existing environment/config
  interface, with portable defaults where documented. Bootstrap reads required
  inputs from the environment or parsed repo-root `.env`; do not shell-source
  untrusted dotenv files or add an incompatible parser.
- If `.env` is required, ship an **`.env.example`** template alongside it.
- Distinguish operator-supplied credentials from secrets the step is explicitly
  responsible for generating. Use the established protected credential store;
  do not generate replacements or add a secret store to a generic helper.
  Bootstrap's `.env` never contains tokens/PATs; use its credential-owner path.
- When generation is required, generate non-interactively, retain existing valid
  secrets on reruns, and write outside the repository or under an explicitly
  gitignored `secrets/` path. Protect directories/files with 0700/0600 from
  creation, refuse redirected paths, and never print or commit secret values.
  Do not create this directory unless the step actually needs generated secrets.

## Adding a new step

1. Pick the next free number (leave gaps for future insertion).
2. Choose flat file for a single self-contained script; directory format the
   moment the step needs any supporting file.
3. Write the step to be idempotent and non-interactive; fail loudly
   (`set -euo pipefail`, non-zero exit on error).
4. Resolve supplied parameters through the existing interface; generate secrets
   only when required, using protected external or explicitly gitignored storage.
5. Add a `.requires` file only if the step depends on an optional capability.
