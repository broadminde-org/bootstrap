# Kilo CLI Agent and Plan Testing

**Research date:** 2026-09-02  
**Installed CLI:** Kilo 7.5.6  
**Scope:** Whether an agent Markdown file and a plan Markdown file can be placed at chosen paths and executed through the Kilo CLI.

## Conclusion

Yes, with an important distinction:

- A custom agent can be stored at a project or global agent path and selected by its filename-derived name with `kilo run --agent <name>`.
- A plan can be stored at any path and passed as context with `kilo run --file <plan-path> ...`, or referenced in the prompt. `--file` attaches the file; it does not invoke a native plan runner.
- Kilo 7.5.6 has no `kilo plan <path>` command and no `--plan <path>` option in `kilo run`.
- For repeatable testing, start Kilo from an isolated fixture project, place the agent under `.kilo/agents/`, and pass the plan with `--file`.

## Agent File Locations and Format

Official custom-agent documentation says project agents may be placed at:

- `.kilo/agents/<name>.md`
- `.kilo/agent/<name>.md`
- legacy `.kilocode/agents/<name>.md`

Global agents may be placed under `~/.config/kilo/agent/<name>.md`. The filename without `.md` is the agent identifier; nested paths become namespaced identifiers. Agent files use YAML frontmatter plus a Markdown body. Useful frontmatter includes `description`, `mode`, `model`, `permission`, `steps`, and `variant`.

Primary source: [Kilo Custom Modes](https://kilo.ai/docs/customize/custom-modes).

The installed CLI confirmed `kilo agent list` and `kilo debug agent <name>` are available. `kilo agent create --path <directory>` writes a generated file below `<directory>/agents/`; it is a generator, not an arbitrary existing-file loader. To test a hand-written agent, write the Markdown file directly to a recognized directory.

Primary sources:

- `kilo agent --help` and `kilo agent create --help` on Kilo 7.5.6
- `kilo agent list` on the current host
- [Kilo CLI Reference](https://kilo.ai/docs/code-with-ai/platforms/cli-reference)

## Run Syntax

The installed syntax is:

```bash
kilo run \
  --dir /path/to/fixture \
  --agent my-agent \
  --file /path/to/test-plan.md \
  --format json \
  --auto \
  "Execute the attached test plan. Follow the plan exactly. Report each check as PASS or FAIL and do not modify files outside the agent's allowed scope."
```

Relevant flags:

- `--agent <name>` selects a primary agent by identifier.
- `--file <path>` is repeatable and attaches files to the prompt.
- `--dir <path>` changes the working directory for a local run.
- `--format json` emits raw JSON events, useful for harnesses.
- `--auto` runs autonomously and automatically approves permissions that are not explicitly denied. Use only in a disposable/trusted fixture because it is deliberately permissive.
- `--model <provider/model>` and `--variant <name>` control model selection.
- `--title <text>` sets a stable session title.
- `--command <name>` executes a slash command rather than a normal prompt; it is not needed for ordinary plan-file execution.

Primary sources:

- `kilo run --help` on Kilo 7.5.6
- [Kilo CLI Reference](https://kilo.ai/docs/code-with-ai/platforms/cli-reference)
- [Kilo CLI guide](https://kilo.ai/docs/code-with-ai/platforms/cli)
- Source implementation: [`packages/opencode/src/cli/cmd/run.ts`](https://github.com/Kilo-Org/kilocode/blob/main/packages/opencode/src/cli/cmd/run.ts)

The Kilo source resolves each `--file` path, checks it exists, and sends it as a file part alongside the text prompt. Therefore the plan contents are context supplied to the selected agent, not a special control-plane object.

## Plan Agent vs Executing a Saved Plan

Kilo has a built-in `plan` agent intended to analyse a codebase and write implementation plans. Official documentation describes it as read-only plus restricted plan-file editing, normally under `.kilo/plans/`.

That workflow is different from executing an already-written plan:

```bash
# Ask the built-in planner to create a plan in an interactive session.
kilo --agent plan --prompt "Analyse this fixture and write an implementation plan"

# Execute a saved plan with a custom implementation/test agent.
kilo run --dir /path/to/fixture \
  --agent test-engineer \
  --file /path/to/saved-plan.md \
  --auto \
  "Execute the attached plan as a test task. Report evidence and stop on unsafe or ambiguous steps."
```

The plan agent's built-in plan-enter/plan-exit interaction is not a batch plan-file executor. Non-interactive `kilo run` explicitly denies plan-enter and plan-exit, so a test harness should use a normal prompt plus `--file` when it needs deterministic one-shot execution.

Primary sources:

- [Kilo Using Agents](https://kilo.ai/docs/code-with-ai/agents/using-agents)
- [Kilo Custom Modes](https://kilo.ai/docs/customize/custom-modes)
- `packages/opencode/src/cli/cmd/run.ts`, especially the `--file` handling and non-interactive permission rules

## Recommended Fixture Layout

```text
fixture/
  .kilo/
    agents/
      plan-test-runner.md
  plans/
    smoke.md
  src/
  tests/
```

Example agent:

```markdown
---
description: Execute Markdown test plans and report evidence
mode: primary
permission:
  read: allow
  glob: allow
  grep: allow
  bash: allow
  edit: deny
  mcp: deny
---

You execute the supplied test plan. Do not infer success: run each command or inspect each assertion required by the plan. Report PASS, FAIL, or BLOCKED with command output and explain any deviation. Do not edit files.
```

Example harness invocation:

```bash
set -o pipefail
kilo run \
  --dir "$PWD/fixture" \
  --agent plan-test-runner \
  --file "$PWD/fixture/plans/smoke.md" \
  --format json \
  --auto \
  --title "plan smoke test" \
  "Execute the attached test plan. Treat the plan as authoritative test instructions. Return a machine-readable summary with PASS, FAIL, and BLOCKED results." \
  > "$PWD/fixture/results.jsonl"
status=$?
printf 'kilo exit status: %s\n' "$status"
```

For a read-only review agent, set `edit: deny`. For a test-writing agent, allow only the specific test-file patterns. Agent permissions are ordered and pattern-based; the last matching rule wins.

## Limitations and Caveats

- There is no CLI flag to select an arbitrary agent file by filesystem path. `--agent` accepts the loaded agent name, so the file must be in a recognized config location or be exposed through project configuration.
- `--file` attaches the plan as prompt context. It does not enforce that every plan step is followed. The agent prompt and the plan should define reporting and stopping behavior.
- `--auto` bypasses approval prompts; explicit agent/config denies still matter, but this is not a security sandbox.
- A plain non-interactive run without `--auto` cannot interactively ask for approvals. Kilo auto-rejects permission requests and exits nonzero when a request was rejected. This is useful for CI failure detection but can surprise agents that need writes or commands.
- The CLI's project-level config and `.kilo/agents/` are resolved relative to the `--dir`/working directory. Use a disposable fixture and verify discovery with `kilo agent list` from that directory before running the paid model task.
- `kilo agent create --path X` means “use X as the parent directory and create X/agents/...”; it does not mean “load this exact Markdown path.”

## Validation Commands

```bash
kilo --version
kilo agent list
kilo debug agent plan-test-runner
kilo run --help
kilo config check
```

For CI, capture `--format json` output and the process exit code. Treat exit code `0` as CLI/session success, not proof that the plan's assertions passed; require the agent's structured result or add an external test-plan checker.

## Empirical Workspace Discovery Test

On 2026-09-02 with Kilo 7.5.6, a temporary `.kilo/agents/cli-discovery-probe.md`
was created in `/home/luke/bootstrap`. Without restarting a daemon or CLI process:

```text
kilo agent list
  cli-discovery-probe (primary)

kilo debug agent cli-discovery-probe
  returned the probe's prompt and permissions
```

`kilo run --agent cli-discovery-probe --command status --format json` also accepted
the agent selection and created a session; it failed afterward because `status` is
not a registered CLI command, not because the agent was undiscovered. The temporary
probe was then removed. This confirms that a newly written workspace agent is
available to a newly invoked CLI command immediately. An already-running interactive
session may need `/reload` or a restart to refresh its agent catalog.
