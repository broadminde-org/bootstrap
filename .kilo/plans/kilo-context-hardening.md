# Plan: Kilo Context-Set Hardening

Executor: GPT-5.6 Luna. Repo: `/home/luke/bootstrap`. Read-only elsewhere.
Derived from: session-export analysis (5 sessions, 2026-09-02) + `user/init.d/37-kilo-settings/CONTEXT-SET-GAPS.md`.

## 1. Objective

Close the verified context-set gaps and fix the session-report tooling, as five ordered
tasks: restore two salvaged skills (`debug-with-logs`, `package-version-lookup`) in
trimmed form, add one short `session-economy` rule, remove the dead mcp-server deploy
step from `37-kilo-settings/run.sh`, and fix four defects in `kilo-session-report.py`.

Deliverables (files changed):

- NEW `user/init.d/37-kilo-settings/_kilo/skills/debug-with-logs/SKILL.md`
- NEW `user/init.d/37-kilo-settings/_kilo/skills/package-version-lookup/SKILL.md`
- NEW `user/init.d/37-kilo-settings/_config/kilo/rules/session-economy.md`
- EDIT `user/init.d/37-kilo-settings/run.sh`
- EDIT `user/init.d/30-scripts/scripts/kilo-session-report.py`

## 2. Context (verified this session — re-read before editing)

Existing patterns to follow:

- Rule format: `user/init.d/37-kilo-settings/_config/kilo/rules/workspace-temp.md:1-11`
  — title, `## Scope`, `## Rules` with `SHOUTY_SNAKE` rule names, ≤ ~15 lines.
- Skill format: `_salvage/opencode/skills/debug-with-logs/SKILL.md:1-35` and
  `_salvage/opencode/skills/package-version-lookup/SKILL.md:1-41` — YAML frontmatter
  (`name`, `description` with USE FOR trigger), short sections, anti-patterns list.
- Deploy mechanism: `user/init.d/37-kilo-settings/run.sh:83-85` syncs
  `agents commands rules` from `_config/kilo/` to `~/.config/kilo/`;
  `run.sh:126` syncs `_kilo/skills` to `~/.kilo/skills/`. `sync_dir_preserve` never
  deletes. New files in the skeleton are picked up automatically — no run.sh edit
  needed for tasks 1–3.
- `kilo.jsonc` already carries the `instructions` glob
  (`_config/kilo/kilo.jsonc:3`); rules deploy via the existing sync.

Evidence base for why each task exists (do not re-litigate, do not expand scope):

- 7/7 tool failures in the analyzed sessions were act-without-verifying failures
  (guessed URLs → 404, reads of non-existent files, patch built on stale content).
- The two most expensive sessions mixed 4–8 user tasks and switched models mid-session.
- ~150KB of webfetch output was spent answering a question `npx skills add --help`
  answers locally.
- `kilo-session-report.py` flagged 115/117 turns as high-cost (useless), reported
  `session_diffs_total=0` for a session containing a 195-insertion commit, and
  defaults `sanitize=False` on exports containing live auth/SSH details.

## 3. Acceptance criteria (all must pass)

```bash
cd /home/luke/bootstrap
bash -n user/init.d/37-kilo-settings/run.sh && shellcheck user/init.d/37-kilo-settings/run.sh
python3 -m py_compile user/init.d/30-scripts/scripts/kilo-session-report.py
ls user/init.d/37-kilo-settings/_kilo/skills/debug-with-logs/SKILL.md \
   user/init.d/37-kilo-settings/_kilo/skills/package-version-lookup/SKILL.md \
   user/init.d/37-kilo-settings/_config/kilo/rules/session-economy.md
head -4 user/init.d/37-kilo-settings/_kilo/skills/debug-with-logs/SKILL.md | grep -q '^name: debug-with-logs$'
! grep -n 'mcp-server\|MCP_DEPLOY\|8766' user/init.d/37-kilo-settings/run.sh
grep -q 'no-sanitize' user/init.d/30-scripts/scripts/kilo-session-report.py
grep -q 'exported_summary_diffs' user/init.d/30-scripts/scripts/kilo-session-report.py
grep -q 'user_messages\|model_switches' user/init.d/30-scripts/scripts/kilo-session-report.py
```

Sandboxed deploy smoke test (fake HOME — never the real one):

```bash
mkdir -p .tmp/plan-smoke
HOME="$PWD/.tmp/plan-smoke" bash user/init.d/37-kilo-settings/run.sh
test -f .tmp/plan-smoke/.config/kilo/rules/session-economy.md
test -f .tmp/plan-smoke/.kilo/skills/debug-with-logs/SKILL.md
test -f .tmp/plan-smoke/.kilo/skills/package-version-lookup/SKILL.md
# Expected: no mcp-server output line at all; run exits 0.
rm -rf .tmp/plan-smoke
```

Report-script smoke test:

```bash
python3 user/init.d/30-scripts/scripts/kilo-session-report.py \
  --last 1 --format json --output-dir "$PWD/.tmp/ksr-smoke"
python3 -c "import json; r=json.load(open('.tmp/ksr-smoke/report.json')); \
  assert r['report_meta']['sanitize'] is True; \
  assert 'user_messages' in r['session_summary'][0]; \
  assert 'exported_summary_diffs' in r; print('report OK')"
rm -rf .tmp/ksr-smoke
```

## 4. Risk analysis

| Risk | Mitigation | Check |
|---|---|---|
| Rules/skills enter every agent context on next deploy — bloat reintroduced | Hard size caps (steps below) | `wc -l` per new file: rule ≤ 20 lines, each skill ≤ 60 lines |
| `sanitize` default flip changes existing automation behavior | `--no-sanitize` escape hatch preserves old behavior exactly | smoke test asserts default True; `--no-sanitize` run asserts False |
| P90 high-cost metric changes report semantics | Record computed threshold in `report_meta` so runs are comparable | meta contains `high_cost_threshold_tokens` |
| Renaming `session_diffs` breaks consumers | No known consumers (report introduced this week); rename is total, including the `_total` summary key | acceptance grep above |
| `run.sh` mcp-removal breaks idempotent re-runs on hosts where MCP was once deployed | Deployed `~/.config/kilo/mcp-server/` is left in place (never deleted today either — `sync_dir_preserve` semantics); removal only stops future deploy attempts | smoke test exits 0 with no mcp output |

## 5. Steps (dependency order)

### Task 0 — Discovery (read-only; STOP and re-plan if reality differs)

1. Re-read every file listed as an edit target immediately before editing it. Do not
   patch from memory or from this plan's excerpts. If any target differs materially
   from §2 citations, stop and report the delta.
2. Read both salvaged sources in full:
   `_salvage/opencode/skills/debug-with-logs/SKILL.md`,
   `_salvage/opencode/skills/package-version-lookup/SKILL.md`.

### Task 1 — Restore `debug-with-logs` (broadened: verify-before-act)

Create `_kilo/skills/debug-with-logs/SKILL.md` from the salvaged source with these
edits:

- Keep: LOCATE / FILTER / REPORT rules, methodology, anti-patterns.
- Remove: line 16's `Check /tmp/` guidance (violates the workspace-temp rule);
  replace with workspace-local capture (`<workspace>/.tmp/`).
- Add one section, `## Verify Before Acting`, generalized from the session failures:
  before `read` confirm the path exists (glob); before `webfetch` confirm the URL
  shape (prefer raw source over rendered HTML; list a repo directory before guessing
  file paths); before `edit`/`apply_patch` re-read the exact target lines.
- Frontmatter description must trigger on: debugging, errors, failing tests,
  non-2xx fetches, missing files, failed patches.

Verify: `wc -l` ≤ 60; frontmatter greps pass.

### Task 2 — Restore `package-version-lookup` (widened ground-truth rule)

Create `_kilo/skills/package-version-lookup/SKILL.md` from the salvaged source with
these edits:

- Keep: ecosystems table, fallback chain, anti-patterns. Trim prose; the endpoint
  table is the value.
- Add anti-pattern `WEB_FIRST`: fetching web pages (especially rendered GitHub HTML)
  for facts available from local ground truth — installed CLI `--help`, local
  lockfiles, `git show`, registry APIs via `curl`. Add the positive rule: run the
  local command first; webfetch raw sources only when local ground truth is absent.
- Frontmatter description must trigger on: pinning/upgrading dependencies AND
  researching CLI flags/syntax.

Verify: `wc -l` ≤ 60; frontmatter greps pass.

### Task 3 — Add `session-economy` rule

Create `_config/kilo/rules/session-economy.md`, modeled exactly on
`workspace-temp.md` structure, ≤ 20 lines, rules only (no essays):

- TASK_BOUNDARY: when the user starts a new task unrelated to the current session's
  work, say so and suggest a fresh session; do not silently continue accumulating.
- NO_MID_SESSION_MODEL_SWITCH: do not change model or reasoning variant mid-session;
  if the current model is failing, say so and stop rather than switching.
- COMMIT_NEEDS_ASK: executing a plan is not authorization to `git commit`/`git push`;
  only commit when the user explicitly asks in the current session.
- LOCAL_TRUTH_FIRST: pointer to the two skills by name for version/CLI/log facts.

Verify: `wc -l` ≤ 20; deploy smoke test (§3) finds it under fake HOME.

### Task 4 — Remove dead mcp-server step from `run.sh`

Edit `user/init.d/37-kilo-settings/run.sh`:

- Delete the MCP server header block (lines 45-49: "MCP server: Source/Deploy/
  Listens/Mounts").
- Delete step 5 in full (lines 128-162, including the `MCP_SRC`/`MCP_DEPLOY` logic
  and the docker compose start), and the now-unused `MCP_DEPLOY` variable (line 65).
- Delete the summary line advertising the MCP endpoint (line 172).
- Fix the stale kilo.jsonc comment (line 32): it currently says "permissions-only
  config", but kilo.jsonc actually carries both the `instructions` glob and
  permissions. Rewrite as one factual line covering both (e.g. "instructions glob
  (rules/) plus permissions"). Do not touch any other header line.

Verify: `bash -n`, `shellcheck`, `! grep -n 'mcp-server\|MCP_DEPLOY\|8766'`, and the
sandboxed deploy smoke test shows no mcp output and exit 0.

### Task 5 — Fix `kilo-session-report.py` (four defects)

Edit `user/init.d/30-scripts/scripts/kilo-session-report.py`. Re-read each region
before editing; current line numbers: sanitize flag 128-131, high-cost gate
1189-1192, session_diffs collection 1344-1351, session_summary assembly 1358-1375,
report assembly 1770-1807, compact renderer 1842+.

1. **Sanitize default-on.** Flip `--sanitize` to `action="store_true", default=True`
   and add `--no-sanitize` (`action="store_false", dest="sanitize"`) so the old
   behavior stays reachable. Update the help text.
2. **Useful high-cost metric.** After collecting all assistant turns for the run,
   compute P90 of `total_tokens`; a turn is high-cost iff
   `total_tokens >= max(p90, min_total_tokens)`. Record
   `high_cost_threshold_tokens` in `report_meta`. Keep `--min-total-tokens` as the
   absolute floor; `--min-input-tokens` no longer independently qualifies a turn
   (remove that clause).
3. **Rename `session_diffs` → `exported_summary_diffs`** everywhere (dict key,
   compact section tag, `session_diffs_total` → `exported_summary_diffs_total`,
   JSON payload key, `--top-diffs` help text note that this reflects only
   `info.summary.diffs`, not observed edits).
4. **Add two `session_summary` fields:** `user_messages` (count of `role == "user"`
   messages) and `model_switches` (number of times consecutive assistant messages
   change `modelID`). Include both in the compact `<session_summary>` row format.

Verify: `py_compile`, acceptance greps, and the report smoke test in §3 (asserts
sanitize default, new fields, renamed key).

## 6. Stop conditions & escalation

- Any §2 citation does not match the file on re-read → stop, report the delta, do
  not improvise.
- Same acceptance check fails 3× → stop and report; no silent workarounds.
- Report smoke test fails because `kilo` CLI is unavailable/broken in this
  environment → run `py_compile` + a `--help` invocation as fallback verification
  and mark the smoke test as DEFERRED in the final report (do not delete the check).
- Anything that looks like it needs a change outside the five deliverables → note it
  in the final report; do not edit it.

## 7. Assumptions & open questions

- `sync_dir_preserve` never deletes: the restored skills will not remove any stale
  live copies; acceptable (they are new names).
- Live deployment (`./user/init.sh 37-kilo-settings` against real `$HOME`) is a
  user action after review — the executor must not run it. The fake-HOME smoke test
  is the deploy verification.
- No consumers depend on the `session_diffs` report key.
- Out of scope (do not touch): the 3–7 minute bash stall investigation (host-state
  debugging, not a repo edit); the `config-hygiene` rule (deferred); restoring any
  other salvaged content (CONTEXT-SET-GAPS R6); committing anything.

## 8. Executor self-check gate (before final answer)

- Re-read §1: exactly five deliverables, no more.
- Every §3 command run, output shown, expected result matched.
- `git status --short` shows only the five deliverables changed vs. the pre-existing
  dirty state (which included: `example.bootstrap.conf.yml`, `skills-lock.json`,
  `commands/audit.md`, `element_discovery.py`, `run.sh` ×2, and untracked `.kilo/`,
  `.kilocode/`, `_plans/`, `_salvage/`, `context-workshop/`, `kilo-session-reports/`,
  `CONTEXT-SET-GAPS.md`, `system-maintainer.md`, `kilo.jsonc`, `rules/`). Untracked
  files you add under `_kilo/skills/` and `_config/kilo/rules/` are expected.
- No `git commit`, no `git push`, no writes outside `/home/luke/bootstrap`.
- Temp scratch lived in `$PWD/.tmp/` and was removed.

## 9. Non-negotiables

1. Re-read each target file immediately before editing it; never patch from memory.
2. No git mutations — plan execution is not commit authorization.
3. Never run `run.sh` against the real `$HOME`; fake-HOME only.
4. Size caps are hard: rule ≤ 20 lines, skills ≤ 60 lines each.
5. Scratch only in `<workspace>/.tmp/`, removed when done.
