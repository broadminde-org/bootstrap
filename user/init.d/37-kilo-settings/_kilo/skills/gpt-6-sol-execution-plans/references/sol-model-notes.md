# GPT-6 Sol and GPT-6.1 Sol model notes

**Research snapshot:** 2026-11-16
**Evidence boundary:** OpenAI first-party documentation and launch/safety publications.
**Use:** Resolve model- or surface-specific decisions when writing an execution plan; do not treat this snapshot as permanently current.

Sections labeled **Documented facts** report the reviewed sources. Sections labeled **Planning recommendations** are derived guidance, not guarantees of model behavior. Recheck linked current documentation before relying on volatile specifications, availability, compatibility, limits, or prices.

## 1. Model and reasoning specifications

### Documented facts — volatile, checked 2026-11-16

The primary references are the [GPT-6 Sol model page](https://developers.openai.com/api/docs/models/gpt-6-sol), [GPT-6.1 Sol model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol), and [reasoning guide](https://developers.openai.com/api/docs/guides/reasoning).

| Setting | GPT-6 Sol | GPT-6.1 Sol |
|---|---|---|
| Exact API model ID | `gpt-6-sol` | `gpt-6.1-sol` |
| Default `reasoning.effort` | `medium` | `medium` |
| Supported efforts | `none`, `low`, `medium`, `high`, `xhigh`, `max` | `low`, `medium`, `high`, `xhigh`, `max` |
| Unsupported effort values | `minimal` is not listed | `none` and `minimal` are unsupported; use `low` |
| Tool-calling transport | Responses for built-in tools and function calling; Chat Completions function calling only with `reasoning_effort: "none"` | Responses required for tool calling |
| API context / maximum input / maximum output | 1,050,000 / 922,000 / 128,000 tokens | 1,050,000 / 922,000 / 128,000 tokens |
| Persisted reasoning | `all_turns` is not documented for this model on the reviewed reasoning page | `reasoning.context: "all_turns"` is supported for compatible earlier reasoning |
| Responses Multi-agent | Not listed as supported | Supported as a beta |

**`off` is not a documented reasoning-effort literal for either model.** Do not silently translate `off` into `none` or `low`; reject or correct the configuration explicitly. Use `reasoning.effort` in Responses and `reasoning_effort` in Chat Completions. Chat Completions endpoint support does not imply function-calling support at every effort.

The reasoning guide documents `reasoning.mode: "standard"` (default) and `"pro"` for GPT-6 models. Pro performs more model work and increases token use and cost. **Mode and effort are independent settings.** The documented effort ladder assigns `low` to efficient tool use and multi-step decisions, `medium` to planning and agentic work, `high` to harder reasoning and debugging, and `xhigh`/`max` to work whose evaluations justify their latency and cost.

Reasoning tokens occupy context and are billed as output tokens; raw reasoning is not exposed. `max_output_tokens` covers generated reasoning, visible output, and non-visible formatting tokens. Exhausting it can return `incomplete` with no visible text. OpenAI recommends initially reserving at least 25,000 tokens for reasoning and output.

### Planning recommendations

Default new substantial Sol execution plans to GPT-6.1 Sol at `medium`, standard mode, unless a measured constraint favors GPT-6 Sol, such as an existing validated workflow or a deliberate need for `none`. Start with standard mode; evaluate pro separately only if the chosen effort fails the acceptance bar. Adjust the initial 25,000-token reserve from observed workloads. Treat every `incomplete` response as unfinished work, never a completed step. Retain the lightest effort/mode that repeatedly passes representative checks.

## 2. Tool execution, asynchronous work, and stopping

### Documented facts

In the [function-calling flow](https://developers.openai.com/api/docs/guides/function-calling), the model emits a tool call, the **application executes it**, and the application returns the result with the original `call_id`. Continuing tool-driven work must preserve returned output and reasoning items. Plans record intended capabilities and reference actual authority; current user grants, runtime permissions, and the instruction hierarchy govern execution. A plan cannot grant permission.

The [GPT-6 guide](https://developers.openai.com/api/docs/guides/latest-model) and linked tool guides add these constraints:

- [Async tool calling](https://developers.openai.com/api/docs/guides/async-tool-calling) uses `async: true` for application-run function/custom tools, not hosted built-in tools. It neither transfers execution to OpenAI nor manages background jobs. The compatibility statement is “GPT-6 Astra and later models”; confirm the selected Sol model and harness before depending on it. Return the eventual result with its original `call_id`. Use an application-defined synchronous wait tool when later work depends on a pending result.
- [Mid-turn steering](https://developers.openai.com/api/docs/guides/steering) is available to the GPT-6 family over a Responses WebSocket connection. Steering does not rewrite emitted output, undo actions, or cancel tools already started. Required tool results and approvals must still be returned. Steering or cancellation is therefore **not rollback**.
- Both model pages list Responses support for tools including web search, file search, image generation, code interpreter, hosted shell, apply patch, skills, computer use, MCP, and tool search. Actual availability depends on product, organization, harness, and permissions.

### Planning recommendations

Use job tracking/dependent waits only in harnesses that actually need asynchronous or side-effecting execution, and recovery appropriate to real side effects. Stop unchanged failures; retry only authorized, materially justified attempts with a new hypothesis or changed evidence under actual operation limits. Do not invent deadlines, attempt ceilings, or one-milestone sessions. Idempotency is not authorization. Keep tool definitions stable and expose stage-appropriate tools with `allowed_tools`; use strict schemas, serialize shared/dependent work, and put approval interruptions at the side-effecting tool.

An ordinary non-denial read-only diagnostic error does not consume an otherwise applicable grant at unchanged scope/risk. Denial, unexpected sensitive state/data, changed scope/risk, or a warning affecting authority/safety requires reassessment, not a tool workaround.

When software consumes plans or reports, consider [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) with JSON Schema. Still handle refusals and `incomplete`, and independently validate semantics, authorization, and business rules: schema compliance does not prove execution succeeded. See [Guardrails and human review](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals).

## 3. Context, history, and resumable state

### Documented facts

For GPT-6.1 Sol, `reasoning.context: "all_turns"` can make compatible earlier reasoning available again. The request must contain earlier response items through `previous_response_id`, a conversation, or a complete manual replay. Inspect the response's effective `reasoning.context`; requesting the option neither creates missing reasoning nor exposes raw chain-of-thought. Incompatible reasoning is omitted when switching model families. See [Preserve reasoning across calls](https://developers.openai.com/api/docs/guides/reasoning#preserve-reasoning-across-calls).

For both models, preserving earlier API request prefixes/history is safest for cache and reasoning continuity. Changing earlier instructions, history, tools, or tool outputs can break cache prefixes and cause newer frontier models to drop subsequent reasoning items; see [Keep the prefix unchanged](https://developers.openai.com/api/docs/guides/preserved-reasoning). This API-history guidance does not require an append-only operational plan. `previous_response_id` does **not** carry forward top-level `instructions`; resend stable instructions on every request, as described in the [Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses).

[Compaction](https://developers.openai.com/api/docs/guides/compaction) can preserve opaque state for long runs but changes cache prefixes and has feature-compatibility limits, including [Multi-agent limitations](https://developers.openai.com/api/docs/guides/responses-multi-agent#limitations) and [configuration-update limitations](https://developers.openai.com/api/docs/guides/reasoning#change-reasoning-mid-conversation).

### Planning recommendations

Place stable API instructions/references before dynamic operational state and preserve tool ordering where applicable; API history/cache continuity and replaceable plan documents are distinct. Do not change the active Kilo model or reasoning settings mid-session; API configuration-update support does not authorize such a change.

## 4. API context versus ChatGPT Work and Codex

### Documented facts — volatile, checked 2026-11-16

The launch posts [GPT-6 Sol and Luna](https://openai.com/index/introducing-gpt-6-sol-and-luna/) and [GPT-6.1 Sol](https://openai.com/index/introducing-gpt-6-1-sol/) announced ChatGPT Work and Codex availability; launch statements do not guarantee current workspace availability. The [current ChatGPT/Codex model guide](https://developers.openai.com/codex/models) says available options and defaults vary by plan, client, workspace settings, and rollout.

GPT-6.1 Sol has a **default 500,000-token context window in Codex and ChatGPT Work**, distinct from its 1,050,000-token API window. The reviewed product documentation did not provide an equivalent current default product-window figure for GPT-6 Sol. Do not infer subscription context, usage limits, or credit consumption from API specifications.

Codex reads `AGENTS.md` with nearer files taking precedence; see [Custom instructions](https://developers.openai.com/codex/agent-configuration/agents-md). [Permission modes](https://developers.openai.com/codex/permission-modes) combine sandbox and approval policy. “Approve for me” changes review responsibility, not sandbox authority. [Auto-review](https://developers.openai.com/codex/sandboxing/auto-review) is not a deterministic security guarantee. [Long-running work](https://developers.openai.com/codex/long-running-work) recommends clear outcomes, constraints, and verification in the same chat; starting a goal does not broaden access.

### Planning recommendations

Confirm the actual model picker, client, workspace, and harness instead of assuming API features exist in a product surface. Audit loaded instructions and skills for conflicts. Enforce network, write, credential, and approval boundaries in the runtime. Keep parallel chats or agents from writing to the same connected source; isolate coding work where necessary.

Order integration around the first real usable slice and minimum safety prerequisites; new interfaces need the production implementation/caller required by the task. Separate required core/final checks from optional matrices and research. Name the blocker and next execution enabled before unplanned substantial support; ordinary required follow-on work needs no extra ceremony. Design-only tasks use their actual deliverable. Scale observed evidence to the milestone, retaining all applicable project-required acceptance gates; independent evidence need not mean a separate reviewer or model run.

## 5. Delegation and prompting limits

### Documented facts

The [Responses Multi-agent beta](https://developers.openai.com/api/docs/guides/responses-multi-agent) is documented for GPT-6.1 Sol. Each subagent needs a bounded task and maintains its own context. OpenAI recommends the default `max_concurrent_subagents` of 3 for most workloads; this limits concurrent agents, **not** their total number or context size. Every agent receives the request's tools, so delegation does not create least privilege. Multi-agent can increase token usage and is less suitable for strict dependencies, small tasks, shared mutable-state contention, or a required deterministic graph. ChatGPT/Codex **Ultra** is documented separately; do not assume it exposes the same controls or behavior.

The [current GPT-6 prompting guide](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices) says its autonomy, instruction-following, delegation, and verification suggestions address behavior observed with **GPT-6 Astra** and require evaluation on the selected model and workload. It does not establish identical Sol behavior. The [GPT-6.1 Sol safety addendum](https://deploymentsafety.openai.com/gpt-6-1-sol) reports unwanted persistence in deliberately challenging warning evaluations without system controls; these are not production failure rates.

### Planning recommendations

Delegate only concrete independent work, limit concurrency, and isolate mutable state. Require external evidence and enforce permissions outside prompts. Test prompting patterns on Sol rather than claiming guaranteed autonomy, persistence, questioning, delegation, or testing behavior.

## 6. Caching, long context, and cost

### Documented facts — volatile, checked 2026-11-16

[Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) is enabled by default for supported models, but writes are billed and hits are not guaranteed. For these Sol models, prefixes become cacheable at 1,024 visible input tokens. The default minimum lifetime is 30 minutes at 1.25× uncached input rate; an optional 12-hour minimum is listed at 2.5×. Cached reads cost 0.1× input for GPT-6 Sol and 0.05× for GPT-6.1 Sol.

For Standard API processing, both models list $2 per 1M input tokens and $10 per 1M output tokens. Cached input is $0.20 per 1M for GPT-6 Sol and $0.10 per 1M for GPT-6.1 Sol; cache writes are $2.50 per 1M for both. API prompts with **more than 272K input tokens** charge the full request at **2× input and cache rates and 1.5× output rates**. OpenAI states that GPT-6.1 Sol usage drawn from a Codex/ChatGPT Work subscription has no long-context surcharge; that does not change API pricing.

To prevent dynamic suffixes from being written to cache, set `prompt_cache_options.mode: "explicit"` and place explicit breakpoints only after stable content. Adding a breakpoint in implicit mode does not suppress the implicit breakpoint at the latest eligible message.

### Planning recommendations

Reuse genuinely stable prefixes and append new turns; do not pad short prompts to reach cache minimums. Track cached/read/write tokens, latency, quality, and total cost. Test accuracy at realistic context sizes rather than treating the advertised window as a reliability guarantee. Near the 272K boundary, compare milestone/compaction designs with one large request instead of assuming either is cheaper or more accurate.

## 7. Migration checks

### Documented requirements and checks

The [GPT-6 migration quickstart](https://developers.openai.com/api/docs/guides/latest-model#migration-quickstart) requires or calls for these checks when moving from GPT-6 Sol to GPT-6.1 Sol:

1. Set `model` to `gpt-6.1-sol`.
2. Replace `reasoning.effort: "none"` with `low`; `none` and `minimal` are invalid for GPT-6.1 Sol.
3. Move Chat Completions requests that call functions to Responses.
4. Otherwise preserve supported effective effort and compare representative tasks at equal effort; start older `minimal` requests at `low`.
5. When effort is not `none`, remove `temperature`, `top_p`, and `top_logprobs`; for Chat Completions also remove `logprobs`, and for Responses remove `message.output_text.logprobs` from `include`.
6. When migrating cache configuration from GPT-5.5 or earlier, replace legacy `prompt_cache_retention` with `prompt_cache_options.ttl` (default `"30m"`).

### Planning recommendations

Do not assume effort levels or persisted reasoning transfer perfectly between generations. Carry forward readable plans, source artifacts, decisions, and verification results, then rerun acceptance checks. Use current official [model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection) and representative measurements before promoting a migration.
