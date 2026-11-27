# Bootstrap Host Context Audit

Status: proposed audit plan, 2026-11-22. Execute in a fresh session rooted at
`~/bootstrap` only when requested. This plan authorizes no configuration changes,
provisioning, cleanup, installations, Git mutations, or new Agent Manager sessions.

## Outcome

Produce an evidence-backed recommendation for a smaller, consistent host-wide
agent context, with clear source ownership and a safe future implementation order.
Distinguish token overhead from stale authority, conflicting instructions, and
execution churn. Do not implement recommendations during the audit.

The Corvid `AGENTS.md` cleanup remains a separate task. Record whether it has
happened before collecting baselines; do not require or perform it as audit setup.

## Scope And Boundaries

- Read bootstrap's applicable instructions first. Preserve its no-privilege-
  escalation rule and dirty/untracked work.
- Inspect bootstrap-owned context, installed host context, and the client paths
  that discover and inject it. Do not broaden into general host provisioning.
- Do not run `init.sh`, step entry points, `sync-kilo-context.sh`, migrators,
  package managers, MCP startup commands, or provisioning tests. Source review
  is sufficient for their ownership and mutation behavior in this audit.
- Do not read credential stores, private keys, `.env`, private host configuration,
  or dump live JSON configs. Use key-only/redacted structural inspection for
  instruction patterns, discovery paths, MCP enablement, and config precedence.
  Redact before tool output, not after capture. Record unavailable facts as unknown.
- No firewall, deployment, service, network, or production operations. Public
  documentation lookup is allowed when needed to resolve client behavior.
- Do not launch another client, change models, or create probe sessions merely
  to measure prompts. Use available client source and existing nonsecret metadata;
  request separate scope if an isolated runtime experiment is necessary.
- Audit operations are read-only except the requested final report. Keep scratch
  under unique `$HOME/.tmpdir/` paths; never delete user context or old evidence.

## Starting References

Read these four local report copies once:

- [Default agent context](../../_CONTEXT_BLOAT_ANALYSIS/default-agent-context.md).
- [Recent plans: bloat and drift](../../_CONTEXT_BLOAT_ANALYSIS/recent-plans-bloat-and-drift.md).
- [Last week's session review](../../_CONTEXT_BLOAT_ANALYSIS/last-week-session-review.md).
- [Four context failure modes](../../_CONTEXT_BLOAT_ANALYSIS/FIX_THIS_SHIT.md).

These are byte-preserved copies from `~/netbird_pfs/_CONTEXT_BLOAT_ANALYSIS/`.
Treat their observations as dated leads, not current measurements or executable
authority. Report-relative Corvid plan/source links still refer to the original
`~/netbird_pfs/` workspace; do not interpret them as bootstrap paths. Do not
repeat the week-long session census or load historical plans/transcripts wholesale.

Corvid cleanup completed in commit `2d7d2e1`: the root `AGENTS.md` is 6,999
characters, down 70.11% from 23,416. Read **Cleanup Disposition** in
`~/netbird_pfs/.kilo/plans/agents-md-cleanup.md` and use the current
`~/netbird_pfs/AGENTS.md` as the post-cleanup baseline, not the reports' old size.
The bootstrap audit has not been executed by copying these inputs.

Start the ownership trace with these bootstrap sources:

- `user/init.d/37-kilo-settings/`: `run.sh`, `migrate-kilo-jsonc.sh`, default/optional
  skill manifests, managed policy lists, `_config/`, `_kilo/`, and relevant tests.
- `user/sync-kilo-context.sh`: reverse synchronization and feature-skill routing.
- `user/init.d/lib/`: locate the actual preserve-sync implementation.
- Feature owners: `user/init.d/30-scripts/`, `60-caddy/`, `98-npm-shared/`, and
  `99-go-shared/`; expand only to producers/consumers found in the trace.

## Audit Sequence

### 1. Establish The Inventory And Ownership Map

Record the bootstrap revision/dirty state and audit time without capturing private
diffs. Enumerate instruction, rule, agent, command, skill, reference, and relevant
configuration sources in `~/.config/kilo`, `~/.kilo`, and `~/.agents`.
Check legacy roots and ancestor instructions only where discovery rules make them
relevant; do not recursively scan the whole home directory.

For each context item record its path, type, bootstrap owner or external owner,
installation trigger, update direction, and retirement behavior. Compare public
text sources using size/content hashes and scoped diffs. Classify differences as
matched, modified, missing, installed extra, or unresolved; do not adopt the live
copy or bootstrap copy as authoritative without tracing ownership.

Inspect preserve-sync, create-once configuration, optional-skill skipping,
migration refusals, reverse-sync deletion, and config-copy/diff exposure. A
source-level exposure opportunity is not evidence that a secret leaked.

### 2. Verify What Actually Loads

Identify the installed client/version using existing executable/package metadata
and the package-version-lookup workflow. Establish whether CLI and extension
behavior can both be verified; do not generalize one to the other.

Trace applicable config precedence, environment override names without values,
instruction globs, directory-scoped instructions, skill discovery/body loading,
selected-agent prompts, command expansion, and MCP schema exposure. Validate
against the matching installed implementation or authoritative documentation;
label documentation-only and runtime observations separately.

Build a loading table: item/layer, trigger, evidence, size, and confidence. Separate
always-injected text, catalog metadata, selected bodies, explicit references,
tool schemas, and transcript replay. Investigate advertised-but-missing skills
and duplicate discovery paths rather than assuming the filesystem equals the catalog.

Use existing nonsecret prompt/usage metadata if available. Otherwise report
character counts and clearly labeled token estimates. Do not present config
presence as connected-tool proof, or cached token totals as avoidable cost.

### 3. Review The Context For Defects

Read every in-scope rule, agent/command prompt, and discovered skill entry body.
Review referenced resources when their instructions are invoked or needed to
resolve a finding; inventory unread resources and explain their exclusion. Do not
claim every skill resource was audited merely because its `SKILL.md` was read.

Classify findings as duplication, contradiction, stale fact/authority, ambiguous
scope, overbroad trigger, unnecessary loading, or ownership/retirement risk.
Separate current defaults from conditional instructions and historical evidence.

Prioritize these leads, validating each rather than assuming it remains true:

- Repeated execution/evidence/retry policy in rules, language skills, and agents.
- Frontend design versus cognitive-accessibility precedence and Svelte trigger overlap.
- Artifact presentation guidance versus mandatory validation requirements.
- Global Playwright/Svelte exposure in non-frontend workspaces.
- Optional skill retention and external/builtin skill discovery.
- Scratch, configuration-input, permission, and safety rules with competing scopes.

Every material finding needs file/line evidence, its activation conditions, the
concrete failure or overhead mechanism, and a proposed disposition. Do not remove
safety requirements just because another layer also states them.

### 4. Recommend A Minimal Target And Migration Order

Propose a small universal core, task-specific entry points, and precise references.
For each item recommend keep, shorten, consolidate, scope, retire from discovery,
or preserve as history. Name the source owner and how an eventual change reaches
existing hosts without deleting user-installed extras or reversing through sync.

Separate supported mechanisms from ideas requiring client changes. Preserve
permission enforcement, credential protections, mandatory validation, actual
operation limits, and historical evidence. Do not add another large policy file.

Rank changes by demonstrated correctness risk, likely context savings, and rollout
risk. State the focused checks and optional disposable-host experiments required
for later implementation, without running them now. List unresolved decisions
and evidence gaps separately from implementable recommendations.

## Deliverable And Acceptance

Write one concise report in `~/bootstrap/docs/` when audit execution is requested,
using a descriptive non-overwriting filename. Keep private metadata out of tracked
documentation. Put detailed public inventory tables in the report or a linked
appendix only when necessary; do not embed full prompts or historical transcripts.

The report must contain:

- An executive recommendation and ordered future change queue.
- The source/install/discovery ownership map and a coverage/exclusion inventory.
- Loading evidence with measured sizes, confidence, and explicit estimate limits.
- Severity-ranked findings with source references and conditional precedence.
- Item-level dispositions, synchronization/retirement implications, and checks
  required before a later rollout.
- Unknowns and operations needing separate authorization.

The audit is complete when all in-scope context entry documents and mutation/
discovery paths are accounted for, recommendations preserve essential boundaries,
and another executor can identify the first change without rereading the Corvid
campaign history. Unavailable exact telemetry does not block a useful report;
it limits quantitative claims. No recommendations are applied during this audit.
