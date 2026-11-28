# Optimizing Sol execution plans

**Research snapshot:** 2026-11-16
**Purpose:** Improve the whole execution configuration from representative evidence, not subjective prompt polishing.

Use only when optimization of a Sol-targeted plan is explicitly requested. Runs, research, and configuration changes require their own authority; source/static review does not authorize evaluations or an active-session model/variant switch. Preserve the actual operation budgets and counting units, approval gates, and language/project checks in both baseline and candidate.

Except for the explicitly labeled platform note and linked OpenAI guidance, this document contains **planning recommendations**, not documented guarantees. Optimize the plan together with higher-priority instructions, source context, tools, permissions, harness, model, reasoning mode/effort, and output budget. A longer plan can perform worse when it adds contradictions, irrelevant context, or unnecessary work.

## Controlled optimization loop

### 1. Version the configuration

Record the plan version, exact model snapshot where available, reasoning mode and effort, output budget, prompts/instructions, source bundle, tool schemas, permissions, and relevant harness versions. Pin production snapshots where available. Preserve enough information to reproduce baseline and candidate conditions without storing secrets or hidden chain-of-thought.

### 2. Build a representative task set

Cover normal cases, boundary conditions, missing inputs, conflicting inputs, realistic long-context cases, tool failures, and relevant adversarial or untrusted content. Include cases that exercise approval, stop, recovery, and reporting rules rather than measuring only happy-path answers.

OpenAI's [accuracy-optimization guide](https://developers.openai.com/api/docs/guides/optimizing-llm-accuracy#evaluation) suggests 20+ questions with ground-truth answers as a starting heuristic before sophisticated optimization. Treat 20 as a starting point, not a universal sample-size guarantee. Keep regression cases out of prompt examples so improvement is not memorization.

### 3. Establish independent acceptance criteria first

Define expected artifacts, observable state, correctness and completeness requirements, forbidden side effects, and required checks before comparing candidates. Preserve ground truth or independently checkable conditions where possible. Use deterministic checks whenever available; calibrate human or model graders for subjective properties.

### 4. Repeat baseline and candidate runs

Run each task more than once under equivalent conditions, with the same repetition policy for baseline and candidate. Keep tools, permissions, source versions, budgets, and unrelated settings equivalent except for the variable under test. Do not treat a small difference from one run as an improvement.

### 5. Inspect outcomes and traces

Inspect final artifacts, independently observed system state, tool calls and errors, timing, and execution traces. Compare completion reports with actual state. Do not rely on a success claim or require hidden chain-of-thought. OpenAI recommends trace inspection while debugging and repeatable evaluations for comparisons; see [Evaluate agent workflows](https://developers.openai.com/api/docs/guides/agent-evals), [trace grading](https://developers.openai.com/api/docs/guides/trace-grading), and [evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices).

### 6. Diagnose the failing layer

Classify the problem before rewriting: objective, context, tools, orchestration, permissions, verification, reporting, effort, or cost controls. Distinguish **missing context** from **inconsistent behavior**. Additional examples may improve inconsistent behavior but cannot supply private or current facts; additional retrieval can add noise to an already well-specified task.

### 7. Change one meaningful variable per candidate

Select a recurring, costly failure and write a specific critique and desired observable behavior. Form a testable hypothesis such as “these tool schemas are confusable,” not “the prompt needs to be better.” Change one meaningful variable: objective wording, source bundle, tool schema, step boundary, acceptance check, permission gate, model, reasoning mode/effort, or output budget. Annotate representative good and bad results where that clarifies the hypothesis.

### 8. Promote only measured improvements

Compare baseline and candidate on the same tasks, including the existing regression set. Inspect traces as well as final answers. Promote only candidates that meet quality and safety requirements with acceptable total cost, latency, and human repair burden. Otherwise revert and record the result.

A pass-rate increase that doubles repair time or introduces an approval violation is not an optimization. A shorter prompt is not necessarily cheaper if it increases reasoning, retries, or tool calls. Compare **cost per accepted outcome**, not prompt size or benchmark score alone.

### 9. Grow the regression set

Add newly discovered production failures to the representative set with expected evidence and severity. Repeat the loop from the newly established baseline. Preserve rejected candidates and their measurements so a later change does not repeatedly re-test the same hypothesis.

## Measurement contract

Measure at least the following dimensions for baseline and every candidate:

| Dimension | Required measurements |
|---|---|
| Outcome | Acceptance pass rate; correctness; completeness; regressions |
| Control | Scope and permission violations; wrong tools or arguments; approval and stop-rule compliance |
| Recovery | Retry counts; repeated identical failures; `incomplete` runs; safe recovery without circumvention |
| Reporting | Completion claims contradicted by inspected state; omitted tool failures, unresolved checks, or failed required checks |
| Efficiency | Wall-clock latency; input, output, and reasoning tokens; cache reads and writes; total cost per accepted result |
| Human effort | Review and repair time; clarification and approval interruptions; avoidable escalations |

Report denominators, repetitions, failures, and confidence-limiting factors. Compare accepted outcomes rather than counting a fast failed run as efficient. Record human repair needed to make an artifact acceptable.

## Failure diagnosis

| Observed failure | Likely layer | Targeted change to test |
|---|---|---|
| Correct plan but wrong or stale facts | Context and retrieval | Supply authoritative current inputs, precedence, and freshness rules; remove irrelevant context |
| Missed deliverable or violated non-goal | Objective and constraints | State one observable objective, explicit non-goals, and a final requirement-to-artifact check |
| Wrong tool, arguments, or excessive searching | Tool contract | Clarify names, descriptions, schemas, and when not to call; expose fewer stage-relevant tools |
| Out-of-order steps or overwritten work | Dependencies and orchestration | Make dependencies explicit; serialize shared-state writes; isolate independent work |
| Same error retried repeatedly | Failure policy and harness limits | Classify transient and permanent failures; bound materially different retries; add a stop condition |
| Success claimed despite failed or missing checks | Verification and reporting | Require observed evidence, handle `incomplete`, and prohibit completion with failed or unrun required checks |
| Execution stops for trivial ambiguity | Assumption policy | Permit documented reversible in-scope assumptions; escalate only material ambiguity |
| Another route attempted after denial | Permission boundary | Stop the affected action; enforce denials outside the prompt; prohibit alternate-channel circumvention |
| Correct result but too slow or expensive | Scope, effort, and orchestration | Remove low-value work/context, reuse stable prefixes, lower effort/mode, or parallelize only independent work |
| Quality drops on long inputs | Context design | Retrieve focused evidence, split at meaningful milestones, and test at realistic context sizes |

Use the cheapest intervention that addresses the diagnosed cause, in this order where applicable:

1. Remove contradictions, duplicated rules, and ambiguous success conditions.
2. Fix missing, stale, or noisy sources.
3. Simplify tools, permissions, dependencies, and failure handling.
4. Strengthen independent acceptance checks and truthful reporting.
5. Remove low-value work and improve reuse or safe parallelism.
6. Compare model, standard/pro mode, and reasoning effort only afterward; retain the lightest reliable configuration.

For repetitive planning or status outputs, use schemas to reduce formatting variation and make checks machine-readable. For subjective quality, combine narrow automated graders with calibrated human judgment. OpenAI's [dataset guide](https://developers.openai.com/api/docs/guides/evaluation-getting-started) recommends detailed annotations and narrowly defined graders for properties that actually fail.

## Prompt-optimizer platform note — 2026-11-16

The 2026-11-16 source snapshot records the legacy Evals platform and its dataset-backed [prompt optimizer](https://developers.openai.com/api/docs/guides/prompt-optimizer) as **deprecated**, with shutdown scheduled for **2026-11-30**; this is a dated claim, not fresh service verification. Verify the material current status through the [deprecations page](https://developers.openai.com/api/docs/deprecations) only under research authority before depending on it, or report the dependency unresolved. Generated revisions still require manual review and authorized evaluation because they can regress. The baseline–trace–diagnose–compare loop above is independent of that platform.
