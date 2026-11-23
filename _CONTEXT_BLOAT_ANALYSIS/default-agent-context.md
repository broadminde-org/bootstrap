# Default Agent Context Analysis

Date: 2026-11-22
Workspace: `/home/luke/netbird_pfs`

## Bottom Line

A fresh root-workspace agent starts with approximately **7,000 tokens of
file-backed instructions**, before accounting for Kilo's built-in prompt, tool
definitions, skills catalog, or the user's request.

Including those platform layers, **roughly 20,000-35,000 tokens is a reasonable
budgeting estimate for a fresh session like the analyzed session**. That total
is not an exact tokenizer measurement; the file sizes below are measured.

## Automatically Loaded

These sources were present in the agent's initial instructions, before any tool
calls:

| Source | Lines | Characters | Approx. Tokens |
|---|---:|---:|---:|
| Root `AGENTS.md` | 305 | 23,416 | 5,850 |
| Global `config-hygiene.md` | 11 | 907 | 225 |
| Global `execution-focus.md` | 9 | 2,040 | 510 |
| Global `image-build.md` | 6 | 331 | 85 |
| Global `session-economy.md` | 10 | 551 | 140 |
| Global `workspace-temp.md` | 10 | 1,066 | 265 |
| **File-Backed Total** | **351** | **28,311** | **7,075** |

Token estimates use approximately four characters per token. Technical paths
and identifiers can increase the actual count.

The global rules are unconditionally included through
`/home/luke/.config/kilo/kilo.jsonc:3`:

```json
"instructions": ["~/.config/kilo/rules/*.md"]
```

A rule's `Scope` heading guides its applicability; it does **not** prevent its
text from loading.

Additional default context includes:

- Kilo's engineering, behavior, safety, environment, and coordination instructions.
- **30 skill catalog entries**, including descriptions and locations. Their complete skill bodies are not loaded initially.
- Built-in tool definitions and JSON argument schemas.
- **22 Playwright tools and four Svelte tools** exposed in the analyzed session, despite this being a Go/pfSense workspace.
- The user's request and editor metadata, including open-tab paths.

## Conditional Context

These sources are not all loaded at root-session startup:

| Source | Loading Behavior | Approx. Additional Tokens |
|---|---|---:|
| `ansible/AGENTS.md` | Directory-scoped instructions; accessing that subtree triggered its injection during this analysis | 3,450 |
| `netbird-docker/AGENTS.md` | Instructions for that subtree/session scope | 1,150 |
| Full skill bodies | Loaded when the agent invokes `skill` | Varies |
| Custom agent prompts | Relevant selected agent's prompt, not all agent bodies combined | Varies |
| Plans, docs, source, logs | Explicit reads, references, or command expansion | Varies |

There are eight global custom agents, all marked `mode: primary`. Their files
total approximately **5,740 tokens**, but that is **not** a default combined
context charge.

The open tabs `FIX_THIS_SHIT.md` and
`.kilo/plans/corvid-inline-release-completion.md` supplied their **paths**, not
their contents. Likewise, mentioning a plan inside `AGENTS.md` does not
automatically include the referenced document.

Internal Task subagents start with fresh context rather than the parent's full
transcript. They still have applicable instructions, their agent/tool setup,
and the delegated prompt; their exact baseline need not match the main agent.

## Largest Contributors

1. **The root `AGENTS.md` dominates editable default context.** It accounts for approximately **83% of the file-backed instruction characters**.
2. **Historical qualification detail is loaded for every task.** `AGENTS.md:114-245` alone occupies 132 lines, about 43% of the file. It includes dated attempts, evidence paths, hashes, and retained-helper status.
3. **Unrelated MCP tools add platform overhead.** The globally configured Playwright and Svelte servers expose tool schemas even when neither is relevant.
4. **The skills catalog adds several thousand tokens**, although progressive loading already avoids including every skill body.

The root file also mixes broad permission at `AGENTS.md:298` with detailed
operation-specific authorization limits earlier in the file. That adds
interpretation burden beyond the token cost.

## Reduction Priorities

- Keep project identity, essential commands, secret boundaries, platform restrictions, and current publication/live-operation holds in root `AGENTS.md`.
- Move detailed historical diagnostics and qualification procedures behind explicit links, preserving a short mandatory instruction to read the relevant contract before those operations.
- Scope Playwright/Svelte MCP availability to workspaces that need them.
- Shorten skill descriptions where their trigger conditions can remain clear.

A **roughly 50-65% reduction in root-file context** looks feasible without
removing essential boundaries. That would save approximately **3,000-4,000
tokens per fresh root agent**; MCP savings would be additional.

## Evidence and Limits

File sizes were measured with `wc -l -w -m`. Initial prompt contents provided
direct evidence of the root instructions, global rules, skills catalog, and
exposed tools. Reading under `ansible/` produced an additional directory-scoped
instruction message.

No ancestor `AGENTS.md`, `CLAUDE.md`, or `CONTEXT.md` files were found at the
checked ancestor locations. `KILO_CONFIG`, `KILO_CONFIG_DIR`,
`KILO_CONFIG_CONTENT`, and `KILO_DISABLE_PROJECT_CONFIG` were unset in the
inspected shell environment. This does not independently prove the environment
of every other agent process or client.

The overall token range is a budgeting estimate, not a captured raw API request
or provider usage measurement. Existing-session history, loaded skills, tool
results, directory instructions, and delegated prompts add further context.

The analysis made no changes to agent instructions or configuration. This
report file was subsequently created at the user's request.
