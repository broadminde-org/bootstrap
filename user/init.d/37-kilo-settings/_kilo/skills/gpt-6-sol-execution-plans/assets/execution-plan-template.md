# Execution plan: <short name>

> Copy only useful fields. Step essentials are objective/action, exact scope, acceptance evidence, and proportionate failure handling; IDs, budgets, deadlines, retries, and tracking are optional metadata, not universal requirements. Record only real limits. This plan records intent and references actual authority; current user grants, runtime permissions, and instructions govern actions, including separate commit/push/deployment gates.

**Plan ID / version:** <stable identifier and version>
**Owner / date:** <accountable person, ISO date>
**Executor:** <ChatGPT Work | Codex surface | API agent>
**Target model:** <gpt-6-sol | gpt-6.1-sol>
**Reasoning settings:** <valid effort; standard/pro mode where applicable>
**Actual limits, if any:** <only applicable token/cost/time/operation limits; no invented ceiling>

## 1. Objective

**Single observable outcome:** <resulting state, not an activity>
**Intended recipient / artifacts:** <user and exact artifact paths, records, or outputs>
**Non-goals:** <explicitly excluded work and side effects>
**First slice:** <smallest safe authorized integrated result, production implementation/caller and usable entry point where needed; actual deliverable for design/review/docs>
**Minimum prerequisites:** <blocking scope, safety, authority, or feasibility decisions; reversible assumptions separately>

## 2. Authoritative inputs and current state

**Sources:** <path, URL, or record with version/date>
**Current state / reproduction:** <observed baseline and exact reproduction where applicable>
**Source precedence:** <order used to resolve conflicts>
**Allowed assumptions:** <only documented, reversible, in-scope assumptions>
**Current execution queue:** <replaceable next actions/dependencies, separate from historical decisions/evidence; preserve stable API prefixes where applicable>

## 3. Constraints

**Compatibility / output requirements:** <schemas, interfaces, formats, platforms>
**Must remain unchanged:** <behavior, data, files, or public contracts>
**Forbidden approaches:** <specific disallowed implementations or actions>
**Required versus optional lanes:** <required behavior and smoke/core/final checks versus additional matrices, research, harnesses, and hardening>
**Supporting work:** <for unplanned substantial support or displaced priorities, concrete blocker/uncertainty and next execution enabled; no ceremony for normal required follow-on work>

## 4. Tools, permissions, and recovery

**Allowed reads:** <exact sources>
**Allowed writes:** <exact paths or records>
**Allowed network destinations:** <exact destinations or none>
**Credentials / sensitive-data boundary:** <permitted scope, prohibited discovery/disclosure>
**Required human or configured reviews:** <actions that stop at an approval gate>
**Forbidden actions:** <including unchanged retries, denial workarounds, wider permissions, and fabricated results>
**Delegation / parallelism rule:** <independent work only, concurrency limit, shared-state isolation>
**Rollback / recovery:** <specific method for every side effect; steering/cancellation is not rollback>

## 5. Ordered steps

### Step <ID> — <short action>

**Depends on:** <step IDs or none>
**Action:** <one concrete operation>
**Tool and exact scope:** <tool plus permitted paths, records, commands, or destinations>
**Expected output / saved state:** <artifact or observable state>
**Acceptance evidence:** <observed output or inspected state and expected result at this milestone; independent evidence need not require another reviewer>
**On failure / escalation:** <proportionate handling under actual authority/limits; stop unchanged failures, retry only with a new hypothesis or materially changed evidence; recovery where needed>

<Order required steps toward the first integrated result before optional expansion. Continue required follow-on checks after success. Use waits/job tracking only if the harness actually needs async or side-effecting execution. Omit empty ceremony.>

## 6. Global acceptance checks

- [ ] The objective-level observable result is present and correct.
- [ ] Required compatibility, source, schema, output, and non-goal checks pass.
- [ ] Affected regressions and unauthorized-change inspection pass; all applicable user/project/AGENTS.md/CI-required milestone/final gates remain mandatory regardless of a narrower claim. Report unrelated pre-existing failures separately without silently fixing them.
- [ ] Every required artifact exists at its named location.
- [ ] Independently inspected final state matches the completion report.
- [ ] No required check is failed, omitted, or represented by an `incomplete` result.

## 7. Stop and escalation

**Stop for:** <material ambiguity, conflicting authority, out-of-scope work, unexpected sensitive data, destructive or unapproved external action, denial, warning affecting risk/authority, unchanged failure, or unrecoverable acceptance failure>
**Escalation recipient / evidence:** <recipient plus commands, outputs, current diff/state, failed checks, and exact missing decision or permission>
**Safe partial state to preserve:** <artifacts, logs, checkpoints, and recovery state>
**When blocked:** <only bounded authorized work removing the blocker or obtaining necessary evidence; no unrelated safe lane or unsafe smoke>
**Diagnostic versus denial:** <ordinary non-denial read-only error at unchanged scope/risk does not invalidate a still-applicable grant; denial or materially changed risk/authority stops the affected action>

## 8. Continuation / completion report

**Capability demonstrated:** <usable entry point, or missing concrete executor/components; distinguish offline/component progress and source-only evidence>
**Next action / blocker and authority:** <next required action under the current grant, concrete blocker, or none if acceptance passed; no permission inferred from a plan/handoff/peer>
**Completed step IDs / artifacts:** <IDs and exact links or paths>
**Checks and exact results:** <commands or inspections, pass/fail results, and independent evidence>
**Deviations / assumptions / failed checks:** <all limitations, including tool failures and unrun checks>
**Approvals / remaining risks:** <specific approvals and unresolved risks>
<Do not require a successor plan, model-backed run, or experiment merely to accept source-only work.>
