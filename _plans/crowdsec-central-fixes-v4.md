# DeepSeek V4 Execution Plan: CrowdSec ↔ central-Caddy link fixes

**Routing: run on `deepseek-v4-pro` with thinking enabled (high).** This plan
chains >10 tool calls across 6 files. Final diff review by a separate reviewer
(not V4 itself).

The authoritative spec is `_plans/crowdsec-central-fixes.md` in this repo
("SPEC"). Read it first. Its code blocks are authoritative **except** where
this plan overrides them (§3, §8).

## 1. Objective

Make the host CrowdSec LAPI reachable from the central caddy container and add
an end-to-end bouncer-link health assertion, by editing
`init.d/54-crowdsec/run.sh` and `user/init.d/60-caddy/run.sh` per SPEC, plus
the four cross-reference updates SPEC names.

## 2. Context

Read these exact files/anchors before editing. STOP and re-plan if any anchor
does not match reality.

- `_plans/crowdsec-central-fixes.md` — SPEC. Fixes in §"Fix 1" (1a–1d) and
  §"Fix 2"; cross-references in §"After landing".
- `init.d/54-crowdsec/run.sh` (217 lines):
  - Header step list to extend: lines 13–41 (note the existing `4b` sub-step
    style at lines 36–38 — match it).
  - Step 2 (package install) ends line 92; Step 3 header begins line 94.
    New Steps 2b/2c insert between them.
  - Step 4 samples `acquis_changed=0` / `cs_was_active` at lines 123–125.
  - Step 5 restart gate to modify: line 187
    (`if [[ "$acquis_changed" -eq 1 && "$cs_was_active" -eq 1 ]]; then`).
  - Step 7 post-conditions: lines 200–214; new assertion goes after line 214,
    before the closing `echo ""` at line 216.
- `user/init.d/60-caddy/run.sh` (297 lines):
  - `CROWDSEC_BOUNCER_KEY` read into scope at line 155.
  - Step 9 post-conditions live inside `was_running -eq 1` (lines 275–294).
    New assertion inserts between the `caddy adapt` block (ends line 286) and
    the `caddy-route list` block (line 288).
  - Existing FAIL convention to match: lines 283–286 (FAIL to stderr, then
    `exit 1`).
- `init.d/lib/common.sh:2` — `set -euo pipefail` is in force for 54-crowdsec
  (root tier). `user/init.d/lib/common.sh:2` likewise for 60-caddy. Every
  variable used in arithmetic must be initialized on every path.
- `init.d/52-ufw/run.sh:28-33,86-91` — the "no ufw rules for Docker-published
  ports" doctrine. SPEC §1b explains why the new host-bound LAPI rule is a
  different category and belongs in 54-crowdsec, not 52-ufw. Do not add
  anything to 52-ufw.
- Cross-reference targets:
  - `codemap.md:117` — stale `54-crowdsec` row (says "appends Caddy log path
    to `/etc/crowdsec/acquis.yaml`"; drop-in has replaced the append).
  - `codemap.md:184` — stale "crowdsec acquis.yaml references the same path"
    cell (same staleness class; found in plan review, included here).
  - `docs/central-caddy.md` — no CrowdSec section exists; add one immediately
    before `## Architecture` (line 185).
  - `_plans/central-caddy.md:507-522` — review-fix log table; append a new
    dated subsection after line 522, before `### No-auto-start` (line 524).

## 3. Corrections to SPEC (verified during plan review 2026-08-04 — mandatory)

1. **SPEC §1a's `sed` is broken as written.** It uses bare `(...)` with a `\1`
   backreference; GNU sed in default BRE mode rejects this:
   `sed: -e expression #1, char 180: invalid reference \1 on \`s' command's RHS`
   (reproduced on a fixture). Under `set -e` the step would abort mid-run.
   **The substitution must use `sed -E`** (extended regex). With `-E`, the
   exact pattern/replacement in SPEC §1a was verified: rewrites the line,
   preserves leading indentation, appends the `# managed by` comment, creates
   the `.crowdsec-bak` backup, and the §1a idempotency grep then matches.
2. SPEC §1c's parenthetical is satisfied by SPEC §1a's own `lapi_changed=0`
   initialization at the top of Step 2b (2b always executes, so the Step 5
   arithmetic is always defined). Do not also add a duplicate declaration in
   Step 4 — one initialization, in 2b.
3. **Addition to SPEC §1b/2c** (flagged, small): after the ufw block, when
   `ufw` exists but `ufw status` does not report `Status: active`, print a
   one-line WARNING to stderr that LAPI now binds 0.0.0.0:8080 and is
   unfiltered until ufw is enabled (52-ufw stages but never enables — Phase
   1c is manual). Rationale: SPEC's whole premise is "nothing tells the
   operator"; a staged-but-inactive ufw leaves 0.0.0.0:8080 world-reachable.

## 4. Acceptance criteria (all local, all executable)

Run from the repo root `/home/luke/bootstrap`. Every check must pass.

1. `bash -n init.d/54-crowdsec/run.sh && bash -n user/init.d/60-caddy/run.sh`
   → exit 0.
2. `shellcheck -f gcc init.d/54-crowdsec/run.sh user/init.d/60-caddy/run.sh`
   → exactly 3 findings, all SC2016, all in `user/init.d/60-caddy/run.sh`
   (the pre-existing intentional envsubst literal-var notes). Zero findings
   in `init.d/54-crowdsec/run.sh`. (Baseline captured pre-change: identical.)
3. `grep -c 'listen_uri' init.d/54-crowdsec/run.sh` → ≥ 4 (2b present);
   `grep -q 'CrowdSec LAPI from docker bridges' init.d/54-crowdsec/run.sh`
   → exit 0 (2c present); `grep -q 'ufw status' init.d/54-crowdsec/run.sh`
   → exit 0 (§3.3 warning present).
4. `grep -q 'sed -i.crowdsec-bak -E' init.d/54-crowdsec/run.sh` → exit 0
   (the §3.1 correction landed; a bare-`(` BRE form is a FAIL).
5. Restart gate: `grep -q '\$((acquis_changed + lapi_changed))' init.d/54-crowdsec/run.sh`
   → exit 0, and the line number of `lapi_changed=0` is strictly less than
   the line number of the restart gate (`grep -n` both, compare).
6. `grep -q 'caddy crowdsec health --address unix//run/caddy-admin.sock' user/init.d/60-caddy/run.sh`
   → exit 0, and the match's line number falls inside the Step 9
   `was_running -eq 1` block (between the `caddy adapt` check and the
   `caddy-route list` check).
7. Behavioral harness (throwaway, under `/tmp`, `set -euo pipefail`): extract
   the Step 2b logic (with `CONFIG_YAML` pointed at a fixture) and run three
   cases. Expected:
   - fixture with `listen_uri: 127.0.0.1:8080` (indented under `api:`/`server:`)
     → line rewritten to `0.0.0.0:8080` with the `# managed by` comment,
     leading indentation preserved, `.crowdsec-bak` backup created,
     `lapi_changed` becomes 1;
   - fixture already at `0.0.0.0:8080` → file byte-identical, "skipping"
     branch, `lapi_changed` stays 0;
   - fixture with any other value (e.g. `10.0.0.5:8080`) → file
     byte-identical, WARNING on stderr, `lapi_changed` stays 0.
   Then run the rewritten fixture through 2b a second time → byte-identical,
   "skipping" branch (idempotency).
8. Restart-gate probe (throwaway, `set -euo pipefail`): the modified Step 5
   condition with (`acquis_changed`,`lapi_changed`) ∈ {0,1}² and
   `cs_was_active` ∈ {0,1} → restart fires exactly for
   {(1,0,1),(0,1,1),(1,1,1)} and for no other combination; no
   unbound-variable abort in any combination.
9. Cross-references: `grep -q '0.0.0.0:8080' codemap.md docs/central-caddy.md`
   → exit 0 for both; `grep -q '2026-08-04' _plans/central-caddy.md` → exit 0;
   `grep -q 'acquis.d/caddy-central.yaml' codemap.md` → exit 0.
10. `git diff --stat` lists exactly these 6 files and no others:
    `init.d/54-crowdsec/run.sh`, `user/init.d/60-caddy/run.sh`, `codemap.md`,
    `docs/central-caddy.md`, `_plans/central-caddy.md`,
    `_plans/crowdsec-central-fixes.md` (status-line update, step 6.5).

## 5. Risk analysis

One acceptance check per risk. Live-host-only checks are marked OPERATOR.

| # | Risk | Check |
|---|---|---|
| R1 | `sed` corrupts `/etc/crowdsec/config.yaml` on the live host → LAPI fails to start, host IPS down | §4.7 three-case harness passes on fixtures (incl. `.crowdsec-bak` backup assertion) before any host run; OPERATOR: `cscli lapi status` per SPEC §Verification |
| R2 | BRE/ERE sed bug — SPEC §1a as written aborts under `set -e` (verified, §3.1) | §4.4 grep proves `-E` form; §4.7 case 1 shows the rewritten line |
| R3 | `set -u` abort: `lapi_changed` unbound at the Step 5 gate on any path | §4.5 init-before-use ordering; §4.8 probe over all 8 combinations exits clean |
| R4 | Restart logic wrong: restarts an unchanged daemon (needless LAPI blip) or skips restart after a `listen_uri` change (inert config) | §4.8 truth table: restart fires exactly for {(1,0,1),(0,1,1),(1,1,1)} |
| R5 | `0.0.0.0:8080` bound while ufw is staged-but-inactive → LAPI reachable with no firewall (52-ufw never enables; Phase 1c is manual) | §4.3 `ufw status` grep proves the §3.3 warning exists; OPERATOR: confirm `ufw status` reports active on the live host |
| R6 | Health assertion silently downgraded to a warning → the fail-open bug SPEC exists to fix persists | `grep -A6 'did not pass within 60s' user/init.d/60-caddy/run.sh \| grep -q 'exit 1'` → exit 0 |
| R7 | Idempotency regression: re-run duplicates the ufw rule or re-seds the config | §4.7 second-pass byte-identical check; OPERATOR: live re-run per SPEC §"Idempotency" |

## 6. Steps (dependency order)

Discovery is read-only. If any §2 anchor mismatches, STOP — see §7.

1. **Discover.** Read every file/anchor in §2 and all of SPEC. Confirm:
   `listen_uri` appears nowhere outside `_plans/` (SPEC §"Gap 1" claim);
   `init.d/54-crowdsec/.requires` contains `public`;
   `user/init.d/60-caddy/.requires` contains `docker` + `caddy` (60-caddy is
   NOT public-gated; its CrowdSec parts are gated in-script — do not touch
   `.requires` files).
2. **Edit `init.d/54-crowdsec/run.sh`.**
   a. Insert Step 2b per SPEC §1a **with the §3.1 `-E` correction**, between
      the Step 2 block (ends line 92) and the Step 3 header (line 94).
      `lapi_changed=0` initializes at the top of 2b. Keep SPEC's
      comment-header style and its warn-and-leave-untouched branch for
      non-default values.
   b. Insert Step 2c per SPEC §1b immediately after 2b, **plus the §3.3
      inactive-ufw WARNING**.
   c. Replace the Step 5 restart gate (line 187) with the arithmetic-sum form
      per SPEC §1c.
   d. Add the Step 7 post-condition assertion per SPEC §1d after the
      firewall-bouncer PASS (line 214).
   e. Extend the header step list (lines 13–41) with `2b` and `2c` entries in
      the existing `4b` sub-step style (one to three lines each: LAPI binds
      0.0.0.0:8080 for docker-bridge reachability, exposure scoped by the
      ufw rule; ufw allows 172.16.0.0/12 → 8080/tcp).
   Verify: criteria 4.1–4.5, 4.7, 4.8.
3. **Edit `user/init.d/60-caddy/run.sh`.** Insert the bouncer-link health
   assertion per SPEC §2 at the §2 anchor. Hard requirements: runs only when
   `CROWDSEC_BOUNCER_KEY` is non-empty; 12 attempts × 5s; on failure prints
   SPEC's FAIL + four diagnostic lines to stderr and `exit 1`; on pass prints
   SPEC's PASS line. Never starts/stops the container. Match the existing
   two-space `  PASS:`/`  FAIL:` indentation.
   Verify: criteria 4.1, 4.2, 4.6, R6.
4. **Cross-references.**
   a. `codemap.md:117` — rewrite the `54-crowdsec` row: managed
      `acquis.d/caddy-central.yaml` drop-in (not acquis.yaml append), LAPI
      `listen_uri` 0.0.0.0:8080 management, ufw 172.16.0.0/12 → 8080/tcp rule,
      restart on config change to a running daemon. Idempotency column:
      compare-before-write/skip throughout, ufw rule skipped when present.
   b. `codemap.md:184` — replace the stale "crowdsec acquis.yaml references
      the same path" with the drop-in equivalent.
   c. `docs/central-caddy.md` — new `## CrowdSec` section immediately before
      `## Architecture` (line 185). Cover, concisely: bouncer gated on the
      `public` capability + generated key; LAPI reached at
      `http://host.docker.internal:8080`; host side expects
      `listen_uri: 0.0.0.0:8080` and the ufw 172.16.0.0/12 rule (both owned by
      root-tier 54-crowdsec); the bouncer is fail-open, so a broken link is
      silent; diagnostics: `docker exec caddy caddy crowdsec health --address
      unix//run/caddy-admin.sock` (also `ping` / `check <ip>`),
      `cscli bouncers list`.
   d. `_plans/central-caddy.md` — new dated subsection
      (`### Review-fix round (2026-08-04)`) after line 522, before
      `### No-auto-start`: two gaps (loopback-only LAPI + ufw default-deny →
      container-unreachable LAPI; no end-to-end bouncer health assertion →
      silent fail-open), where fixed, and that §4's checks verify.
   Verify: criterion 4.9.
5. **SPEC bookkeeping.** In `_plans/crowdsec-central-fixes.md`: flip the
   status line (line 3) to implemented with date, and append one line to §1a
   noting the `sed -E` correction (§3.1 here) so the spec matches reality.
6. **Final gate.** Run every §4 criterion; capture command + output for the
   §9 self-check. `git diff --stat` must show exactly the 6 files.

## 7. Stop conditions & escalation

- Any §2 anchor mismatches (line numbers drifted, text differs) → STOP,
  report the mismatch, re-plan. Do not eyeball an alternative anchor.
- The same §4 criterion fails 3 times → STOP, report the failing command,
  output, and what was tried.
- shellcheck reports anything beyond the 3 baseline SC2016 notes → fix the
  new finding; do not suppress with a disable directive.
- Forbidden without explicit operator instruction: editing files outside the
  6 named in §4.10; touching `~/netbird-docker`; editing `bootstrap.conf.yml`
  (gitignored live-host config); running any step against the live host
  (no `sudo ./init.sh`, no `docker exec`, no `systemctl`); committing.

## 8. Assumptions & open questions

- SPEC's `caddy crowdsec health|ping|check --address` flag support was
  re-verified during plan review against the local `caddy-custom:latest`
  image (`--address` is a global flag on all three subcommands).
- `ufw show added` prints staged rules including comments regardless of
  active state (SPEC §1b) — standard ufw behavior; not re-verifiable here
  without root. The 2c idempotency grep on the comment string depends on it.
- Additions beyond SPEC, all flagged: §3.1 (sed `-E`, mandatory correctness
  fix), §3.3 (inactive-ufw WARNING), header list update (step 6.2e),
  `codemap.md:184` (step 6.4b), SPEC status bookkeeping (step 6.5). Each is
  required by a §4 criterion; none changes SPEC's design.
- Live verification on broadminde1 (SPEC §"Verification") needs root on the
  host, `public: true` in the gitignored `bootstrap.conf.yml`, and a running
  central container. It is an **operator handoff**, not part of this
  execution. Rollback: SPEC §"Rollback". The
  `~/netbird-docker/_plans/caddy-conversions.md` §4 gate update is a
  separate repo, separate commit — out of scope here.

## 9. Self-check gate (before declaring done)

Re-read §1. For each §4 criterion and each §5 risk check: paste the command
you ran and its actual output, marked PASS/FAIL. List every assumption you
made that is not already in §8. If any criterion is FAIL or unverifiable
locally, say so explicitly — do not declare done.

## 10. Non-negotiables

1. The `listen_uri` substitution uses `sed -E`. The SPEC §1a bare-paren form
   is verified broken. Always back up (`.crowdsec-bak`) before writing; a
   non-default, non-target `listen_uri` is warned about and left untouched —
   never clobbered.
2. `lapi_changed=0` is initialized exactly once, unconditionally, before the
   Step 5 arithmetic (`set -u` aborts on an unbound variable).
3. The 60-caddy health assertion runs only when `CROWDSEC_BOUNCER_KEY` is
   non-empty, and on failure it prints the FAIL block and exits 1. It must
   never be downgraded to a warning — silent fail-open is the bug being
   fixed.
4. Repo edits only. Never run the steps against the live host; never
   start/stop/restart any service or container; never commit.
5. Scope is the 6 files in §4.10. No refactors, no drive-by fixes, no
   netbird-docker, no `bootstrap.conf.yml`.
