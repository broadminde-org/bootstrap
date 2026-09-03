# Context Set Gap Analysis — Recommendations

Date: 2026-09-02
Scope: Cross-reference of salvaged opencode context set (`_salvage/opencode/`) against the
deployed Kilo global context set (`init.d/37-kilo-settings/` → `~/.config/kilo/`, `~/.kilo/`),
plus 2026 context-engineering research. Generic only — nothing project-specific.

Recommendation #1 (fix broken references: `/standards` command, `package-version-lookup`
reference in `/audit`) was executed separately and is not covered here.

---

## R2 — Restore `package-version-lookup` as a skill (HIGH)

**Gap:** LLM knowledge cutoffs make models pin stale or confabulated dependency versions —
a problem that worsens as models age between releases. The salvaged skill had copy-paste
live registry recipes for 9 ecosystems (PyPI, npm, Go proxy, RubyGems, crates, Debian,
Alpine, DockerHub, GHCR) and a hard rule: never pin from memory.

**Why a skill, not a rule:** It is needed only when touching dependencies. A `SKILL.md`
loads on demand at zero always-on context cost. The salvaged file
(`_salvage/opencode/skills/package-version-lookup/SKILL.md`) is already skill-shaped and
generic — restoring it is close to a copy operation.

**Also restores:** the dependency half of `/audit`, whose "latest version" check is
currently instruction-only.

## R3 — Restore `debug-with-logs` as a skill (HIGH)

**Gap:** Nothing in the current set enforces evidence-first debugging. A top LLM failure
mode is proposing fixes without reading actual output (MAST taxonomy, UC Berkeley 2025:
absent/incomplete verification is among the dominant agent failure modes). The salvaged
skill mandated: locate real logs first, filter ERROR/WARN/stack-trace before widening,
report log lines before proposing fixes, confirm health after the fix.

**Current partial coverage:** `code-skeptic` demands proof *after* the fact, but nothing
guides the agent *doing* the debugging. These are complementary, not redundant.

**Form:** skill (on-demand), same reasoning as R2. Salvaged source is generic.

## R4 — Add a short `config-hygiene` rule (MEDIUM)

**Gap:** The salvaged `rules/no-hardcoding.md` covered: runtime config via env vars,
`.env.example` tracked / `.env` never committed, template files as source of truth,
no hardcoded domains/ports/URLs/credentials. Only "never stage `.env`" survives today
(in the `/commit` command).

**Form:** always-on rule, ~6 lines, modeled on `workspace-temp.md`. Rules are cheap only
when few and short — this one qualifies. Alternatively fold into `workspace-temp.md` as
a second section to keep the rules/ directory at one file.

**Note:** the live `~/.config/kilo/rules/` directory does not currently exist — the
`instructions` glob in kilo.jsonc matches nothing until a rule file is deployed. Any new
rule must actually be synced to take effect.

## R5 — Resolve the mcp-server/standards apparatus in `run.sh` (MEDIUM)

**Gap:** `run.sh` step 5 and its header comments still describe deploying and starting the
host-standards MCP server (`~/.config/kilo/mcp-server/`, port 8766, standards volume
mount). The skeleton has no `mcp-server/` directory, so the step silently skips — but the
comments promise infrastructure that does not exist.

**Fix options (pick one):**
- Remove step 5 and the related header/summary lines from `run.sh` (simplest; the
  standards MCP was retired with the opencode set), or
- Restore `mcp-server/` and a `standards/` directory if the standards-search capability
  is actually wanted back.

**Recommendation:** remove. The standards library was part of the context-creep problem;
its content that still matters (version pinning, log debugging) returns via R2/R3 as
skills, which is the cheaper delivery mechanism.

## R6 — Do NOT restore the rest (validated by research)

The purge was directionally correct. Keep these out:

- `communication-style`, `tool-usage` rules — now baked into Kilo's system prompt.
- `modular-design` rule — covered better by `ponytail` + `code-simplifier`.
- `*-shared-first` skills (go/python/docker/shell) — repo-topology-dependent; the generic
  Python core was folded into the `python` skill.
- `codemap-discovery`, `analysis-tasks`, `docs-quality`, `completeness-verification`,
  `codebase-inventory` — absorbed by the `mapper` agent.
- `context-gathering`, `option-generation`, `decision-records` — absorbed by the
  `architect` agent's interview/decision discipline.
- `mcp-tools.md`, `lifecycle-management.md`, `shell-environment.md`, `mermaid-standards.md`,
  python standards quartet — absorbed (init-d skill, mermaid skill, python skill) or
  obsolete.
- `agent-tuner` — depended on session-export tooling that no longer exists.

**Research support:**
- ETH Zürich (arXiv 2602.11988): LLM-generated context files reduce task success and add
  20–23% inference cost; even human-curated files add up to 19% cost for ~4pp gain.
  Small, human-written, always-on rules + on-demand skills is the validated architecture —
  which is what the current set already implements.
- Instructions land best in the first/last 20% of context; favors few short rule files.
- Progressive disclosure works, but *discovery* is the failure mode — a removed skill
  cannot be discovered at all. That is the actual cost of R2/R3 being absent: not bloat
  avoided, but capability unreachable.

---

## Summary table

| # | Recommendation | Priority | Effort | Form |
|---|----------------|----------|--------|------|
| 2 | Restore `package-version-lookup` | High | Copy + trim | Skill |
| 3 | Restore `debug-with-logs` | High | Copy + trim | Skill |
| 4 | Add `config-hygiene` rule | Medium | ~6 lines | Rule (always-on) |
| 5 | Remove mcp-server step from `run.sh` | Medium | Delete a block | Script edit |
| 6 | Keep everything else purged | — | None | — |

**Ordering:** R2 and R3 are independent and can be done together. R4 is trivial. R5 is
cleanup that prevents the run.sh comments from lying about the environment.
