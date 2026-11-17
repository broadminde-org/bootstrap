# Execution plan: <short name>

> Copy only fields that help. Keep trivial tasks proportionately small. This plan records intent; it does not grant permissions or authorize commits, pushes, deployments, or other side effects.

**Plan ID / version:** <stable identifier and version>
**Owner / date:** <accountable person, ISO date>
**Executor:** <ChatGPT Work | Codex surface | API agent>
**Target model:** <gpt-6-sol | gpt-6.1-sol>
**Reasoning settings:** <valid effort; standard/pro mode where applicable>
**Budget / deadline:** <tokens, cost, time, run limit, or not applicable>

## 1. Objective

**Single observable outcome:** <resulting state, not an activity>
**Intended recipient / artifacts:** <user and exact artifact paths, records, or outputs>
**Non-goals:** <explicitly excluded work and side effects>

## 2. Authoritative inputs and current state

**Sources:** <path, URL, or record with version/date>
**Current state / reproduction:** <observed baseline and exact reproduction where applicable>
**Source precedence:** <order used to resolve conflicts>
**Allowed assumptions:** <only documented, reversible, in-scope assumptions>

## 3. Constraints

**Compatibility / output requirements:** <schemas, interfaces, formats, platforms>
**Must remain unchanged:** <behavior, data, files, or public contracts>
**Forbidden approaches:** <specific disallowed implementations or actions>
**Scope / budget limits:** <meaningful limits not already stated above>

## 4. Tools, permissions, and recovery

**Allowed reads:** <exact sources>
**Allowed writes:** <exact paths or records>
**Allowed network destinations:** <exact destinations or none>
**Credentials / sensitive-data boundary:** <permitted scope, prohibited discovery/disclosure>
**Required human or configured reviews:** <actions that stop at an approval gate>
**Forbidden actions:** <including indirect retries, denial workarounds, wider permissions, and fabricated results>
**Delegation / parallelism rule:** <independent work only, concurrency limit, shared-state isolation>
**Rollback / recovery:** <specific method for every side effect; steering/cancellation is not rollback>

## 5. Ordered steps

### Step <ID> — <short action>

**Depends on:** <step IDs or none>
**Action:** <one concrete operation>
**Tool and exact scope:** <tool plus permitted paths, records, commands, or destinations>
**Expected output / saved state:** <artifact or observable state>
**Acceptance evidence:** <independent check and exact expected result>
**On failure / escalation:** <bounded retry, recovery, stop condition, and recipient>

<Repeat for each required step. Omit empty ceremony for a trivial plan.>

## 6. Global acceptance checks

- [ ] The objective-level observable result is present and correct.
- [ ] Required compatibility, source, schema, output, and non-goal checks pass.
- [ ] Regression and unrelated-state checks pass.
- [ ] Every required artifact exists at its named location.
- [ ] Independently inspected final state matches the completion report.
- [ ] No required check is failed, omitted, or represented by an `incomplete` result.

## 7. Stop and escalation

**Stop for:** <material ambiguity, conflicting authority, out-of-scope work, unexpected sensitive data, destructive or unapproved external action, denial/warning, repeated failure, or unrecoverable acceptance failure>
**Escalation recipient / evidence:** <recipient plus commands, outputs, current diff/state, failed checks, and exact missing decision or permission>
**Safe partial state to preserve:** <artifacts, logs, checkpoints, and recovery state>

## 8. Completion report

**Completed step IDs / artifacts:** <IDs and exact links or paths>
**Checks and exact results:** <commands or inspections, pass/fail results, and independent evidence>
**Deviations / assumptions / failed checks:** <all limitations, including tool failures and unrun checks>
**Approvals / remaining risks:** <specific approvals and unresolved risks>
**Next action:** <next safe action, or “none—acceptance checks passed”>
