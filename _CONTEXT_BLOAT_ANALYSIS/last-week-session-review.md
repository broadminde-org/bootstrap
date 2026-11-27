# Last Week's Sessions: Drift, Sprawl, and Wasted Work

Date: 2026-11-22
Workspace: `/home/luke/netbird_pfs`
Review window: 2026-11-15 21:32:06 UTC through 2026-11-22 21:32:06 UTC.

## Bottom Line

The sessions corroborate the two reports. The strongest evidence is not just
large documents: **stale or conflicting execution context repeatedly caused
expensive decisions, additional approval conversations, and work that did not
advance the first real update/rollback.**

The recurring loop was:

1. Resume from a large plan or handoff containing several generations of state.
2. Discover that its premise, caller, inputs, or acceptance conditions do not match reality.
3. Build or repair a supporting component and run expensive validation.
4. Append the result and its qualifications to the execution context.
5. Resume with more context, but still without the first native outcome.

There is also direct admission of avoidable waste. One executor acknowledged
repeating a roughly 55-minute Python stage after an incorrect environment and a
known failure. Another acknowledged choosing its own session cutoff and then
unnecessarily requiring operator permission to continue. These are stronger
findings than inferring waste from a large test count. [S01, S08]

**Not all supporting work was waste.** Tests found real defects, fresh fixtures
removed unsafe historical dependencies, and measured fixture optimizations worked.
Several expensive sequences and supporting investigations were explicitly
operator-authorized. The problem is principally stale premises, acceptance
design, sequencing, and state management, not a blanket failure to obey scope.

This review uses [Default Agent Context Analysis](default-agent-context.md),
[Recent Plans: Context Bloat and Drift](recent-plans-bloat-and-drift.md), and the
[four-mode framework](FIX_THIS_SHIT.md). Session identifiers and selected message
identifiers are listed below so the evidence can be retrieved with local recall.

## Review Coverage

A read-only census of Kilo's local SQLite database selected messages created
inside the stated window, for the database-identified project whose worktree is
this workspace. It found 307 active sessions: 62 roots and 245 children.
Excluding the two earlier context-report sessions and their one child leaves
the following **304-session review cohort**. This is not a claim that every
session was updater execution; it includes planning, reviews and other workspace
work. [S28]

| Recorded activity | In-window count |
|---|---:|
| Parent/root sessions | **60** |
| Child sessions | **244** |
| Messages | **11,283** |
| Tool calls | **20,648** |
| Plan-read tool calls | **509** |

The database census covered the cohort's metadata. The deeper thematic review
read **24 root-session transcripts and three historical child-review transcripts**
listed in the evidence register, concentrating on the execution chains implicated
by the two reports. An opening just before the window is used only as boundary
context; its earlier messages are not included in the in-window counters.

No registered sessions in that project had managed-worktree directories; the
historical directory values were this workspace. This does not establish that
no deleted or unregistered sessions ever existed.

These counts establish workload, not waste. Neither 244 child sessions nor 509
plan reads is inherently unnecessary. Their significance is the repeated stale
state, nonintegrated contracts and redundant acceptance demonstrated below.

## Findings

### 1. High: Expensive validation was repeated before a known failure was resolved

The Phase 1 optimization executor said:

> "I didn't need to run it twice. That was a bad execution choice."

It explained that the standalone invocation omitted `TMPDIR`, causing 28
avoidable errors, and that it started the full gate before properly resolving
or reporting the other failure. [S01, `prt_1f2201508001ljchJNKML0eBQb`]

| Historical execution | Recorded result | Elapsed |
|---|---|---:|
| Standalone Python | 1,884 tests; one campaign-ID failure and 28 environment errors | 3,270.901s |
| Subsequent full gate | Python repeated; two failures and one error; later stages did not run | 3,574.152s |
| Combined sequence | Neither established final integration | **114m05s** |

This is elapsed execution burden, not 114 minutes proven wholly unnecessary.
The environment mistake, known-failure sequencing, and repeated Python stage
are the demonstrated avoidable elements.

Phase 2 inherited the same standalone-then-full-gate pattern. Its prerequisite
work included a failed 1,885-test standalone run, a successful 1,885-test
standalone run, and then a successful full gate repeating Python. Those three
runs total **177m14s**, excluding focused checks. The operator explicitly chose
to close Phase 1 first and authorized the subsequent correction. That makes the
expense authorized, but does not supply a distinct purpose for duplicate
exhaustive coverage. [S02]

The release-completion session later demonstrated a better alternative: after
operator approval, it ran only the remaining 14 stages, corrected one installer
fixture, and retried the affected five stages without repeating root race or
Python. [S05]

**Report connection:** Recent Plans finding 6 is confirmed by actual execution,
including an explicit executor admission, not merely duplicate commands on paper.

**Framework:** Validate known failures and invocation prerequisites first; prune
redundant acceptance clauses. Preserve required coverage, but state what distinct
contract each exhaustive run proves.

A smaller but especially clear overchecking example occurred on November 17:
placing every helper-build source into each resident SSH fence exhausted the
fixture's fixed 20-second budget. The correction separated a 434-file build
inventory from a 60-file execution inventory. Binding build inputs was useful;
repeating that whole inventory at every execution fence was the placement error.
[S20, `prt_1e80ff494001Fru3jlF630RiCk`]

### 2. High: Source changes during validation destroyed its acceptance value

The Phase 1 executor corrected snapshot-name handling while its gate was still
running, changing source pins and exception expectations. It subsequently said:

> "That gate result is therefore stale and cannot validate the final tree."

The relevant gate occupied approximately **59m34s**. Its failures combined the
pre-existing campaign-ID problem with consequences of mid-run source changes.
[S01, `prt_1f24006f0001UY4N87KZr0NVVg`]

The same investigation initially attributed absolute-name handling to tarfile
stripping a leading slash, then corrected that assertion:

> "Tarfile preserves the leading slash, so the new predicate incorrectly treated it as unrelated."

[S01, `prt_1f238e858001gq7RSl0w4ZSLSB`]

This combines an unvalidated premise with incompatible running and edited source
states. Source-stability checks correctly detected the problem; the avoidable
error was executing validation against moving inputs.

**Counterexample:** The self-contained fixture session validated immutable copied
sources while working-tree corrections proceeded, then ran a new serialized gate.
Those edits did not invalidate the already-running copy. [S04]

**Report connection:** Conflicting execution generations are not only a reading
problem. They can consume an hour and leave no final-tree acceptance result.

**Framework:** Validate the suspected behavior with a small reproducer; retain
one clearly identified source generation per accepted run.

### 3. High: Stale plans changed what the executor was actually accomplishing

The optimization plan advertised replacing an 11,106-file recursive copy with
411 admitted inputs. The current tree already copied only those 411 inputs:

> "The current tree already limits product copies to 411 admitted source files."

[S01, `prt_1f1c1e368001T1Wk6IjAQhBRRi`]

Both before and after copied **2,632,324 source bytes per product**. The actual
change consolidated selectors and added five contract tests. Focused elapsed
time changed from 195.868s to 205.660s. That is neither the advertised new copy
reduction nor a demonstrated performance regression: the test selection changed
and build variance was not isolated.

A separate review then found the plan still instructed a fresh executor to
implement Phase 1 even though its code, measurements, tests, and documentation
already existed. It changed the queue to closeout rather than implementation.
[S03, `prt_1f252327f001Rx6Gc7Z92c9CxT`]

The older E-F plan still calls itself the "authoritative operational E-F queue"
at [lines 3-5](../.kilo/plans/corvid-update-remaining-work.md#L3). Reconstructing
why it is no longer current requires newer documents and their supersession
rules. This corroborates the second report's authority problem.

**Counterexample:** The Phase 1 executor found and disclosed the stale copy premise
before implementing and declined to claim the historical savings as a fresh win.
The verification was useful; the stale plan still created unnecessary remapping.

**Framework:** Validate the current premise before estimating benefit; compact
completed work into status; prune executable language from superseded queues.

The earlier sessions also contain direct factual corrections: an assumed
`RetainedAssets` API did not exist; two `CapturedSSH` implementations were
confused before an audit established that no transport change was needed; and a
claimed Ruff pass was withdrawn after reading its actual lint log. [S19, S23]
These are bounded false starts, not evidence of completed redundant rewrites.
They illustrate how provisional assumptions or premature status can poison the
next handoff if recorded before validation.

### 4. High: Unrelated workspace state became an updater release blocker

A 458-test focused run passed, but its broader source inventory included
`tests/firewall_rule_execution.py`, which changed during execution. The release
session initially treated the changed binding as blocking unchanged-source
integration. The operator asked why that file mattered and then clarified that
firewall-rule creation was no longer part of Corvid. [S05]

The assistant subsequently distinguished the facts correctly: this did not
demonstrate an updater defect, and the full gate could still legitimately include
firewall tests. The operator amended **Corvid source-stability admission**, not
the existing gate selection. The original receipt remained unchanged.

The defect here is an overbroad acceptance boundary. Concurrent work in another
subsystem leaked into the updater's release state, generating a blocker and an
operator correction despite passing selected tests.

**Report connection:** The default context mixes unrelated project tracks;
the plan report identifies unclear admission scope. This is a concrete instance
where that mixing affected execution.

**Framework:** Curate the relevant subsystem and dependency scope before long
validation, rather than treating every workspace change as equivalent product
drift. Do not silently exclude shared dependencies or required gate tests.

### 5. High: The first integrated outcome kept losing to supporting machinery

This was already visible on November 16. A coordinator's real source and
terminal adapters could not jointly satisfy its exact contracts, while doubles
bypassed those checks. After correction, new pre-dispatch reservations made
normal concrete admission fail unconditionally. [S27,
`prt_1e371e92d001GgYqxCyVJY0SLI`, `prt_1e386ba31001SnYKFpzzaNlpXE`]

The corrections and re-reviews were necessary once those bugs existed. The
avoidable sequencing was allowing separately passing contracts to accumulate
before exercising their real composition.

The November 20 review of the newly proposed healthy lane found three concrete
execution contradictions: [S09]

- Signed-download admission was required before the signed assets were generated.
- The named healthy executor required the exact controller and continuous custody that the healthy lane intended to defer.
- Rollback required both preserving its successful update and a restore receipt; the existing restore path would erase that prerequisite.

These were real dependency/interface errors, not objections to retaining required
safety checks. The replacement queue corrected them by separating unsigned
readiness from signed admission, naming a controller-independent healthy path,
and adding genuine continuation proof.

Even then, a milestone-1 implementation worker reported a full passing gate with
1,932 Python tests while the production healthy transport, canonical execution,
admission revisions, and rollback continuation remained missing. It explicitly
reported that this was unfinished source implementation, not a reserved-authority
blocker. [S10]

The database attributes **352 messages, 420 tool calls, and 74,186,337 recorded
token units** to that worker's own in-window messages. Most recorded usage is
context replay, not new output; this is workload associated with an explicitly
unfinished integrated assignment, not an estimate that all 74 million units
were avoidable. [S28]

The subsequent integration session found wrong API usage, incompatible request
shapes, premature terminal waiting, SSH-owner confusion, missing persisted nonce,
and receipt labels exceeding the store's limit. Its completed caller finally
passed focused integration and the full local gate. These fixes were necessary;
their late discovery shows why testing components before composing the caller
did not establish readiness. [S06]

The reviewed final states still record **no live UPDATE rows executed**. The
476-row campaign and publication remain unqualified. This is documentary session
evidence, not a new independent audit of every live receipt.

**Report connection:** Recent Plans finding 5 is supported by actual missing
interfaces and late integration defects, not just the number of offline milestones.

**Framework:** Curate supporting work around the next callable operation. Every
supporting change should identify the concrete blocker and operation it unlocks.
Surface missing external inputs before further implementation or full gates.

### 6. Medium: Admission conversations had no compact, stable finish line

Milestone 0's acceptance accumulated a firewall-scope amendment, a specific
clock-test exclusion, a 14-stage continuation amendment, and then explicit
cumulative reconciliation. After all stage outcomes existed, the session still
stopped at the remaining cross-run source-binding requirement until the operator
accepted that limitation. [S05]

The assistant was right not to silently waive the written contract. The waste
is the acceptance design and late reconciliation: several conversations were
needed to decide what one milestone required and which previously completed
results could count.

Milestone 2 added a different problem. Readiness repeatedly required broad
source/dependency/compiler/runtime authentication alongside host and snapshot
admission. The operator confirmed snapshots, asked why values already in config
needed supplying, and described manual Hyper-V recovery. The assistant eventually
accepted that recovery model and admitted:

> "I asked too broadly for a VM identity ..."

[S07, `prt_1fd063a54001BMMSKNrxk2M706`]

The next immediate missing input was management-observation API access. The
assistant explained that this was introduced by the independent management
observer, not something Corvid needed simply to enroll or operate. Local tests
had used doubles for that HTTPS observer. [S07,
`prt_1fd3511da0013Dm4y2V1sTnuiA`]

The independently authenticated observations may be required. What is missing
is an early, finite input contract stating who supplies each proof and what
operation it enables. A generic demand for "complete authentication" invites
another preparation exercise without establishing how admission closes.

**Qualification to the previous report:** The clean-slate plan's optional
snapshot identifiers apply to **initial implementation**, not necessarily live
execution. [Lines 3758-3759](../.kilo/plans/1794861195623-corvid-clean-slate-inline-qualification.md#L3758)
say so explicitly; live bindings later require actual baseline identity.
Requesting the correct live recovery point is not itself evidence of scope drift.
The stronger evidence is overbroad requests, repeated operator re-entry, and
late discovery of a new harness-specific input.

**Framework:** Compact admission into a current table: required artifact/fact,
acceptable proof, supplier, status, and operation unlocked. Validate existing
config before asking for values again. Changes to the trust model need an explicit
decision, not accumulating caveats.

### 7. Medium: Goal resumptions replayed obsolete state and status-only turns

Across the two November 20 release sessions, the saved recall exports contain:

- **13 synthetic goal-continuation prompts.**
- **10 wakeup-scheduling calls** and nine explicit wakeup deliveries.
- One repeated milestone-0 goal after milestone 0 had explicitly closed.
- Two repeated original-process goals after that process had failed and a retry replaced it.
- Four deliveries in the later session that only checked process status, scheduled another wait, and reported waiting.

[S05, S06]

The later wakeup text correctly said to inspect the retry, "not the failed
original," while the enclosing synthetic goal still named the original process.
This is a visible clash between current instructions and persistent old objective
text. It increases interpretation burden and could cause wrong-run decisions;
the reviewed transcript does not establish that it actually inspected the wrong
process.

The November 21 readiness session added four synthetic goal prompts, four
wakeup calls, and three explicit deliveries. An additional "check now" was
operator-requested and should not be classified as autonomous churn. [S07]

Scheduling waits was often correct under the goal rules. **The waste is redundant
status-only re-entry and replaying stale instructions, not waiting itself.** The
saved transcripts do not independently establish delivery of a process-exit
notification, so they cannot prove the agent ignored such a notification.

**Report connection:** This adds a runtime source of bloat absent from the two
file-focused reports: persistent objectives and generated resumptions can retain
obsolete state even after a plan is corrected.

**Framework:** Prune obsolete goal objectives/process references when state
changes; use process completion to resume when supported. Otherwise schedule
coarse waits based on measured duration, without rereading the whole operational
history at every status check.

### 8. Medium: Historical output and live authority were repeatedly conflated

November 18 validation exposed tests depending on dated failed-run artifacts and
original inventory bytes. One negative test could "pass misleadingly" because
it accepted any `ValueError`, including historical inventory drift before the
intended assertion. [S11, `prt_1edf262e90015MgGphgCdY8ni2`]

The operator separately challenged required fixture inputs living under
`test-results/`. Stable synthetic fixtures and an explicit authenticated
historical suite resolved that design flaw without rewriting the original
reports. A corrected history-free gate passed 1,832 Python tests and 15 stages.
[S04, S11, S12]

The firewall-plan review showed the analogous operational problem: dated
observation/proof directories and hand-reviewed bindings were absent, while
the old plan still described already-implemented work and retired inventory.
The operator explicitly interrupted a growing investigation:

> "this is getting much more in depth than it should be."

[S13, `prt_1f6cc6d21001RJ60wunhVXs8aq`]

Creating an artifact directory did not produce admission evidence; the assistant
correctly said so later. But the session had to repeatedly reconstruct which
blockers were actually resolved. It also investigated old host associations after
the operator identified the current inventory as authoritative, prompting another
explicit stale-context correction. Current address selection and host-key
authentication remain different requirements; this does not justify bypassing
the latter.

**Counterexample:** November 21's legacy-input audit found no safe removal set
and corrected an overbroad description of active `config.json` as legacy. The
operator explicitly requested that investigation. Auditing consumers rather than
deleting by filename was the right response. [S07]

**Framework:** Separate current fixtures, operational admission, and historical
evidence. Prune historical execution authority, not authentic evidence or protected
operator files.

### 9. Medium: Artificial session boundaries caused avoidable handoffs

The November 17 executor explicitly said:

> "I chose `18:00 UTC` myself ... it was not a deadline you imposed."

It also said treating that cutoff as requiring approval to continue was
unnecessary. [S08, `prt_1eaab3b6a001LsArT50W59D5F7`]

This is a concrete workflow stop unrelated to an actual update transaction,
catalog validity, execution timeout, or unavailable authority. Its cost is
additional continuation conversations and context reconstruction.

Do not overgeneralize: some session boundaries and phase-only execution were
explicitly operator-requested. Those must be honored. The avoidable behavior is
inventing a concrete stopping condition from an ambiguous planning instruction
and then treating it as an external safety gate.

**Framework:** Validate who imposed a boundary and what it protects; prune
self-created stopping rules while retaining real operation bounds and actual
pause instructions.

## What The Token Evidence Does And Does Not Establish

Unlike recall alone, the local database retains normalized usage fields. Across
10,360 in-window assistant messages, the cohort's recorded counters were: [S28]

| Stored normalized field | Sum |
|---|---:|
| `input` | 15,131,362 |
| `output` | 3,502,361 |
| `reasoning` | 2,896,441 |
| `cache.read` | **1,304,577,026** |
| `cache.write` | 84,944,303 |
| `total` | **1,411,051,493** |
| Stored cost accumulator | **772.6520** |

For all 10,312 records containing `total`, the five buckets sum to that total
exactly. The remaining 48 records have zero buckets and no total; five still
contain positive cost. Counters were summed only from message records, not
again from step-finish records, session summaries, or event history.

**This is approximately 1.41 billion cumulative recorded token units, not 1.41
billion tokens of newly written material.** About 92.5% of the total is the
cache-read bucket alone: repeated context replay dominates the recorded volume.
The stored cost accumulator is application accounting, not an independently
verified invoice, verified currency denomination, or an avoidable-cost estimate.
Raw provider usage and the normalization implementation were not audited; these
bucket semantics must not be generalized to every provider's raw output fields.

No usable compaction-count telemetry was found in the examined part/event
markers. That means compaction history was **unavailable**, not proven absent.

The metadata review also found a conservative lower bound of **85 generated
goal-continuation texts** matching their retained goal objectives: 345,867
characters of full text, including 174,434 objective characters. Matching current
retained objectives can miss older objectives; these are neither a complete
continuation census nor tokenizer/billing measurements.

Bounded command inspection identified **12 bare full-gate invocations and seven
standalone full-regression invocations**; list-only commands were excluded.
Fourteen `bash -n test_all.sh` syntax checks were also excluded: mentioning the
gate script is not the same as running its gate.
Invocation is not completion: successful completion of the full gate cannot be
inferred from launch metadata. These counts are not 12 passing gates or 12
redundant gates, and unrecognized wrappers can make them lower bounds.

The default-context report measured approximately 7,075 tokens of file-backed
instructions, with root `AGENTS.md` dominating that total. Its 20,000-35,000
overall startup estimate includes platform layers and is **not provider telemetry**.

The plan report measured about 804,316 characters across four inline-update
plans, approximately 201,000 tokens by a character heuristic. That is potential
explicit-read context, **not proof every session loaded all four plans**.

The transcripts corroborate the mechanisms: repeated plan reads, re-reviews,
embedded full plans, long generated goals, corrections and growing handoffs.
Those mechanisms can multiply an already-heavy baseline. The recorded usage
supports that replay is a large part of the workload; it does not establish
which replay was unnecessary or an exact avoidable-token count or monetary loss.
Cached replay, compaction, provider accounting, and changed test selections matter.

The November 22 file-size estimates must not be retroactively treated as measured
initial prompts for every November 15-21 session. Earlier full system-prompt
captures were not available in this review.

The unrelated Playwright/Svelte tool exposure identified in the first report is
a plausible fixed overhead and a curation opportunity. **This transcript sample
does not demonstrate irrelevant browser/Svelte calls causing the engineering
drift.** The stronger demonstrated sources are stale state and bad sequencing.

## What To Preserve

- Real failed receipts and authentic historical artifacts; failed evidence must not be relabeled as passing.
- Exact signature, origin, expiry, sequence, running-image and required independent-observation checks at their actual trust boundaries.
- Explicit operator authority for reserved signing, rebinding, host operations, Git changes and publication.
- The accepted 476-row campaign and the distinction between local tests, native diagnostics, live qualification and publication.
- Focused regression fixes for demonstrated defects, rather than categorizing every safety review as churn.
- Actual fixture wins: three warm requests improved from 9.90s to 1.56s and three disposable copies from 21.65s to 4.90s. These are component timings, not proof of a comparable full-gate gain. [S14]

## Recommended Changes

These are recommendations for a subsequent authorized change, not changes made
by this review.

| Priority | Change | Failure addressed | Observable success |
|---|---|---|---|
| 1 | One current execution queue with concise status, blockers and next operation; historical banners on superseded queues | Poisoning / clash | A new executor can identify the next operation without resolving several competing plans |
| 2 | A finite readiness table naming proof, supplier and operation unlocked | Distraction / sprawl | Missing management, recovery, trust and native inputs are identified before another long validation cycle |
| 3 | Focused reproduction and preflight before exhaustive validation; one full gate for overlapping coverage unless a distinct purpose is stated | Churn | No repeated full Python run merely because two inherited checklist entries select it |
| 4 | Immutable, scoped validation inputs and a clear active-run owner | Clash | Concurrent unrelated changes neither invalidate Corvid evidence nor create duplicate runs |
| 5 | Replace narrative handoffs with current-state summaries and evidence references | Distraction | Expired PIDs, stale blockers and old hypotheses are absent from the next execution packet |
| 6 | Refresh persistent goal state and prefer completion-driven resumption | Clash / token replay | No resumed goal names a failed process or a closed milestone as current |
| 7 | Reduce root instructions through progressive disclosure and scope irrelevant tools | Distraction / confusion | Essential boundaries remain loaded; operation-specific history and unrelated tool schemas do not |
| 8 | Keep fixtures and result outputs separate; preserve history outside executable authority | Poisoning / clash | Ordinary regressions run without dated operational reports; historical checks remain explicit |

Do not solve this by adding another large policy file. A small authoritative
state surface and removal of conflicting authority are more valuable than
more instructions telling agents not to drift.

## Evidence Register

Use `kilo_local_recall` in read mode with the session ID. Message IDs identify
specific excerpts where recall search exposed them. Dates and durations are
historical transcript reports unless explicitly described as current file checks.

| Ref | Date | Session | Evidence |
|---|---|---|---|
| S01 | Nov 19 | `ses_e0e4fcbc2ffe8m6xyA5Vv292F2` | Phase 1 stale premise, duplicate Python, wrong TMPDIR, mid-run edits and corrected tarfile assumption |
| S02 | Nov 19 | `ses_e0d956da3ffeTPhRjwYke9kKz6` | Phase 2 entry/Phase 1 closeout; repeated exhaustive prerequisites, authorized correction and successful stable gate |
| S03 | Nov 19 | `ses_e0db35a6affetqcFybB0GoDRLD` | Plan still instructing implementation after implementation existed |
| S04 | Nov 18 | `ses_e106a2be7ffeceTa5UON356RBV` | Fresh fixtures, immutable validation copies, history-free gate; `prt_1f039e34b001e5Lcu7ZA1PbJeC` |
| S05 | Nov 20 | `ses_e08af2eabffeboRvCbCkokhKX6` | Firewall drift, cumulative amendments, stage continuation, stale milestone goal and partial healthy implementation |
| S06 | Nov 20-21 | `ses_e05570b74ffe2E6Ods4lfM1idV` | Actual healthy integration defects, two final gates, stale process goals and no live UPDATE rows |
| S07 | Nov 21 | `ses_e044472eaffea1BoYWmTe946Jw` | Narrow readiness work, repeated input requests, manual recovery accepted, management API input and authorized legacy audit |
| S08 | Nov 17 | `ses_e157a85f8ffeHArmwb0DcWT6XW` | Self-chosen deadline and unnecessary continuation approval |
| S09 | Nov 20 | `ses_e090b014effe8eICUuw5KBHOAL` | Read-only healthy-plan review: signed-asset cycle, exact-controller dependency and rollback restore contradiction |
| S10 | Nov 20 | `ses_e07f62fc9ffeWHNQGdLTtK1BqG` | Passing component gate while core healthy execution still absent; `prt_1f844e447001L5I6vx2w9ZDeO3` |
| S11 | Nov 18 | `ses_e12ac38cfffeITPaB2LQ5M5Xe5` | Stale historical fixture inputs and misleading negative pass |
| S12 | Nov 18 | `ses_e120417a5ffeQu1tC6E4HcITWU` | Synthetic recovery baseline, 24 tests and forbidden historical reads; `prt_1edff78590011FJBPdFszzMt22` |
| S13 | Nov 20 | `ses_e0953d48fffeJ9UtuRxxHzUOff` | Firewall status reconstruction, operator interruption, artifact directory versus admission, stale inventory associations |
| S14 | Nov 19 | `ses_e0ee4f5c7ffeEKDk2x9HL14VVy` | Measured fixture wins, later unset-TMPDIR run and no established whole-gate improvement |
| S15 | Nov 19 | `ses_e0eb80ec6ffenjsnki7HnQSYMN` | Counterexample: did not duplicate active validation; distinguished component timings and honored stop |
| S16 | Nov 16 | `ses_e1c93b30dffeaE87AWBCxUKhtm` | Resident interoperability, impossible timing equality and successive component closeouts |
| S17 | Nov 16 | `ses_e1afa41ecffepbZ9LlgfBg1EZ0` | Continuous E-F goal, actual native support work, admission block and explicit user pause |
| S18 | Nov 16 | `ses_e19ef9e99ffe1y3olEj2JIWcll` | Delay investigation, purge versus VM restoration correction and trust-model decisions |
| S19 | Nov 16-17 | `ses_e19459ce0ffeuGbqEDr0V2WiI4` | Healthy-first request, foundations-first sequence, nonexistent API and CapturedSSH confusion |
| S20 | Nov 17 | `ses_e18009051ffePJ0mYiFjAPQzXV` | Input-free execution, repeated build inventory exhausting SSH-fence fixture budget |
| S21 | Nov 17 | `ses_e17a23320ffe6sw063Y3zrvkAi` | Successive source/bracket/terminal closeouts with usable execution still unfinished |
| S22 | Nov 17 | `ses_e15257143ffeUOQGJ2jEcTyd66` | Publisher containment, operational pointer sync and genuine admission boundary |
| S23 | Nov 17-18 | `ses_e14976c32ffeHGiHGgeRHjR0F3` | False lint-pass correction, overstated management-URL prerequisite and authorized installer changes |
| S24 | Nov 15-16 | `ses_e1ee4725dffepuBqpdiRLeoSmV` | Explicitly source-only assembly scope; opening five minutes before cutoff is boundary context only |
| S25 | Nov 17 | `ses_e18fa0079ffeqMx7d1qQ3YFEJg` | Original operator-requested one-milestone session rule and concrete interface corrections |
| S26 | Nov 17 | `ses_e1551adefffe5EzTrFEuCUmlgF` | Authorized deadline/workflow constraint removal without waiving required final gate |
| S27 | Nov 16 | `ses_e1c8f5610ffe3BZpmZxi55RUGg` | Concrete producer/coordinator incompatibility hidden by doubles and reservation regression |
| S28 | Nov 22 census | `/home/luke/.local/share/kilo/kilo.db` | Read-only project/session/message/part metadata and normalized message-usage counters, filtered by message creation time |

For reproducing S28, open SQLite with `mode=ro` and `PRAGMA query_only=ON`.
Resolve the project using `project.worktree`, include its registered
`project_directory` entries, and filter `message.time_created` inclusively
between **1794778326000** and **1795383126000** milliseconds. Exclude the two
report roots `ses_dfae34409ffeAOZQqyw3uyLU9l` and
`ses_dfaec621affeeaWlPSWg1nA754`, this review root
`ses_dfad397aeffeCY55isunL7T3sE`, and their recursive descendants. Count tool
parts by joining their message IDs to those window messages; sum usage/cost
only from assistant message JSON, once per message. Session update timestamps
are not the inclusion filter.

## Limits And Scope

- This is a thematic primary-transcript review, not a line-by-line audit of every conversation or a full code/security review.
- Recall can truncate large sessions. Bounded reads of saved exports were used for the longer release sessions; exports omit some question answers and tool details.
- Database access used SQLite read-only mode. The cutoff uses message creation time, not session update time; boundary-straddling provider requests cannot be prorated precisely. The two prior report families and this review family were excluded; this review began just after the cutoff.
- Assistant assertions were cross-checked against dialogue, selected current source/plan text, and corrective statements where available. Historical test receipts were not independently rerun or fully reauthenticated.
- User-requested supporting work and revisions are not classified as unauthorized behavior. Pausing at a genuine authority/input blocker is not itself waste.
- Current document references describe files inspected on November 22; line numbers may subsequently move.
- No tests, firewall operations, candidate generation/signing, configuration changes, plan edits, Git mutations or publication ran during this review. Only this report was added to the workspace.
