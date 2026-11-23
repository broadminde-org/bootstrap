# Host Plan Lifecycle

**Disposition:** Finalized, implementation-ready; source implementation requires a separate request, and host application remains separately gated.
**Scope:** `user/init.d/37-kilo-settings` only, except this requested plan.
**Outcome:** General planners and executors receive one concise plan-lifecycle contract, and planning guidance produces replaceable current-state queues rather than accumulating history.

## Boundaries

- Preserve required qualification, truthful evidence, secrets, privilege boundaries, and separate commit/push/deployment authorization.
- Do not edit existing project plans, project instructions, or authentic historical evidence.
- Do not change models, MCP configuration, optional-skill selection, permissions, or the JSONC migrator.
- Do not introduce a plan-management service, mandatory archive per update, new evaluation framework, or large policy document.
- Do not run provisioning or alter live `~/.config/kilo` or `~/.kilo` during source implementation.
- Limit source writes to the new rule and four existing files listed below. Report any additional needed correction rather than expanding scope.

## 1. Add The General Lifecycle Contract

Create `_config/kilo/rules/plan-lifecycle.md`, loaded through the existing global rules glob. Keep it short, approximately 10-15 substantive bullets at most, covering:

- Apply to creating, executing, reviewing, resuming, and updating plans, regardless of model or selected agent. Maintenance is conditional on write authority; read-only reviews report stale state without editing plans or creating archives.
- Maintain one current execution queue per workstream; separate independent workstreams may have separate plans.
- Make disposition, objective, current state, remaining actions, blockers, and acceptance easy to identify.
- Use explicit dispositions: draft, active, blocked, completed, or historical. A superseded plan is historical and points to its successor; completed/historical plans are not executable queues.
- Update current state in place. Remove resolved blockers, obsolete actions, and superseded instructions instead of appending narrative handoffs or repeated amendment sections.
- Retain only completed-work summaries and exact current identifiers needed for continuation or admission; link evidence instead of embedding logs, obsolete process histories, or investigation transcripts. Do not remove a required source/receipt identity merely to shorten the plan.
- Preserve authentic evidence and still-applicable decisions outside the executable queue; reuse existing records rather than automatically creating an archive for every update.
- Reference applicable policies and contracts instead of repeating them. Make any material acceptance or trust-model change explicit under actual authority; never silently waive it during compaction.
- Map required checks to their acceptance purpose. One still-valid execution may satisfy overlapping requirements only when the governing contract permits reuse; explicit separate-run requirements remain binding. Reruns need a distinct purpose or invalidated evidence, without omitting required coverage.
- A plan records intent, not permission. Keep persistent goals and continuation summaries aligned with current state when the runtime permits; report stale retained objectives rather than treating them as current authority.
- Use size as a warning, not a completeness gate. Prefer compact queues; reassess repetition/history around 200 lines or 12,000 characters, without dropping necessary execution requirements to meet a quota.

**Acceptance:** The rule covers creation, update, resume, and retirement; contains no project-specific facts or mandatory history-producing ceremony; is discoverable through the existing instructions glob.

## 2. Align The Planner And Skill

Update these existing files, without copying the whole lifecycle rule into each:

- `_config/kilo/agents/architect.md`: explicitly follow the global lifecycle contract, reuse the current plan for the same workstream, and save the current execution contract rather than the interview transcript. Preserve finalization behavior and plan-only edit permissions.
- `_kilo/skills/gpt-6-sol-execution-plans/SKILL.md`: align update/retirement guidance with the global rule; retain its Sol-specific trigger and technical guidance. Do not turn ordinary planning into model research or an optimization experiment.
- `_kilo/skills/gpt-6-sol-execution-plans/assets/execution-plan-template.md`: reduce the default to disposition/objective, relevant current inputs and constraints, remaining ordered actions, concrete blockers, and acceptance. Keep model/runtime metadata optional for tasks that need it. Consolidate repeated permissions, failure, and acceptance fields. Treat continuation status as replaceable state, not an appended report section.
- `_kilo/skills/gpt-6-sol-execution-plans/references/sol-model-notes.md`: preserve the distinction between API conversation history/cache prefixes and replaceable operational documents; remove any newly redundant lifecycle wording rather than expanding the reference.

Leave `execution-focus.md`, `session-economy.md`, test-engineer, code-skeptic, and language skills unchanged. Report any demonstrated contradiction for disposition; existing required-check safeguards remain intact.

**Acceptance:** General planning does not depend on loading the Sol skill. The template is materially smaller, cannot reasonably be read as an append-only handoff ledger, and still supports scope, safety, dependencies, and required qualification.

## 3. Verify Source And Deployment Behavior

- Review the final diff for lifecycle coverage, duplicated policy, scope creep, lost safety requirements, and accidental executable language in retired-state guidance.
- Walk through a small fictional plan in the review response: mark a step implemented, record a failed check, resolve the failure, supersede a decision, then complete the work. These are simulated states, not executed work or authentic receipts. Verify each replacement snapshot; do not write a scenario archive or reusable harness.
- Include overlapping gate requirements, an explicit separate-run requirement, and source changes invalidating prior evidence. Confirm permitted reuse, retained separate executions, and revalidation respectively. Retain required current identifiers and ensure read-only review does not imply write authority.
- Inspect `run.sh` to confirm the new rule and edited agent/skill files use existing sync paths. No managed filenames are retired in this slice, so no deletion migration is needed; user extras remain preserved.
- Inspect the config and policy assertions to confirm the wildcard instructions and privilege denials remain unchanged. Do not execute the provisioning runner as a test.
- Keep shell/config files unchanged; inspect the diff to verify this. The existing `tests/test-policy.sh` deletes scratch files and must not be invoked by an agent under the current shell-deletion policy. If an applicable required check cannot be run, report the limit and hand it to the operator; do not silently waive it.

**Acceptance:** Report observed source properties and scenario outcomes separately from live behavior. Text/scenario checks do not establish reliable model behavior or prove that a deployed host loaded the rule.

## 4. Apply And Check Separately

Before host application, the non-root operator preserves the existing four managed file versions and records whether `~/.config/kilo/rules/plan-lifecycle.md` already exists, preserving that version if present. Use a user-owned location outside loaded context directories so backups do not become additional instructions.

After explicit host-application approval, the non-root operator runs from `/home/luke/bootstrap`:

```bash
./user/init.sh 37-kilo-settings
kilo config check
```

Expected result: the rule and updated managed files are deployed through existing paths, local extras are preserved, and effective configuration validates. The runner also performs its existing scratch/timer and config housekeeping; approval must cover the existing step, not assume a five-file-only live operation. Reload Kilo or start a fresh session before assessing instruction loading.

Verify deployed content against the source and confirm a fresh session receives the rule. Check for conflicting extra loaded rules without removing user-owned context; report conflicts. Observe one explicitly authorized fictional plan creation/update/completion exercise, checking replacement rather than accumulation. Report behavioral failures without launching a broad benchmark campaign.

If deployment partially fails, inspect which managed files changed; do not assume the runner rolls back Markdown. If the new context causes a regression, the operator restores only the backed-up managed files, restores the prior rule or removes the newly introduced rule if none existed, then reloads Kilo. Preserve user extras; broader runner side effects require separate disposition.

If policy regression testing is needed, the operator can run from the same directory, with an existing user-owned scratch parent:

```bash
TMPDIR="$HOME/.tmpdir" bash user/init.d/37-kilo-settings/tests/test-policy.sh
```

This test uses an isolated HOME and a stubbed Kilo validator; it checks migration invariants, not actual instruction loading or model compliance.

## Current State

Review complete; plan finalized with no unresolved implementation decisions. No source implementation, tests, provisioning, or live configuration changes performed. Next action is source implementation after an explicit request; live validation remains pending separate host application. Update this section in place; do not append execution history.
