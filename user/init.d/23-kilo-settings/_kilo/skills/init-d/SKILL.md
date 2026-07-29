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
- Steps are executed with `chmod +x` applied by the runner; failures are
  collected, reported by name at the end, and cause a non-zero exit.

## Runner contract (`init.sh`)

- **Privilege mode is one or the other, decided up front:**
  - *Root mode* — refuses to run unless EUID=0. For host/system-level
    provisioning (apt packages, docker, users, firewall).
  - *User mode* — refuses to run as root. For per-user dev tooling installed
    into `$HOME` (python, node, shell config). Never mixes: if a step needs
    root, it belongs in the root-mode init.d, and vice versa.
- **Standard CLI** (adhere to this exact set):
  - `./init.sh` — run all steps in numeric order
  - `./init.sh --from N` — run from step N onward
  - `./init.sh N` — run only step N
  - `./init.sh --help` — print usage
- Discovery uses `find ... -maxdepth 1` on `init.d`, skipping `*.disabled`,
  collecting both flat files and dirs into a map keyed by numeric prefix.
- Loads capability config before running steps; prefers a
  `$(hostname).conf.yml` over the default conf when both exist (optional).

## Configuration and secrets

- Steps that need project-specific parameters read them from an **`.env` file**
  at the project root. Nothing project-specific is hardcoded in steps.
- If `.env` is required, ship an **`.env.example`** template alongside it.
- Internal secrets (passwords, tokens, keys the system needs) are **generated
  by the init step itself**, never prompted for or committed.
- Generated secrets are written to a **`secrets/`** folder: create it if
  missing, `chmod 700` the directory and `chmod 600` the files inside.

## Adding a new step

1. Pick the next free number (leave gaps for future insertion).
2. Choose flat file for a single self-contained script; directory format the
   moment the step needs any supporting file.
3. Write the step to be idempotent and non-interactive; fail loudly
   (`set -euo pipefail`, non-zero exit on error).
4. Read parameters from `.env`; generate secrets into `secrets/`.
5. Add a `.requires` file only if the step depends on an optional capability.
