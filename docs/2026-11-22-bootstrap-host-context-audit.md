# Bootstrap Host Context Audit

Audit date: 2026-11-22 UTC. Source of truth:
`.kilo/plans/bootstrap-host-context-audit.md`. This is a read-only audit result,
not implementation, provisioning, cleanup, publication, or permission approval.

## Executive Recommendation

Keep a small universal safety/execution core, task-specific skill entry points,
and precise references. Fix ownership and contradictory instructions before
optimizing prompt size. Do not add another policy bundle or delete safeguards
because the model supposedly knows them.

The five global rules total **4,895 characters**, about **1,224 estimated tokens**.
The more material correctness risks are unsafe reverse synchronization, retained
optional context, instruction conflicts, and client behavior that differs from
its documentation. Browser/Svelte schemas are exposed in this non-frontend
session, but their exact token cost was not measured.

First future change: replace the raw live-config diff in
`user/init.d/37-kilo-settings/run.sh:156-163` with value-free structural reporting,
and prevent unscreened live JSON import at `user/sync-kilo-context.sh:108-116`.
Preserve unrelated local configuration and permission enforcement. Implement and
exercise this separately, not by running either script during this audit.

| Order | Future Change And Owner | Correctness / Savings / Rollout Risk |
|---|---|---|
| 1 | Bootstrap: remove raw-config output/import; make reverse-sync ownership, manifest handling, and retirement explicit | High safety benefit; negligible prompt saving; medium migration risk |
| 2 | Bootstrap/client owners: qualify named MCP-tool denial for restricted roles; reconcile Svelte/Go-access drift, canonical resources and safety-weakening entries | High safety/correctness benefit; mainly conditional savings; medium risk |
| 3 | Bootstrap plus external skill owners: one frontend design identity, accessibility precedence, one version-aware Svelte workflow; repair missing dependencies | Medium correctness benefit; conditional body/catalog savings; medium risk |
| 4 | Bootstrap/client integration: task-scoped MCP availability and supported skill selection, with explicit handling of retained optional copies | Startup savings plausible but unmeasured; higher rollout risk until both clients are qualified |
| 5 | Bootstrap: shorten universal-policy repetition in rules, selected agents, and task skills; keep task-specific validation | Modest measured rule surface; potentially larger selected-body savings; low risk only after preservation checks |
| 6 | Source owners: retain patch/migration/history resources outside current entry instructions; retire only identified managed discovery entries | Prevents stale authority; do not delete evidence or external user extras |

## Baseline And Evidence Limits

- Bootstrap revision: `2e54f2826050b66358d837da5765bd866170e3f8`.
  Collection began at `2026-11-22T23:20:29Z`. The initial tree had no tracked
  modifications and six untracked status entries; their private/local names and
  contents are not reproduced. Existing work was preserved.
- Read the four `_CONTEXT_BLOAT_ANALYSIS/` reports once as dated leads. Their
  copies match the originals byte-for-byte. No historical session census or
  campaign-plan replay was repeated.
- Corvid cleanup commit `2d7d2e1` exists. Its cleanup disposition and current
  root were checked: **6,999 characters**, SHA-256 prefix `9889771958cf`, versus
  the historical 23,416. The old 7,075-token file baseline is not current.
- Installed npm manifest identifies `@kilocode/cli` **7.8.17**. Version-tagged
  client source was reviewed, not executed or proven identical to the installed
  native binary. The launcher permits an override/cached/platform binary.
  Conventional local/remote VS Code extension roots were absent; the actual
  extension implementation and executing backend version remain unverified.
- Live JSON was inspected only through an allowlisted structural projection,
  redacted before output. No credentials, `.env`, private host config, raw live
  JSON, provider values, or configuration diffs were captured.
- Existing SQLite metadata was queried read-only for this audit session's
  numeric usage fields only. Counters exist, but do not isolate a fresh startup
  prompt or avoidable cost. No transcripts or historical usage cohort were read;
  private session identifiers/accounting are omitted here.
  Versioned normalization stores uncached input, non-reasoning output and separate
  cache/reasoning buckets; message tokens are assigned per completed step, not
  automatically cumulative session spend (`S/session/session.ts:420-464`,
  `S/session/processor.ts:669-723`). Historical records are not re-normalized on
  read, so current source semantics cannot be assumed for every historical row.
- One initial filename glob unintentionally searched home descendants rather
  than only discovery roots. No unrelated returned file contents were opened or
  included; subsequent existence checks used exact paths.

References below use `B37` = `user/init.d/37-kilo-settings`, `B30` =
`user/init.d/30-scripts`, `B60` = `user/init.d/60-caddy`, `B98` =
`user/init.d/98-npm-shared`, `B99` = `user/init.d/99-go-shared`.
`K/<name>` = `~/.kilo/skills/<name>`; `A/<name>` =
`~/.agents/skills/<name>`. Skill line references name `SKILL.md` unless another
file is stated. `S/` = `packages/opencode/src/`, `C/` = `packages/core/src/` in
[Kilo's v7.8.17 source](https://github.com/Kilo-Org/kilocode/tree/v7.8.17).

## Ownership And Synchronization

| Source Owner | Installed Item / Trigger | Forward Update / Retirement / Reverse Direction |
|---|---|---|
| B37 `_config/kilo/{agents,commands,rules}` | Eight agents, two commands, five rules; unconditional step | Preserve-sync replaces owned content, retains extras; reverse-sync replaces whole source directories |
| B37 `_config/kilo/kilo.json` | Global MCP template; create once | Existing differences require manual merge; reverse-sync blindly imports live JSON |
| B37 `_config/kilo/kilo.jsonc` | Global instructions/permissions; create once or narrow migration | Unrelated local settings retained; unsupported/conflicting structure refused; rollback covers this file only |
| B37 `.kilocodeignore` | Workspace ignore file; create once/manual merge | Current copy matches public template; discovery filtering, not an injected instruction body |
| B37 `_kilo/skills` plus manifests | Eight default and ten optional skills; optional selection through `KILO_OPTIONAL_SKILLS` | Unselected optionals are neither updated nor removed; reverse import does not update manifests |
| B30 `kilo/skills` | `air`, `image-build`; unconditional context install | Preserve-sync; canonical `templates/air.toml.template` subsequently replaces Air asset |
| B60 `kilo/skills` | `central-caddy`; requires `docker` and `caddy` | Preserve-sync; `docs/central-caddy.md` subsequently replaces bundled guide; disablement is not retirement |
| B98 `kilo/skills` | `frontend-shared-access`; requires `dev` | Installed before auth handling; preserve-sync, no capability-off retirement |
| B99 `kilo/skills` | `go-shared-access`; requires `dev` | Installed before deploy-key handling; preserve-sync, no capability-off retirement |
| External `.agents/skills` | Eight entries, seven noncolliding names | No bootstrap source owner established; do not import, overwrite, or delete as managed extras |
| Client builtin | `kilo-config` | Compiled into client; upstream/client-version owner, not a missing filesystem skill |
| Bootstrap repository | Root `AGENTS.md`, `.kilo/agents/context-technician.md`, project config | Repository-owned; selected agent is conditional, not a host-global default |
| Project legacy copy | `.kilocode/skills/skill-creator` | External producer unresolved; different Claude-oriented entry, shadowed by home skill of the same name |

Forward implementation: `user/init.d/lib/common.sh:43-116` overwrites differing
owned files, retains destination-only files, reports executable extras, and
rejects problematic symlinks. Ordinary extra Markdown is not reported.
`B37/run.sh:127-140` installs text and explicitly retires only
`rules/privilege-escalation.md` and `commands/standards.md`.

Migration: `B37/migrate-kilo-jsonc.sh:44-49,85,149-207` refuses symlinks,
nonregular paths, incompatible instruction/bash structure, ambiguous managed
keys, and non-deny managed values. It supports anchorless allowlists and retains
unrelated entries (`:209-239`); validation/rollback is at `:257-284`.
The entire step is not transactional: scratch/timer changes and text installation
precede migration; manifests are checked later (`B37/run.sh:67-109,127-178,210-274`).

Reverse implementation: `user/sync-kilo-context.sh:83-116,133-171` mirrors whole
directories, copies raw JSON, then routes five feature skill names. Missing
directories are skipped; missing live feature skills leave old feature-owned
source directories. Added/deleted B37 skills can violate manifests. Literal
privilege-string checks (`:70-77`) are not semantic permission validation.

### Comparison Inventory

Public deploy trees, excluding two JSON templates: **90 files / 555,928 bytes**,
comprising 15 agent/command/rule files, 23 skill entries and 52 resources.
Full-file SHA-256 comparison: **86 matched, two modified, two missing**.
No installed extras were found within those managed trees. External `.agents`
entries are a separate ownership class, not managed-tree extras.

| Tree | Files / Bytes | Comparison |
|---|---:|---|
| B37 `_config/kilo`, excluding JSON | 15 / 33,122 | All matched |
| B37 `_kilo` | 66 / 471,344 | Svelte writer entry modified; other counterparts matched |
| B30 `kilo` | 4 / 14,557 | Matched, including canonical Air asset |
| B60 `kilo` | 2 / 22,397 | Entry and guide absent; not advertised in this session |
| B98 `kilo` | 1 / 3,350 | Matched |
| B99 `kilo` | 2 / 11,158 | Go-access entry modified; reference matched |

Svelte source/live entry SHA-256 prefixes: `14b07b9f0e50` / `3f489ab8dfab`;
Go-access: `5fa8ae465f3b` / `c60f2fa3a03f`. Differences are substantive reference/
workflow changes, not grounds to choose the live copy automatically.
The bundled Caddy guide is 14,102 bytes (`327a35f1d90e`); canonical
`docs/central-caddy.md` is 20,731 (`f968b9229bc1`). Forward installation selects
the latter (`B60/run.sh:43-48`); reverse-sync edits to the former can be lost.

## What Loads

Runtime observations here: bootstrap root plus all five global rules were
supplied as instructions; the catalog advertised **30 names** (29 filesystem
names plus builtin); **22 Playwright and four Svelte schemas** were exposed.
This proves exposure in this session, not connection identity or healthy servers.

Redacted config structure: global `kilo.json` has MCP entries for Playwright and
Svelte with enablement unspecified; global `kilo.jsonc` has the sole instruction
glob `~/.config/kilo/rules/*.md`, permissions and indexing. No explicit skill
paths/URLs were present. Project `.kilo/kilo.jsonc` has schema/snapshot keys only.
Ancestor `/`, `/home`, and home had no `AGENTS.md`, `CLAUDE.md`, or `CONTEXT.md`;
home `.kilocode`, `.claude`, and `/etc/kilo` were absent.
Project `.kilocode` contains a separate skill-creator entry and 17 resources;
project `.agents`, `.claude`, root JSON configs, global AGENTS and legacy TOML
config were absent. This legacy project entry does not add an advertised name.
Exact legacy candidates were checked: editor global storage, home/CWD custom
modes, home/CWD workflows and rule roots/mode variants, project MCP JSON and
home ignore were absent. The CWD `.kilocodeignore` exists and matches its owner.
Shell `KILO_CONFIG`, `KILO_CONFIG_DIR`, `KILO_CONFIG_CONTENT`,
`KILO_DISABLE_PROJECT_CONFIG`, `KILO_DISABLE_EXTERNAL_SKILLS`, and
`XDG_CONFIG_HOME` were unset; `KILO_DISABLE_CLAUDE_CODE` was set, value withheld.
This is not proof of another client process's environment.
Additional shell override names: `KILO_PLATFORM`, `KILOCODE_FEATURE`, and
`KILO_EXPERIMENTAL_CLAUDE_MIGRATION` were set, values withheld;
`KILO_PERMISSION`, `KILO_BIN_PATH`, `KILO_DISABLE_CLAUDE_CODE_PROMPT` and
`KILO_DISABLE_CLAUDE_CODE_SKILLS` were unset. Presence does not establish a
flag's truth value, active platform, or executed migration.

| Layer | Trigger / Measured Size | Evidence / Confidence |
|---|---|---|
| Global rules | Always included by glob; 4,895 characters | Current prompt plus `S/session/instruction.ts:165-211`; high for this session |
| Bootstrap root | Applicable workspace; 14,690 characters | Current prompt; SHA prefix `abf7d307fabc`; high |
| Post-cleanup Corvid root | Corvid workspace only; 6,999 characters | Current file/disposition, not a fresh Corvid prompt capture |
| Skill catalog | Advertised name/description/location, not all bodies | `S/session/system.ts:153-164`, `S/skill/index.ts:396-410`; high observation, source-level mechanism |
| Skill bodies | Selected tool/skill-command body; 130,420 installed body characters across 30 entries, including one shadowed duplicate | `S/skill/index.ts:115-159,313-325`; `S/tool/skill.ts:31-113`; not a default prompt total |
| Custom agent bodies | Only selected prompt; global files 22,957 characters, bodies 20,356 | `S/config/agent.ts:31-90`; `S/session/llm/request.ts:70-95`; not eight prompts charged together |
| Project context technician | Selected agent only; file 9,656, body 8,994 characters | Repository file; not used as audit authority |
| Commands | Explicit expansion; global files 5,240, bodies 5,041 characters | `S/session/prompt.ts:2354-2456`; shell placeholders can execute |
| References/nested instructions | Explicit reads, attachment expansion, or scoped file reads | `S/session/instruction.ts:214-263`; a link alone does not load its target |
| MCP schemas/instructions | Enabled, connected discovery; schemas sent before invocation approval | `S/mcp/index.ts:486-514,606-644`; `S/session/tools.ts:473-503`; exact size unknown |
| Transcript replay | Retained messages/tool inputs/results, including loaded bodies | `S/session/message-v2.ts:326-465,546-555,663-719`; not new authored text |

Character/4 estimates are budgeting heuristics, not tokenizer measurements:
bootstrap file instructions total **19,585 characters**, approximately **4,896
tokens**; post-cleanup Corvid root plus unchanged global rules is **11,894**,
approximately **2,974 tokens**. Do not add all skill/agent/resource bytes to either.
Filesystem skill descriptions total **8,684 characters**, including the losing
duplicate; names, locations, wrappers and builtin metadata are additional.
No exact catalog/schema/system-prompt token total, invoice, or avoidable-cost
estimate is established. Cached replay is not necessarily avoidable cost.

### Versioned Discovery Rules

- Config merge order is legacy/organization modes, remote well-known, XDG global,
  explicit file, project root files, discovered directories, inline content,
  active-account organization, managed config. `KILO_PERMISSION` applies after
  managed config (`S/config/config.ts:578-601,689-800,825-1022`).
- Global filenames merge `config.json`, `kilo.json`, `kilo.jsonc`,
  `opencode.json`, `opencode.jsonc`. Instruction arrays accumulate with exact
  string deduplication (`S/config/config.ts:77-83,459-481`).
- Config directory order is XDG, primary-worktree fallback, active nearest-to-root
  ancestors (`.kilocode` then `.kilo` per level), home roots, explicit directory.
  Thus home definitions can override project ones; farther ancestors can override
  nearer config directories (`S/config/paths.ts:22-40`, `C/fs-util.ts:162-175`).
- Instruction filename classes are AGENTS, compatible CLAUDE, then CONTEXT; all
  ancestor matches of the first matching class load. File reads can attach scoped
  instructions (`S/session/instruction.ts:63-78,145-163,214-263`).
- Skills load builtin, external home/project `.claude`/`.agents`, config-root
  skills, explicit paths, then URLs. Last successfully parsed frontmatter name
  wins. The advertised `K/frontend-design` shadows `A/frontend-design`.
  Full bodies are parsed/cached at discovery, but only catalog metadata is
  initially injected (`S/skill/index.ts:144-159,220-325,396-410`).
- `disable-model-invocation` is not implemented by this skill parser. Skill-deny
  filters catalog/tool use, but explicit skill commands resolve through unfiltered
  names. Neither project-config nor external-skill disable switches alone provide
  complete isolation (`S/skill/index.ts:32-58,225-300,385-390`;
  `S/command/index.ts:173-175,215-222`).
- Permission evaluation is **last matching rule wins**, otherwise ask
  (`S/permission/index.ts:102-112,478-514`). Ask does not hide MCP schemas.
- Legacy migration also consumes editor global storage at
  `~/.config/Code/User/globalStorage/kilocode.kilo-code`, custom modes, workflows,
  mode-specific rules, project MCP JSON and ignore files. Exact paths were checked
  without dumping their contents (`S/kilocode/paths.ts:14-29`,
  `S/kilocode/{modes,workflows,mcp,ignore,rules}-migrator.ts`). Editor-storage MCP
  loading has a platform/daemon condition; project MCP files do not
  (`S/kilocode/config/config.ts:350-426`).
  `~/.config/kilocode` is not a content root in this chain;
  `~/.config/opencode` is only a leftover-directory notification.
- Project `mcp.<server>.enabled: false` can override an inherited server without
  changing permissions (`S/kilocode/config/config.ts:635-657`,
  `C/v1/config/config.ts:255-257`, `S/mcp/index.ts:629-632`).
  Higher-precedence config can re-enable it; a disk edit alone does not prove an
  existing connection was disconnected.
  A scalar `permission.mcp: deny` is different: reviewed tool calls ask against
  names such as `svelte_*`, not literal `mcp` (`S/session/tools.ts:502`).
- Config/MCP presence alone is not connection proof. Diagnostic client startup
  can create directories/config/gitignores, migrate permissions, resolve plugins,
  download skill caches, and start MCPs. No client diagnostics were launched
  (`C/global.ts:48-58`, `S/config/config.ts:379-391,430-568,894-897`).

## Severity-Ranked Findings

Severity describes the activated source-level risk, not an observed exploit,
credential leak, provisioning failure, or measured execution waste.

| Severity / Class | Evidence And Activation | Mechanism / Proposed Disposition |
|---|---|---|
| High / exposure, ownership | B37 `run.sh:156-163`; reverse-sync `:108-116`; provisioning/import with customized config | Raw diff can reveal values; raw import can put secrets in tracked templates. Emit value-free structure; explicit allowlisted/screened import, never wholesale live-config adoption |
| High / safety weakening | K/agent-md-refactor `:187-209`; instruction refactoring | Explicitly recommends deleting "Don't commit secrets" because the agent knows it. Correct advice; preserve safeguards or verify an authoritative replacement, never delete by line budget |
| High / conflicting validation | K/artifacts-builder `:19-24,76-80`; A/frontend-ui-engineering `:329-340`; interactive artifacts | Optional/delayed testing conflicts with mandatory UI finish gates. Preview is not acceptance; retain applicable rendered/accessibility/responsive/state checks |
| High / consequential defaults | K/neurodivergent-ux `:33-34`; forms/application interfaces | "Auto-save everything locally" includes sensitive/ephemeral inputs without exclusions. Preserve recovery usability, but require data classification and appropriate authorization |
| High / permission qualification gap | Global frontend-specialist `:19,28`, reviewer `:10`, architect `:13`, test-engineer `:22`; selected restricted roles under reviewed CLI | Scalar `permission.mcp: deny` does not match named MCP tool permission keys in the reviewed path; no conversion was located. Text restrictions remain binding, but are not demonstrated runtime enforcement. Qualify version-specific named-tool denial in an authorized isolated negative test; extension semantics unknown |
| Medium / hidden side effects | K/artifacts-builder `scripts/init-artifact.sh:33-43,272-277`, `bundle-artifact.sh:21,36`; artifact setup/bundling | Global package installation precedes argument validation; bundling adds dependencies and deletes outputs. Scope to explicit standalone-artifact authority; disclose effects and prefer existing tooling |
| Medium / retirement drift | B37 `run.sh:269-273`; reverse-sync `:83-105,133-171`; optional rollout/reverse import | All ten optionals remain installed; exclusion does not update or retire them. Reverse imports can resurrect retired files, fail manifests, or miss feature deletions. Introduce owned identity/hash-aware retirement and convergence tests |
| Medium / competing producer | B30 `run.sh:29-34`, B60 `run.sh:43-48`; skill-resource edits | Canonical producer overwrites bundled/reverse-synced resources. Name the real producer; generate/copy outward, not edit whichever duplicate is nearest |
| Medium / client stale authority | Builtin `S/kilocode/skills/kilo-config.md:125,192`; configuring permissions | First-match advice contradicts actual last-match evaluator and its own MCP section. Upstream/versioned correction; do not reorder or weaken live permissions based on stale prose |
| Medium / unsupported scoping | A/handoff, A/grill-with-docs, A/improve-codebase-architecture frontmatter; automatic catalog discovery | `disable-model-invocation: true` is ignored; live docs also claim metadata-only discovery/project priority unlike this source. Use supported controls and prove caller behavior before rollout |
| Medium / shadowed legacy authority | Project `.kilocode/skills/skill-creator/SKILL.md:169-219,236-244,369,438-441`; explicit legacy-entry reference or changed discovery order | Different Claude-specific eval workflow assumes unavailable notification fields, uses untracked backgrounding and OS temp. Keep as external history or explicitly port/scope it; never assume project copy is the selected skill |
| Medium / frontend precedence | K/frontend-design `:25-31,42-48`; K/neurodivergent-ux `:8-17,21-27,52-59`; application UI | Extreme motion/type directions conflict with low-stimulus/legible UX; marketing exclusion differs between description/body. One design identity; accessibility and existing systems take precedence |
| Medium / installed source drift | K/svelte-code-writer `:15-20,36,56,65`; B37 source `:15-30,53,72-89`; Svelte edits | Rune quoting is broken and live npx advice lacks source safeguards. Roll out reviewed source via owner; preserve authorized MCP/fallback, metadata lookup and revalidation |
| Medium / version assumptions | K/svelte-core-bestpractices `:164,168,182`, `references/await-expressions.md:135`; Svelte 5 work | New APIs treated as universally available. Gate by actual project version; selective references, no memory-based API claims |
| Medium / scratch conflict | Global workspace-temp `:4,7-10`; A/handoff `:8`, A/improve-codebase-architecture `:39`; K/webapp examples | OS-temp/fixed platform paths conflict with host scratch rules. Use unique agent scratch; distinguish runner-owned `.dev/tmp` and mandatory Corvid workspace `.tmp` from ad-hoc scratch |
| Medium / unavailable dependency | A/grill-with-docs `:7`, A/improve-codebase-architecture `:64`, A/frontend-ui-engineering `:308`; interview/accessibility work | `grilling` and referenced accessibility checklist are absent. Repair exact references/dependencies or retire broken wrapper from discovery; no invented substitute |
| Medium / presentation authority | A/improve-codebase-architecture `:39`, `HTML-REPORT.md:13-16`; architecture HTML report | "Self-contained" uses CDN scripts and loose Mermaid security. Honest offline/network contract and strict rendering; source finding, not exploit proof |
| Medium / unsafe examples | K/webapp-testing `scripts/with_server.py:66-100`, `examples/console_logging.py:15-16,31-32`; adapting helpers | Raw commands/console can expose secrets; undrained pipes and shell-only termination undermine lifecycle. Screen output; tracked lifecycle and specific readiness; keep entry authorization boundaries |
| Medium / credential-role history | K/go-shared-access `:17,24,59`, `references/access-model.md:20-25,82-84,126-150`; K/frontend-shared-access `:40-41,45-47,56-57` | Missing checkout reference, mixed migration eras and consume/publish-role claims. Use bundled owner reference, history banners, role-specific statements and value-free checks |
| Medium / false validation claim | K/skill-creator `:147,184-206`; `scripts/quick_validate.py:25-54`, `package_skill.py:68-75`; skill authoring | Regex validator does not provide promised YAML/reference validation; packager includes every file. Align claims/checks; initialize/package only when needed and screen contents |
| Low / duplication, scope | Global execution-focus `:3-9`; K/go `:24-27,37`, K/python `:21-22,42-45,51-52`, K/ponytail `:78-85`, selected skeptic/test agents | Generic evidence/retry/finish policy repeats on activation. State universal policy once; retain language gates, actual attempt accounting and role-specific approval requirements |
| Low / ambiguous portable contracts | K/init-d `:44-45,70-73`; K/package-version-lookup `:14`; K/ponytail `:29-30,58-63,89` | Runner failure semantics, secret-directory exclusion, Go-list ordering and persistent style limits need scoped corrections; no new universal gates |
| Low / overbroad config language | Global config-hygiene `:7-11`; bootstrap AGENTS `:149-157,159-185`; configuration work | Absolute env-only/no-port/disposable-local wording lacks deployment-default and nonrendered-local distinctions. Preserve credential/template protections; scope to app-managed deployment inputs, not arbitrary user config |

The source-only Caddy entry was also read: keep its narrow task trigger and
secret-screening instruction (`B60/kilo/skills/central-caddy/SKILL.md:3-11,228-230`), but replace
deployment-specific fallback examples (`:179-185`) with explicit inputs and
separate agent scratch from provisioning-owned render/cleanup behavior. It is
currently absent, so this is a future-install condition, not current loading.

## Item-Level Target

Universal core: authorization/credential protections, concrete execution outcome,
evidence and required-check reporting, real retry limits, and scoped scratch
policy. Keep permission enforcement in configuration, not merely prose.
A candidate rule budget near 3,000 characters would save roughly 474 heuristic
tokens versus today, **if** preservation checks permit it; this is a target, not
measured savings. Keep tiny image-build/version/log routes where needed.

All discovered filesystem skill bodies were read. The following table covers
the 30 host-root entries; the extra project legacy entry is recorded below.
`=` means entry hash matched its owner;
`modified` means reconcile, not overwrite automatically. Body characters exclude
frontmatter. Resources are inventoried separately and are not default context.

| Entry | Body Chars | Owner / State | Disposition |
|---|---:|---|---|
| K/agent-md-refactor | 7,192 | B37 optional = | Shorten; correct safety deletion advice |
| K/air | 5,329 | B30 = | Keep; canonical template; trim repetition |
| K/artifacts-builder | 2,681 | B37 optional = | Scope standalone artifacts; repair validation/setup |
| K/debug-with-logs | 3,385 | B37 default = | Keep diagnostic/attempt rules; consolidate universal prose |
| K/frontend-design | 3,961 | B37 optional = | Consolidate identity; accessibility precedence |
| K/frontend-shared-access | 2,744 | B98 = | Keep access boundaries; correct role claims |
| K/go | 4,590 | B37 default = | Keep language/project checks; shorten generic policy |
| K/go-shared-access | 2,262 | B99 modified | Repair bundled reference; separate migration history |
| K/gpt-6-sol-execution-plans | 8,901 | B37 default = | Keep explicit Sol trigger; shorten entry/template duplication |
| K/image-build | 750 | B30 = | Keep short publication-contract entry/reference |
| K/init-d | 3,448 | B37 default = | Scope tier-specific semantics and secret handling |
| K/mermaid-diagram-generation | 1,922 | B37 optional = | Keep; scope exports/tool requirements |
| K/neurodivergent-ux | 2,785 | B37 optional = | Keep accessibility; constrain persistence/trigger |
| K/package-version-lookup | 1,431 | B37 default = | Keep local-first lookup; correct version ordering |
| K/ponytail | 3,849 | B37 default = | Shorten; make preference task-scoped |
| K/python | 6,276 | B37 default = | Keep language/tooling gates; trim generic policy |
| K/skill-creator | 11,189 | B37 optional = | Shorten; conditional initialization/package and truthful checks |
| K/svelte-code-writer | 1,644 | B37 optional modified | Reconcile safe source; primary Svelte workflow entry |
| K/svelte-core-bestpractices | 6,911 | B37 optional = | Consolidate entry; preserve version-aware references |
| K/theme-factory | 2,781 | B37 optional = | Scope explicit theme work; skip redundant confirmation |
| K/web-design-guidelines | 916 | B37 optional = | Keep review trigger; remote criteria cannot override authority |
| K/webapp-testing | 9,183 | B37 default = | Keep safety boundary; shorten and repair helper examples |
| A/codebase-design | 5,757 | External | Keep vocabulary; optional fan-out, no session-creation grant |
| A/domain-modeling | 3,027 | External | Scope document writes to actual assignment |
| A/frontend-design | 9,076 | External, shadowed | Consolidate/retire duplicate discovery only with owner consent |
| A/frontend-ui-engineering | 11,331 | External | Shorten; keep UI qualification; repair checklist/dialog example |
| A/grill-with-docs | 66 | External | Retire broken wrapper pending intended dependency |
| A/handoff | 730 | External | Keep; repair scratch destination |
| A/improve-codebase-architecture | 5,784 | External | Explicit entry; repair dependencies/rendering |
| A/research | 519 | External | Keep; scope delegation and report writing |

Other item dispositions: builtin `kilo-config` needs upstream accuracy correction;
absent `central-caddy` stays feature-owned, not globally restored during audit.
Project legacy `.kilocode/skills/skill-creator/SKILL.md` is **32,626 body
characters**, full-file SHA prefix `dcd4803e61e9`, distinct from the advertised
home copy. Scope or retire from discovery with its owner's approval, preserving
its external source/history; this is not a managed bootstrap deletion.
All five rules should be kept/shortened with safety-preservation review.
Global agents: keep reviewer (298 body chars), frontend specialist (942), and
maintainer (2,661) role boundaries; shorten architect (4,206), simplifier (3,059),
skeptic (2,112), mapper (6,196), and test engineer (882) where policy repeats.
Do not remove maintainer approval or bypass denied transports through Bash.
Keep `/audit` (2,737 body chars) and `/commit` (2,304) scope/safety semantics;
shorten only repeated prose. Scope the project context technician (8,994) to its
workshop role; its debug-config/export advice (`:72-79,116`) needs value-free
capture and proven side-effect confinement before future use.
Bootstrap root remains repository-owned: route tool-specific details to their
owners if later requested, preserving tier separation and no escalation.

## Coverage And Exclusions

Read all five rules, eight global agents, two commands, project agent, bootstrap
root, 30 host-root skill entries plus the project legacy entry, builtin config
entry, the absent Caddy source
entry, and differing source counterparts. Mutation/discovery paths and relevant
test callers were source-reviewed. `B37/CONTEXT-SET-GAPS.md` has an explicit
resolved/historical banner (`:3-6`): preserve history; its old "zero always-on
cost" wording (`:25-28`) is not current catalog measurement or executable queue.

**63 installed supporting resources were inventoried: 22 read, 41 excluded.**
An additional **17 project-legacy resources** were inventoried and excluded,
bringing discovered support coverage to **80 files: 22 read, 58 excluded**.
No claim is made that every resource, archive member, example runtime, or public
API fact was audited.

| Skill | Resources Read To Resolve Findings |
|---|---|
| K/air | `assets/air.toml.template` |
| K/artifacts-builder | `scripts/{init-artifact,bundle-artifact}.sh` |
| K/go-shared-access | `references/access-model.md` |
| K/gpt-6-sol-execution-plans | `assets/execution-plan-template.md`, `references/{sol-model-notes,optimization}.md` |
| K/image-build | `references/image-publishing.md` |
| K/skill-creator | `scripts/{init_skill,package_skill,quick_validate}.py` |
| K/svelte-core-bestpractices | `references/{hydratable,await-expressions}.md` |
| K/webapp-testing | `scripts/with_server.py`, `examples/{console_logging,element_discovery,static_html_automation}.py` |
| A/codebase-design | `DEEPENING.md`, `DESIGN-IT-TWICE.md` |
| A/domain-modeling | `ADR-FORMAT.md`, `GLOSSARY-FORMAT.md` |
| A/improve-codebase-architecture | `HTML-REPORT.md` |

| Unread Group | Paths / Count / Reason |
|---|---|
| Licenses | 12 license files across agent refactor, frontend design (both roots), artifacts, skill creator, webapp and themes; not current instructions |
| Patch history | `local.patch` in K/frontend-design, K/artifacts-builder, K/skill-creator (3); preserved provenance, entry/script evidence sufficient |
| Refactor companion | K/agent-md-refactor `README.md` (1); overview not needed to resolve entry finding |
| Artifact archive | K/artifacts-builder `scripts/shadcn-components.tar.gz` (1); contents not executed/unpacked |
| Theme assets | K/theme-factory `theme-showcase.pdf` and all ten `themes/*.md` (11); no theme selected |
| Svelte syntax | K/svelte-core-bestpractices `references/{inspect,snippet,bind,each,render,svelte-reactivity,attach}.md` (7); syntax detail not needed for version/overlap finding |
| Other-client metadata | `agents/openai.yaml` under A/handoff, grill-with-docs, improve-codebase-architecture, research, codebase-design, domain-modeling (6); not used by reviewed Kilo loader |

The unread groups total **41**. License distribution: K/agent-md-refactor 1;
K/frontend-design 2; K/artifacts-builder 2; K/skill-creator 2;
K/webapp-testing 2; K/theme-factory 2; A/frontend-design 1.

Project legacy exclusions (17): `LICENSE.txt`; `agents/{analyzer,grader,comparator}.md`;
`eval-viewer/{viewer.html,generate_review.py}`; `references/schemas.md`;
`assets/eval_review.html`; and `scripts/{__init__,improve_description,run_eval,
quick_validate,utils,package_skill,run_loop,aggregate_benchmark,generate_report}.py`.
They are resources of a shadowed, uninvoked external workflow; its entry alone
establishes the porting/scoping finding. No eval runner, archive or viewer ran.

Additional exclusions: absent Caddy installed resources; canonical/bundled Caddy
guide bodies were compared by size/hash, not semantically audited. No auth stores,
private configs, referenced application/module checkouts, external observation
history, or unrelated provisioning/runtime code were read. Missing `grilling`,
the accessibility checklist and Go checkout were checked, not substituted.
Public lookup was limited to client source/documentation. Exact newer Svelte API
availability was not researched; the finding concerns missing version gating.

## Future Rollout Checks And Unknowns

- Before any future implementation, preserve all credential restrictions,
  no-escalation enforcement, operation-specific authority, actual attempt limits,
  mandatory validation, user extras, and authentic historical evidence.
- Add focused source/fixture checks for redacted diff/import, owned deletion,
  manifests, optional retention, feature routing, canonical-resource convergence,
  and failed-migration partial state. Review unchanged permissions semantically.
- Existing `B37/tests/test-policy.sh:24-155` covers literal policy assertions,
  migrations/refusals/idempotence and file rollback/mode, but uses a fake client
  validator (`:42-48`). B30 `tests/sync-release.bats:21-74` covers reporting,
  modes, symlinks and missing sources. No tests ran; neither proves actual client
  parsing/loading or complete rollback.
- For later runtime qualification, use separately authorized isolated/disposable
  environments: show actual config precedence, skill collision winners, explicit
  command paths, permission-negative cases, MCP schemas/instructions, frontend
  required-check availability, repeated forward/reverse convergence and custom
  user-extra preservation. Establish startup side effects before diagnostics.
- MCP `enabled: false`, skill permissions, discovery switches and project-local
  placement are supported mechanisms, not equivalent isolation guarantees. Do not
  disable mandatory frontend tools until their task-specific entry point works.
  New metadata-based per-skill invocation controls require client changes.
- Retirement must target managed paths with known identities/hash states or an
  explicit operator disposition. Modified managed copies and external skill
  duplicates require review; do not automatically delete them, use wholesale
  reverse-sync, or broaden capabilities just to obtain a smoke result.
- Unknowns: extension implementation; binary/source equivalence; other-process
  environment/organization config; exact startup/tool/catalog token costs;
  historical installation intent; private credential roles/config contents;
  complete client isolation and newer framework API applicability.
- Provisioning, migrators, synchronization, installations, MCP/client startup,
  model-backed probes, service/network/production operations, cleanup and Git
  mutations need separate applicable authorization. This audit ran none of them.

The deliverable is an evidence-backed recommendation with conditional precedence
and a first change queue. It does not certify live client, host, frontend,
provisioning or production behavior. No recommendations were applied.
