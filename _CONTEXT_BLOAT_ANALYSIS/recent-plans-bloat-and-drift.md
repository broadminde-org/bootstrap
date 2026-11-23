# Recent Plans: Context Bloat and Drift

Date: 2026-11-22
Workspace: `/home/luke/netbird_pfs`
Scope: Recent plans and selected execution transcripts/source references, primarily November 17-21.

## Bottom Line

There is substantial context bloat and execution-state drift. The main problem is not excessive safety checks: it is mixing current instructions, completed work, historical evidence, and superseded decisions in the same executable documents.

This complements [Default Agent Context Analysis](default-agent-context.md). Plan contents are explicit-read context, not automatically loaded startup instructions.

## Findings

### 1. High: Multiple plans still claim operational authority

[`corvid-update-remaining-work.md:3-16`](../.kilo/plans/corvid-update-remaining-work.md#L3) calls itself the authoritative E-F queue. [`corvid-update-safety-remediation.md:14-24`](../.kilo/plans/corvid-update-safety-remediation.md#L14) names another authoritative resume point. The clean-slate plan supersedes them, then delegates execution to release completion at [`1794861195623-corvid-clean-slate-inline-qualification.md:5-13`](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L5).

Supersession is recoverable, but only by reading across documents. An executor entering through an old plan can encounter obsolete campaign scope, F sequencing, and attempt restrictions.

Recommendation: Retain historical content, but put an unmistakable "Historical, Not Executable" banner and current-queue link at the top of superseded plans.

### 2. High: Execution plans have become evidence archives

The clean-slate plan's implementation tasks begin at **line 3,783**, after thousands of lines of handoffs. The newer release plan explicitly says not to append narrative handoffs at [`corvid-inline-release-completion.md:137`](../.kilo/plans/corvid-inline-release-completion.md#L137), then does exactly that at lines 139-185. Those entries include expired process IDs, multiple failed gates, hashes, subsequent corrections, and superseded blockers.

| Plan | Lines | Characters |
|---|---:|---:|
| Update safety remediation | 3,607 | 325,949 |
| Remaining E-F work | 1,827 | 128,094 |
| Clean-slate qualification | 4,120 | 292,035 |
| Inline release completion | 200 | 58,238 |
| Test-pipeline optimization | 974 | 73,189 |

The four inline-update plans alone contain **804,316 characters**, roughly **201,000 tokens** using the approximate four-character heuristic. This is potential explicit-read cost, not automatically loaded startup context or measured provider usage.

Recommendation: Keep the operational queue replaceable and concise. Preserve detailed attempts in historical records and private evidence, referenced rather than reproduced. The 200-line release plan also demonstrates why line count alone is a poor bloat metric.

### 3. High: Some plans remain launchable after completion or invalidation

[`1794994974360-self-contained-test-fixtures.md:115-205`](../.kilo/plans/1794994974360-self-contained-test-fixtures.md#L115) still presents an implementation queue, although the clean-slate plan explicitly closes that task at [lines 78-84](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L78). The optimization plan's header records completed phases, but its retained opening contract still directs Phase 1 closeout and prohibits later phases at [`corvid-test-pipeline-optimization.md:7-15`](../.kilo/plans/corvid-test-pipeline-optimization.md#L7).

More materially, [`corvid-repository-extraction.md:3`](../.kilo/plans/corvid-repository-extraction.md#L3) says "implementation-ready," while line 13 requires remapping if updater changes land first. That trigger has occurred. Its packaging contract at line 54 still requires management/base-URL inputs deliberately removed from current packaging.

Recommendation: Give every plan one disposition: active, completed, blocked pending remap, or historical. Source implementation alone must not be presented as verified completion.

### 4. Medium: Admission requirements have an unclear finish line

The clean-slate contract explicitly trusts the lab OS tools, root-owned scratch, operator restoration, and management TLS at [lines 3770-3772](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L3770). Later release handoffs repeatedly require independent source/dependency/compiler/runtime authentication at [`corvid-inline-release-completion.md:177-185`](../.kilo/plans/corvid-inline-release-completion.md#L177), without a compact definition of sufficient evidence for each requirement. Snapshot identifiers are described as optional in the original contract at [lines 3714-3719](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L3714), while recent readiness work blocks on exact snapshot/recovery identification.

These requirements may be justified, but the effective boundary is difficult to reconstruct.

Recommendation: For each remaining admission, name the required artifact, acceptable proof, who supplies it, and what operation it unlocks. Resolve trust-model differences explicitly rather than letting "complete authentication" expand indefinitely.

### 5. Medium: Supporting work has repeatedly displaced the first integrated outcome

The clean-slate history records a tenth offline milestone adding an optional observation bracket at [lines 2231-2280](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L2231), and a twelfth adding optional terminal composition at [lines 2009-2046](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L2009). Both leave live admission unavailable. Release completion still records the first genuine update/rollback as pending at [lines 189-190](../.kilo/plans/corvid-inline-release-completion.md#L189).

Some supporting work was explicitly requested, and necessary safety defects were found. This is **not evidence of unauthorized work**. It does show a pattern of component progress without reaching the primary observable outcome. The newer release queue improves this by separating healthy and exact lanes.

Recommendation: Further supporting work should identify the concrete blocker it removes and the next executable operation it enables. Missing operator facts should not become another optional helper project.

### 6. Medium: Validation sometimes repeats exhaustive work without a distinct acceptance purpose

[`corvid-test-pipeline-optimization.md:303-320`](../.kilo/plans/corvid-test-pipeline-optimization.md#L303) and [`1795031915510-review-fixes-quick-first.md:104`](../.kilo/plans/1795031915510-review-fixes-quick-first.md#L104) require full standalone Python followed by the full gate, which itself runs full Python at [`test_all.sh:450`](../test_all.sh#L450). Separate environments or profiling can justify this, but that justification is not consistently explicit.

Recommendation: Preserve mandatory gates. For future plan revisions, use exhaustive duplicate runs only when they establish a genuinely different contract, not simply because both commands appear in the inherited checklist.

## What To Preserve

The plans correctly distinguish offline results from native qualification, retain failed evidence, protect frozen assets, and keep signing/publication and forced policy gated. The approved 476-row campaign is not itself evidence of drift, and this review does not justify reducing its required coverage.

The [firewall-rule creation plan](../ansible/pfsenseless/firewall-rules-creation-plan.md) is comparatively clearer: its main cleanup is renaming resolved "Current Blockers" and marking satisfied prerequisite steps complete.

## Recommended Reduction

1. Make `corvid-inline-release-completion.md` the single clearly named current execution queue, with current status, remaining blockers, and the next operation near the top.
2. Separate durable campaign requirements from historical handoffs. Do not delete evidence or silently change campaign identities, budgets, or decisions.
3. Add completed/blocked/historical dispositions to the fixture, optimization, quick-fix, extraction, and superseded updater plans.
4. Replace repeated admission prose with one concrete readiness table.
5. Shorten `AGENTS.md` to essential instructions and current holds. Its "pending integrated admission" wording at [lines 155-156](../AGENTS.md#L155) already trails the locally accepted milestone recorded in release completion at [line 175](../.kilo/plans/corvid-inline-release-completion.md#L175).

The highest-value change is **less history in the execution context, not fewer safety requirements**.

## Evidence And Limits

- File sizes were measured with `wc -l -w -m` on 2026-11-22. Token estimates use approximately four characters per token and are not exact tokenizer measurements.
- The review covered recent plans, selected execution transcripts, and selective current-source corroboration. It was not a complete source audit or an exhaustive review of all local sessions.
- References and statuses describe the reviewed files as of this date; line numbers may change after edits.
- No files, instructions, or plans were changed during the review; no tests or host operations ran. Historical acceptance receipts were not independently revalidated.
- This report was subsequently saved at the user's request. Its recommendations do not authorize implementation, live operations, signing, campaign rebinding, Git mutations, publication, or changes to required qualification coverage.
