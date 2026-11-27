# Host Context Execution Controls

Status: revised after source and rollout review on 2026-11-17. Awaiting explicit user approval for source implementation. This plan alone authorizes no edits, commits, deployment, or model changes.

## 1. Execution Contract

**Target executor:** GPT-6.1 Sol (`gpt-6.1-sol`), standard reasoning mode, `medium` effort. Do not use `none`, `minimal`, or `off`, and do not switch model, effort, or mode during execution. Confirm the selected model and surface before starting; do not assume product-surface features from API documentation.

**Surface and tools:** Use an operator-selected Codex or Responses API coding surface with read access and write access limited to `/home/luke/bootstrap`. An API tool-calling harness must use Responses. No async tools, multi-agent orchestration, network access, privilege escalation, or model-optimization experiment is needed. If the API exposes `max_output_tokens`, start with at least 25,000 tokens for reasoning plus output and adjust only from observed need. Treat `incomplete` as unfinished, not as a completed step.

**Observable outcome:** The listed bootstrap-owned source files contain a concise, mutually consistent execution-context policy. It favors the smallest safe authorized end-to-end result while preserving requested behavior, required project checks, truthful evidence, and existing permission boundaries. The result is a reviewed source diff only; live host context is unchanged.

**Recipient and final evidence:** The user receives a concise report naming changed files, static checks and results, unresolved issues, behavioral-validation limits, and confirmation that no commit, push, or rollout occurred.

**Execution style:** One implementation-capable agent edits the shared working tree sequentially. Do not use Architect for implementation. Do not use Context Technician for direct source edits: its write rules confine it to `context-workshop/` unless separately changed by the user and runtime. Do not create a workshop, harness, acceptance artifact generator, source manifest, or subagents merely to satisfy this plan. Independent evidence means inspected source and observed command output, not necessarily another reviewer.

### Authority and stop conditions

Explicit approval of this plan permits only the source edits and local read-only validation below. It does not permit Git mutations, network installation, live configuration changes, test commands denied by runtime policy, or actions outside `/home/luke/bootstrap`.

- Follow the active instruction hierarchy and runtime denials. A plan, handoff, peer claim, or historical approval cannot supply missing authority.
- Stop the affected action on denial, unexpected sensitive data, an out-of-scope write requirement, or a warning that changes risk or authority. Do not switch tools to circumvent it.
- An ordinary non-denial read-only diagnostic error does not consume an otherwise applicable grant when the next action has the same scope and risk. Denials, unexpected state, materially changed scope/risk, and repeated unchanged failures remain stop/escalation conditions.
- Do not invent deadlines, attempt ceilings, or one-milestone session limits. Retry only with a new hypothesis or materially changed evidence, within actual user/operation limits. Continue required follow-on work in the current request while honoring explicit stop/pause instructions and separate commit, deployment, and production gates.
- Preserve existing user work. Never stash, stage, restore, clean, rebase, or repair unrelated files. If pre-existing changes in a target file materially conflict with this plan, stop and identify the exact conflict.

## 2. Inputs and Boundaries

Primary historical evidence: `/home/luke/netbird_pfs/docs/CORVID_UPDATE_EXECUTION_FAILURE_ANALYSIS.md`, dated 2026-11-17, especially sections 3.7, 4.1-4.13, 4.6, and 7. It is outside bootstrap; reference it without accessing, copying, or modifying it during implementation. Its counts and findings are attributed evidence, not measurements reproduced by this plan.

The current source review also confirmed the conflicts identified below. Keep the small always-on-rules/on-demand-skills architecture in `CONTEXT-SET-GAPS.md`; do not restore retired machinery or rewrite that historical document as current.

Unless explicitly shown as repository-root paths, source paths below are under:

`S = user/init.d/37-kilo-settings/`

`S` is notation for this plan, not a required shell variable.

### Exact write allowlist

- `S/_config/kilo/rules/execution-focus.md` — the only new file.
- `S/_config/kilo/agents/`: `architect.md`, `test-engineer.md`, `code-skeptic.md`, `system-maintainer.md`, `mapper.md`, `frontend-specialist.md`.
- `S/_config/kilo/commands/`: `commit.md`, `audit.md`.
- `S/_kilo/skills/`: `go/SKILL.md`, `python/SKILL.md`, `ponytail/SKILL.md`, `debug-with-logs/SKILL.md`.
- `S/_kilo/skills/gpt-6-sol-execution-plans/`: `SKILL.md`, `assets/execution-plan-template.md`, `references/sol-model-notes.md`.
- `S/_kilo/skills/`: `webapp-testing/SKILL.md`, `svelte-code-writer/SKILL.md`.
- Repository-root `.kilo/agents/context-technician.md`, `README.md`, and `docs/codemap.md`.

Do not edit this plan during implementation. Do not edit `AGENTS.md`, `CONTEXT-SET-GAPS.md`, `kilo.json`, `kilo.jsonc`, the migrator, denial manifests, tests, skill manifests, runner scripts, permissions, or capability gating. No source JSON configuration change is needed; this does not mean the separately authorized runner cannot create or migrate live JSON.

### Non-negotiable invariants

- Preserve requested behavior and all applicable user-, project-, `AGENTS.md`-, and CI-required checks. Existing requirements are not optional merely because the current prompt did not repeat them.
- Affected checks support development; required milestone/final checks establish completion. A weaker claim cannot waive required checks. Report omitted, unavailable, or failed required checks without unqualified completion.
- Preserve privilege escalation denials, secret handling, System Maintainer approval gates, manual privileged actions, agent tool permissions, and Context Technician's sandbox permissions.
- Do not hardcode deployment-specific values or secrets, print secret values, or treat prose as runtime enforcement.
- Supporting work must serve the requested deliverable. Do not add infrastructure, a generic Markdown linter, a model evaluation suite, or mandatory reporting artifacts.
- Preserve unrelated pre-existing failures as reported boundaries rather than silently fixing them or treating them as proof that this change failed.

## 3. Ordered Source Implementation

### E00 — Establish the baseline

**Depends on:** explicit source-implementation approval.

1. Read repository instructions and every allowlisted target before editing it.
2. Run `git status --short`; inspect existing tracked, staged, and untracked changes relevant to the allowlist. At review time the plan files and `TODO.md` were untracked; recheck rather than assuming this remains true.
3. Record a concise private baseline of target content needed for compare-before-edit and final review. Do not back up by copying files into new repository artifacts.
4. Confirm that the direct executor has the required source-write capability. If only Context Technician's workshop permissions are available, stop rather than widening them.

**Expected result:** all targets and user changes are known before the first edit; no write or Git mutation has occurred.

### E01 — Establish scheduling and proportionate review

**Files:** new `execution-focus.md`; `architect.md`, `test-engineer.md`, `code-skeptic.md`.

Create the always-on rule with at most eight concise directives and roughly 300 words. Replace conflicting agent text rather than appending a second policy.

**Execution-focus rule must state:**

- Name the primary observable outcome and choose the smallest safe authorized end-to-end slice for integration work. Documentation, review, and design tasks use their actual deliverable; do not invent a live test.
- Before unplanned substantial supporting work, or reprioritization that displaces the primary slice, identify the concrete blocker or decision uncertainty it resolves and the next execution enabled. Normal required follow-on steps need no blocker narrative or extra tool ceremony.
- Prefer an integrated result before broad matrices, reusable harnesses, and optional hardening. Inspect material platform facts early when safe access exists.
- When blocked, do only bounded authorized work that removes that blocker or obtains necessary evidence; do not open an unrelated safe lane.
- Distinguish required smoke/core qualification from expansion and research. Existing required behavior/checks remain mandatory; genuinely additional scope is a proposal. Report and appropriately address discovered safety blockers.
- Report demonstrated capability separately from component/offline progress and missing executors.
- Continue within the current authorized request after successful checks; do not invent deadlines or attempt budgets or repeat an unchanged failure.

**Architect:** Schedule the first real slice and minimum safety prerequisites. Distinguish blocking unknowns from reversible assumptions and experiments. Replace exhaustive interviewing and completion-blocking language in both Planning behavior and Completion behavior: only unresolved decisions affecting scope, safety, authority, or feasibility of the next slice keep planning open. Apply data-flow, failure-mode, rollout/migration, and validation checks only where relevant. Preserve planning-only boundaries and the explicit client finalization workflow, without a redundant confirmation when finalization was already requested.

**Test Engineer:** Replace the unconditional comprehensive-tests/coverage/edge-case objective. Exercise the concrete happy-path entry point and required error behavior first. Additional matrices and coverage improvement are optional unless required by user/project instructions or demonstrated safety risk. Optional lanes must not become indirect prerequisites through shared proof requirements.

**Code Skeptic:** Classify findings as blocking the next safe step, required before final acceptance, or optional. Keep evidence of execution claims and project-rule enforcement, but scale proof to affected claims and milestones and permit relevant evidence reuse. Recognize minimal complete implementations. Report unexamined failures rather than demanding unchanged retries; require a new hypothesis before rerun. Apply steps and language conventions only when actually required by user/project instructions; remove universal English-documentation and per-fix/per-step gatekeeping.

**Source check:** A safe early vertical is not blocked by unrelated findings, while required checks and safety findings retain their proper milestone. No permission frontmatter changes.

### E02 — Reconcile language guidance and debugging safety

**Files:** `go/SKILL.md`, `python/SKILL.md`, `ponytail/SKILL.md`, `debug-with-logs/SKILL.md`.

**Shared validation policy:** Replace unconditional language-wide DONE_GATE semantics with affected checks during development and applicable project-required milestone/final checks. Required checks cannot be avoided by narrowing the completion claim. Use the existing project harness. A single minimal check is a floor only where no convention applies, never a ceiling or replacement for security, money-path, or release qualification.

**Go:** Scope workspace, codemap backend structure, and go-shared guidance to repositories where those structures actually apply. Preserve ee `tests [app]` precedence and `GOWORK=off` verification when claiming a versioned dependency consumer works. A reuse inventory or partial match does not authorize editing another repository or opening a PR.

**Python:**

- Scope package layout, error envelope/application exception hierarchy, type tooling, coverage, and uv-only commands to applicable projects. A standalone helper or narrow correction must not trigger adoption of uv, mypy, pytest, a lockfile, a new framework, or a new layout. Existing non-uv projects retain their required tooling.
- Restrict Shared-First inventory to applicable repositories and genuinely reusable infrastructure. Prefer source/dependency inspection. Do not create/synchronize an environment, change a lockfile, install dependencies, provision access, import modules with unknown side effects, or extend a shared module merely to perform a reuse check.
- Remove the universal 500 ms deadlock assertion, 100 ms unit-test limit, and three/five-failure escalation counts; add no replacement universal thresholds. Use actual contention expectations, observed hypotheses, and operation-specific limits.
- Apply pytest-asyncio configuration only where already used; do not convert anyio suites. Never exclude required slow tests from final qualification. Preserve project coverage thresholds and derive coverage targets from actual layout, not hardcoded `src`.

**Ponytail:** Minimize implementation and validation overhead, not requested behavior or required checks. Remove the ship-a-reduced-version-and-ask-later rule and any implication that one self-check supersedes a project harness or security/money-path qualification. Avoid speculative configuration abstractions but retain policy-required configuration; never hardcode deployment-specific values merely because they are stable.

**Debug With Logs:**

- Prefer existing logs and read-only inspection. Remove generic init-rerun and `bash -x` guidance. Repeatability/idempotency is not authorization: never rerun provisioning or another state-changing operation merely to obtain traces. State-changing reruns need separate specific authority; privileged provisioning remains operator-only.
- Screen existing logs and quoted excerpts for tokens, passwords, connection URLs, expanded arguments, and other secrets. Trace only after checking the command and environment for secret exposure; never print secret values.
- Follow the actual operation-defined attempt budget. Read-only diagnostics and pre-submission harness failures do not consume a mutating-attempt budget. Submissions/admissions consume it when its terms count submissions, including rejected submissions; initiated state changes consume their operation budget. If the unit is unclear, report the ambiguity.
- Verify the original failure with evidence appropriate to that failure. Service health checks apply only to applicable services through authorized checks. Discover paths only when uncertain; known paths may be read directly.

**Source check:** A narrow correction creates no toolchain/environment conversion or broad campaign; an actual release/security change retains required qualification. An idempotent init failure produces no rerun, and secret-bearing logs produce no secret output.

### E03 — Make Sol planning and continuation compact and executable

**Files:** Sol `SKILL.md`, `assets/execution-plan-template.md`, `references/sol-model-notes.md`.

- Reinforce first real integrated slice, required-versus-optional lanes, concrete blockers, and production implementation/caller expectations for new interfaces. Do not mandate abstractions or live tests for design-only work.
- Require integrated ordering and current-state continuation in the skill/template. Source acceptance does not require generating a successor plan or conducting model experiments.
- Separate required step essentials (objective/action, exact scope, acceptance evidence, proportionate failure handling) from optional metadata (IDs, budgets, retries, tracking). Copy only useful fields. Do not make every nontrivial step carry bounded retry, deadline, or full-gate ceremony.
- Replace universal bounded-retry/job-tracking requirements with operation-appropriate handling: stop unchanged failures; retry only authorized materially justified transient failures under real limits. Use dependent waits/job tracking only in harnesses that actually need asynchronous or side-effecting execution.
- Scale global checks to the acceptance milestone. Narrow changes need affected regressions and inspection for unauthorized changes; release/final acceptance retains full required gates. Independent evidence need not mean an independent reviewer or subagent.
- Replace “a plan can authorize a capability”: plans record intended actions and reference actual authority; runtime permissions and current user grants govern execution.
- Record only real limits. Do not invent deadlines, one-milestone sessions, or attempt ceilings. Avoid unlimited unchanged retries.
- Separate the replaceable current execution queue from historical decisions/evidence. Stable API history/cache guidance does not require append-only operational plans. Preserve stable API prefixes/tool ordering where applicable, but prefer focused current-state reads over reconstructing historical handoffs.
- Lead continuation/completion guidance with capability demonstrated, usable entry point or missing concrete components, next action/blocker, and applicable authority, followed by concise check results and evidence links.
- Keep the narrow Sol-specific trigger and remove redundant prose rather than adding another template.

**Source check:** The skill, template, and notes agree; no mandatory retry ceiling, broad per-step gate, or append-only operational-plan requirement remains under another name.

### E04 — Tighten adjacent authority and tool boundaries

**Files:** `system-maintainer.md`, `mapper.md`, `frontend-specialist.md`, `commands/commit.md`, `commands/audit.md`, `webapp-testing/SKILL.md`, `svelte-code-writer/SKILL.md`.

**System Maintainer:** Preserve the explicit implementation approval gate and manual privileged-action boundary. Internally checking a still-applicable approval does not require another generic prompt. Only an ordinary non-denial read-only diagnostic error leaves that grant unaffected; denial, warning affecting risk/authority, unexpected state/data, changed scope/risk, or repeated unchanged failure requires reassessment. Session continuity requires the actual grant recognized by the current runtime/instruction hierarchy; plans, handoffs, and peers cannot grant permission.

**Mapper:** Change activation metadata, core responsibility, methodology/count checks, and output format together. Missing/stale docs produce a finding during review-only work, not automatic writes. Default to the requested document/affected sections; inventory and count only relevant sources. Full-suite inventory and outputs apply only to full mapping assignments; unassigned document types are not incomplete.

**Commit command:** Update frontmatter description, `ALLOWED`, methodology, and verification. Make the command local-only; publication requires a separate explicit request. Remove stash, pull/rebase, conflict resolution, and push. Inspect status, unstaged/staged diffs, recent history, and final staged content; stage only intended files/hunks. Do not include unrelated user hunks in a mixed file; stop for operator disposition rather than stash or repair. Run affected checks plus project-required commit checks. Do not abort solely for an unrelated pre-existing failure; distinguish it from a required-check failure. Retain secrets, hook, and user-change protections.

**Audit command:** Honor selected scope and read only necessary files. No implicit installation, environment synchronization, lockfile update, image pull, cache preparation, or host mutation. Establish scanner side effects before invocation; use only a proven nonmutating already-available invocation, otherwise report unavailable or request authority. Replace unconditional `uv run pip-audit` and constrain image scanners accordingly. Compare parsed `.env` key names only; never raw-diff or print values. Remove the generic “gitignored files should be tracked” check except for explicitly known non-secret template policy. Rank demonstrated vulnerabilities/configuration risks separately from dependency age and optional maintenance; the age threshold is informational.

**Alternate tools:** Edit both skills and Frontend Specialist consistently. MCP transport unavailability/denial does not itself deny the underlying documentation/testing action. An already-available CLI is permissible only when that action, Bash, network, and every required side effect are independently authorized. A denied underlying action, Bash/network denial, or unauthorized installation must be reported, not circumvented. `npx` package resolution and `uv run --with ...` environment/package preparation are separate side effects. Preserve all agent permission frontmatter.

**Source check:** Sources contain no automatic publication or environment-preparation instruction and no permission widening. This is a source-consistency result, not a guarantee of runtime model behavior.

### E05 — Reconcile repository-local guidance and deployment docs

**Files:** repository-root `.kilo/agents/context-technician.md`, `README.md`, `docs/codemap.md`.

**Context Technician:** Preserve sandbox boundaries, `steps: 40`, and every permission. Direct implementation under this plan belongs to another authorized agent. Make test plans, CLI/model-backed runs, exports, iteration logs, and negative tests proportionate to risk and the requested deliverable rather than universal for every prose change. Static source inspection is valid when behavior was not run; report it as such. Remove default three-iteration and two-consecutive-failure limits; unchanged failures need a new hypothesis, while the configured 40-step runtime ceiling remains real. Do not require a model run or export to declare source-only work complete.

**README and codemap:** Update only the existing step-37/rules sections (currently README near line 590 and codemap near lines 142 and 154-168). Document the new rule and fresh-session discovery. Explain that source changes are not live until rollout; synchronized agents/commands/rules/selected skills overwrite managed destination modifications while destination-only additions survive. Existing `kilo.json` and `.kilocodeignore` customizations are preserved with diff guidance; recognized JSONC receives only the managed migration. Unselected optional skills are neither installed nor refreshed and may remain stale. Distinguish “no source JSON edits” from possible live JSON creation/migration. Note relevant nontransactional rollout behavior without turning these documents into an operator runbook.

**Source check:** Repository-local instructions no longer require the harness, retry ceilings, or artifacts this plan rejects. Documentation matches actual runner behavior.

## 4. Source Acceptance and Validation

### E06 — Perform one scoped consistency pass

**Depends on:** E01-E05. No broad reviewer campaign or new tooling.

1. Re-read every changed file and directly linked changed guidance. Trace each invariant to its new location and check that removed blockers did not return as renamed evidence requirements.
2. Inspect Markdown/frontmatter structure and confirm permission frontmatter and safety assertions are unchanged except for expressly intended prose.
3. Inspect internal references and the exact changed-file set against the allowlist. No `.sh` file or other executable script may change. Markdown command examples may change only where expressly required above; stop if any executable script changes rather than treating static prose checks as sufficient.
4. Run `git status --short`, `git diff --check`, and, if relevant staged changes exist, `git diff --cached --check`. Do not stage anything.
5. Ordinary `git diff` omits untracked files. Read the complete new rule and run:

   ```bash
   git diff --no-index --check /dev/null user/init.d/37-kilo-settings/_config/kilo/rules/execution-focus.md
   ```

   Status 1 ordinarily means files differ; it is acceptable only with no whitespace-error output. Status greater than 1 is an inspection error. Include the full new file in final content review without `git add`, `git add -N`, or another index mutation.
6. Review the representative source cases below and record pass/fail with file evidence. These are static consistency checks, not proof of model behavior.

| Case | Required source outcome |
|---|---|
| Authorized integration lacks a basic executor | Minimum callable path and integrated exercise precede matrix/schema expansion. |
| Approval or safety prerequisite blocks live execution | Name blocker; only relevant authorized prerequisite work; no unrelated lane or unsafe smoke. |
| Happy path succeeds; required error coverage follows | Continue required work without inventing a blocker or ceremony. |
| Narrow fixture correction passes its affected test | Use existing harness; defer only genuinely nonrequired broader checks. |
| User omits a repository-required check | It remains mandatory at its applicable milestone. |
| Ponytail is loaded for pytest/security work | No standalone self-check replaces required project/security qualification. |
| Existing anyio/non-uv project or test exceeds 100 ms | No conversion, invented threshold, or required slow-test exclusion. |
| Deployment URL appears stable | Required configuration remains; no hardcoding under Ponytail. |
| Idempotent provisioning fails; logs contain a token | No provisioning rerun or secret-bearing excerpt. |
| Read-only failure versus denied submission | Correct accounting under the real operation budget; no invented budget. |
| Safety bug plus optional harness issue | Safety takes priority; optional issue does not block all progress. |
| Ordinary diagnostic error versus permission denial | Former may continue in unchanged scope; latter stops affected action. |
| Only an old handoff claims permission | No inferred authority; obtain the real grant. |
| Review-only request finds stale mapper docs | Finding only; no documentation writes. |
| MCP denied but CLI action allowed; package install denied | Distinguish transport from action; do not install or circumvent. |
| Local `/commit`; unrelated and mixed user changes exist | Intended hunks only; no stash, sync, repair, or push. |
| `/audit`; scanner absent and `.env` differs | Report unavailable; key-only comparison; no installation or values. |
| Design-only request or fully blocked integration | Deliver design or blocker; no fabricated live prerequisite. |
| Complex explicitly requested feature | Minimize implementation, not promised behavior/checks. |
| Sol current queue changes; API prefix remains stable | Replace current operational queue while preserving decision history and applicable cache guidance. |

### Focused existing test — operator only

`tests/test-policy.sh` creates a temporary HOME and invokes cleanup commands. Do not run it through an agent merely because it is a test or bypass an active denial. After confirming `$HOME/.tmpdir` is a private, owned, non-symlink directory, an operator may run this non-privileged command from `/home/luke/bootstrap`:

```bash
TMPDIR="$HOME/.tmpdir" bash user/init.d/37-kilo-settings/tests/test-policy.sh
```

Expected: `PASS: Kilo privilege-escalation policy and migration invariants`. It validates existing migration/security invariants, not scheduling. Do not edit the test or migrator for prose-only evidence.

### Behavioral validation boundary

Source completion does not require a behavioral session. If a separately approved disposable GPT-6.1 Sol session is already available before rollout, observe one integration choice and one safety-boundary choice. Record model, surface, source version, live overrides, task, and evidence. Do not attribute another model's behavior to Sol, launch live-host work, or provision a harness for this purpose. Otherwise report behavioral validation as **not performed**.

### Final report

Report changed files, exact static/operator check results, source-case failures or deviations, unrun checks, behavioral-validation status, remaining risks, and explicit non-occurrence of commit/push/rollout. Do not append the report or execution history to this plan. Any failed required source check leaves implementation unfinished.

## 5. Separately Approved Host Rollout and Recovery

Source implementation and host rollout are independent approvals. Do not run the settings step during E00-E06.

### Pre-rollout inventory and approval

Before any rollout, the non-root operator must:

1. Review the complete source diff, including the untracked new rule.
2. Inventory every possible runner destination, not only this plan's Git diff: all managed agents/commands/rules/default skills, installed optional skills, live JSON/JSONC, `.kilocodeignore`, scratch/tmpfiles paths and timer state, and retired-path deletions.
3. Compare source to live privately using filenames/status/hashes rather than publishing content. Identify unrelated managed local edits; destination-only additions surviving does not protect edits to managed files.
4. Back up every possible affected destination in an operator-chosen private location outside the repository, preserving content, modes, absence-before-rollout, and relevant timer state. Do not treat pruned agent scratch as durable backup.
5. Preflight nvm/Kilo prerequisites, inspect live JSONC structure read-only against the recognition rules documented in `migrate-kilo-jsonc.sh`, and run `kilo config check` with the selected nvm environment. Do not run the migrator as a preflight check; structural inspection cannot guarantee its later acceptance, so backup/recovery remains necessary. Stop for unrelated live drift and obtain explicit approval for every overwrite/deletion/migration/timer effect, or use a separately reviewed targeted deployment of only approved files.

The full runner can create/chmod scratch paths, write tmpfiles configuration, enable a user timer, overwrite managed files, delete retired `rules/privilege-escalation.md` and `commands/standards.md`, create `kilo.json`, migrate `kilo.jsonc`, and create `.kilocodeignore`. It is not limited to the reviewed prose diff.

### Rollout commands

Choose exactly one rollout invocation after inventorying installed optional skills and explicitly approving the refresh set. The runner records no previous optional selection; construct any selection from the live inventory and approved refresh list.

For a default-skill-only rollout from `/home/luke/bootstrap`:

```bash
./user/init.sh 37-kilo-settings
```

This does **not** install or refresh unselected optional skills. To refresh only an already-installed `svelte-code-writer` alongside the defaults, with that exact selection explicitly approved:

```bash
KILO_OPTIONAL_SKILLS=svelte-code-writer ./user/init.sh 37-kilo-settings
```

Do not run both invocations. If multiple installed optional skills are approved for refresh, use one comma-separated selection instead. Do not select an optional skill where installing it is unwanted, and do not use `KILO_OPTIONAL_SKILLS=all` merely to refresh one skill. Report `svelte-code-writer` as updated, intentionally skipped, or not installed.

On success, inspect reported configuration differences privately, restart/reload Kilo at an operator-chosen time, and confirm discovery of the new rule and edited managed context in a fresh session. Do not copy potentially sensitive live configuration into reports.

### Failure and recovery

The runner is nontransactional. Agents/commands/rules synchronize and retired paths are removed before JSONC migration; skills deploy only after JSONC succeeds. JSONC rollback restores only JSONC, not earlier context changes, tmpfiles/timer effects, retired-file deletion, or a newly created `kilo.json`.

On any failure:

1. Stop before restart/reload and record which phases completed.
2. Restore every changed destination from the operator backup, including files newly created by the rollout and relevant tmpfiles/timer state, using separately approved operator actions. Do not merely rerun synchronization.
3. Do not use destructive Git restoration, prune destination-only additions, relax permissions, or assume another sync deletes a newly deployed rule.
4. Resolve the real configuration conflict before another rollout attempt. Review the mixed-state case “JSONC rejected after agents/commands/rules synchronized” against actual restored state.

## 6. Completion Criteria

- Every allowlisted source change is present, internally consistent, and limited to the requested policy; no equivalent universal blocker survives under renamed wording.
- The new rule remains at most eight concise directives and roughly 300 words. Other edits primarily replace conflicting guidance; no new framework or mandatory artifact is introduced.
- Requested behavior, required project checks, secrets, privilege boundaries, explicit approvals, user-change preservation, and existing permissions remain intact.
- Static source acceptance passes, or any failed/unrun required item is reported without an unqualified completion claim.
- Documentation accurately distinguishes source edits, managed overwrites, destination-only additions, optional-skill skip/staleness, live discovery, and observed behavior.
- No commit, push, host rollout, external Corvid change, permission widening, or model change occurred under source implementation.
- Rollout, if separately approved, reports preflight/inventory, optional-skill disposition, live drift, fresh-session discovery, and any recovery actually performed.
