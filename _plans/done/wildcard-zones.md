# Plan: config-driven wildcard zones for central Caddy

Executor: **DeepSeek V4 Pro, thinking enabled** (all steps chain ≥10 tool calls).
Reviewer: **outside reviewer (human or different model) — mandatory before S9.**
Supersedes: `_plans/central-caddy.md:404` (§5 sketch) with the shape actually chosen.

## 1. Objective

Replace the hardcoded three-template wildcard seeding in `user/init.d/60-caddy` with config-driven, credential-gated wildcard zone rendering — deliverables: edits to `init.d/lib/conf.sh`, `bootstrap.conf.yml`, `example.bootstrap.conf.yml`, `user/init.d/60-caddy/run.sh`, `user/init.d/60-caddy/stack/bin/caddy-route`, one new template `user/init.d/60-caddy/stack/wildcard.caddy.tmpl` (three WIP templates deleted), doc updates to `docs/central-caddy.md`, `README.md`, `codemap.md`, and a revision note in `_plans/central-caddy.md`.

## 2. Context

Locked design decisions (from review, 2026-08-05):

1. Repo stays generic: zones come only from untracked config; zero `broadminde.org` in tracked files.
2. Zone set: `ci` retired (woodpecker CI deploys its own); `dev` = shared `*.dev.<base>` for throwaway dev envs (PWA-grade FQDNs); `host` = `*.<hostname>.<base>` for Netbird-overlay services.
3. Gating = config list AND credentials check: render listed zones only after `acmedns.json` holds a real acme-dns account.
4. Architecture: wildcard site blocks (cert-warming placeholder; apps register more-specific sites via `caddy-route`, most-specific match wins). NOT §5's single-server model.
5. DNS-01 constraint accepted: the reconcile merge in `caddy-route` preserves per-site TLS policies with their subjects (injecting the global issuer's `email`/`ca`), so DNS-01 applies only to names that declare it — one DNS-01 provider (acmedns) per host. Verified live on broadminde1.

Live state on broadminde1 (gathered read-only 2026-08-05):

- `caddy` container running, healthy; it is the live edge. `~/infra/caddy/routes.d/` contains: `ci-wildcard.caddy`, `dev-wildcard.caddy`, `host-wildcard.caddy`, `netbird.caddy`, `netbird-api.caddy`.
- `~/infra/caddy/acmedns.json` holds a REAL single acme-dns account (top-level `fulldomain` key present) — the creds gate is OPEN on this host.
- Live admin API: `srv0` routes = `birb.broadminde.org`, `*.broadminde1.broadminde.org`, `*.dev.broadminde.org`, `*.ci.broadminde.org` (Caddy consolidates :443 sites into one server); one global TLS policy with production CA + email + dns challenges.
- Working tree contains intentional uncommitted changes (F1 config-parity fix + this WIP). No `git checkout/restore/commit` is permitted.

Patterns to follow (read these exactly):

- `get_caddy_conf` must follow `get_pinned_version` at `init.d/lib/conf.sh:157-166` (auto-load guard, `[[ -v ARR[key] ]]` check, echo value else default).
- Section parsing must follow the two existing loops in `load_conf` at `init.d/lib/conf.sh:85-112` (third loop, section name `caddy`, into a new `declare -A _CADDY_CONF` beside `init.d/lib/conf.sh:45-46`). Parser anchor `_parse_section` at `init.d/lib/conf.sh:59-74` matches `^caddy:` at column 0 — the indented `caddy: true` under `capabilities:` cannot false-match.
- Render idempotency must follow compare-before-write `sync_file` at `user/init.d/60-caddy/run.sh:117-123`.
- Error exits must use `die()` at `user/init.d/60-caddy/stack/bin/caddy-route:25`.

Files this plan touches (exact list): `init.d/lib/conf.sh`, `bootstrap.conf.yml`, `example.bootstrap.conf.yml`, `user/init.d/60-caddy/run.sh`, `user/init.d/60-caddy/stack/bin/caddy-route`, `user/init.d/60-caddy/stack/wildcard.caddy.tmpl` (new), delete `user/init.d/60-caddy/stack/{ci,dev,host}-wildcard.caddy.tmpl` (untracked WIP), `docs/central-caddy.md`, `README.md`, `codemap.md`, `_plans/central-caddy.md` (one note only).

Files never to touch: `~/infra/caddy/**` (live dir), `netbird.caddy`, `netbird-api.caddy`, `compose.override.yaml`, `.env`, `acmedns.json`, any file not in the list above.

## 3. Acceptance criteria

- **AC-1** `bash -n init.d/lib/conf.sh user/init.d/60-caddy/run.sh user/init.d/60-caddy/stack/bin/caddy-route` → exit 0, no output.
- **AC-2** Fixture: config with `capabilities: {caddy: true}` and a `caddy:` section (`base_domain: example.net`, `wildcards: "dev host"`). Source `init.d/lib/conf.sh`, `BOOTSTRAP_CONFIG_FILE=<fixture>`, `load_conf` → `get_caddy_conf wildcards` prints `dev host`; `get_caddy_conf base_domain` prints `example.net`; `get_caddy_conf missing fb` prints `fb`; `cap_enabled caddy` returns 0; `get_pinned_version python` still returns the fixture's `versions:` pin.
- **AC-3** Sandbox matrix (harness per S4 verify): all six cases produce the exact expected `routes.d/` tree and log lines:
  1. placeholder `acmedns.json` (`{}`) + zones set → NOTE printed; pre-existing `dev-wildcard.caddy` and `netbird.caddy` fixtures byte-identical afterwards.
  2. real-creds shape + `wildcards: "dev host"` → `dev-wildcard.caddy` contains `*.dev.example.net`; `host-wildcard.caddy` contains `*.$(hostname).example.net`; both pass `grep -c 'dns acmedns /etc/caddy/acmedns.json'` = 1.
  3. case 2 then `wildcards: "host"` → `dev-wildcard.caddy` absent; `host-wildcard.caddy` present; log line names the removed file.
  4. fixture legacy `ci-wildcard.caddy` + `wildcards: "dev"` → `ci-wildcard.caddy` absent after run.
  5. `wildcards: ""` + fixtures `dev-wildcard.caddy`, `host-wildcard.caddy` → both absent; exit 0 (no unbound-variable abort).
  6. `wildcards: "dev bad_label!"` → stderr warning names `bad_label!`; only `dev-wildcard.caddy` rendered; exit 0.
- **AC-4** `STACK_DIR=/tmp/x caddy-route register foo-wildcard /etc/hostname` → exit 1, stderr contains `reserved`; and `grep -n 'wildcard' user/init.d/60-caddy/stack/bin/caddy-route` shows the reservation appears only inside `cmd_register`.
- **AC-5** `grep -rn 'ci-wildcard\|dev-wildcard\|host-wildcard' --exclude-dir=.git --exclude-dir=_plans .` → zero hits; `ls user/init.d/60-caddy/stack/*.tmpl` → exactly `Caddyfile.tmpl` and `wildcard.caddy.tmpl`.
- **AC-6** Doc greps: `grep -n '^## Wildcard zones' docs/central-caddy.md` → 1 hit; `grep -c 'reserved' docs/central-caddy.md` ≥ 1; `grep -n 'Root-tier step count: 16' codemap.md` → 1 hit and the line contains `06`, `57`, `58`; `grep -n 'caddy:' README.md` ≥ 1 hit in the Configuration section; `_plans/central-caddy.md` §5 region contains `2026-08-05`.
- **AC-7 (operator, live)** After the operator run (S9): step exits 0 with all `PASS:` lines; `docker exec caddy curl -s --unix-socket /run/caddy-admin.sock http://localhost/config/apps/http/servers/srv0/routes | jq -r '.[].match[0].host[0] // empty'` lists `birb.broadminde.org`, `*.dev.broadminde.org`, `*.broadminde1.broadminde.org` and NOT `*.ci.broadminde.org`; `caddy-route list` shows `dev-wildcard.caddy`, `host-wildcard.caddy`, `netbird-api.caddy`, `netbird.caddy`.

## 4. Risk analysis

| # | Risk (touching: idempotency, live edge, file lifecycle) | Check |
|---|---|---|
| R1 | Transient creds-skip deletes live zones: cleanup runs when rendering was skipped → live wildcard sites torn down by an unrelated re-run | AC-3 case 1 |
| R2 | Stale cleanup deletes app snippets: files not owned by the step (e.g. `netbird.caddy`) must survive every cleanup pass | AC-3 cases 1–5 fixtures include `netbird.caddy`, asserted present each time |
| R3 | Label injection: a config label containing `/`, `..`, or shell metacharacters writes outside `routes.d/` or breaks the render | AC-3 case 6 |
| R4 | Parser cross-talk: indented `caddy: true` under `capabilities:` leaks into `_CADDY_CONF`, or the `caddy:` section corrupts `cap_enabled caddy` / version pins | AC-2 |
| R5 | `set -u` abort on empty zone set (empty associative-array expansion under `set -u` in run.sh which sources common.sh) | AC-3 case 5 |
| R6 | Name reservation overreach: reservation blocks `deregister`/manual cleanup or legit registrations | AC-4 + reservation confined to `cmd_register` |
| R7 | Live `*.ci.broadminde.org` removal kills something in use | Operator pre-check in S9 (traffic review); rollback = add `ci` back to `wildcards` (generic renderer re-renders `*.ci.<base>`; CNAME presumed still in DNS) |
| R8 | acme-dns single account, 2-TXT concurrency: first simultaneous dev+host issuance races | S9 post-check: after 5 min, `docker exec caddy find /data/caddy/certificates -name '*.crt'` lists certs for both new names; one missing → wait for Caddy's internal retry, re-check once, then escalate |

## 5. Steps (dependency order)

### S0 — Discovery (read-only)

1. Open every file cited in §2 at the cited lines. STOP and re-plan if any anchor differs.
2. Run: `grep -rn 'ci-wildcard\|dev-wildcard\|host-wildcard\|_render_snippet' --exclude-dir=.git .` — expect hits only in `user/init.d/60-caddy/run.sh`, the three template files themselves, and `_plans/`. Any other hit → STOP.
3. Confirm the exact replacement span in `user/init.d/60-caddy/run.sh`: the block from the separator comment immediately before `# Step 7.5:` (currently line 197) through the last `_render_snippet` call (currently line 226). Record start/end lines.
4. Confirm nothing else in the repo references `_render_snippet` after this step's edits would land (only run.sh:201-226 may contain it).

### S1 — `init.d/lib/conf.sh`: parse the `caddy:` section

- Add `declare -A _CADDY_CONF` beside `init.d/lib/conf.sh:45-46`.
- In `load_conf` (`init.d/lib/conf.sh:85-112`), after the versions loop, add a third identical loop parsing section `caddy` into `_CADDY_CONF`.
- Add public function `get_caddy_conf <key> [default]` after `get_pinned_version` (`init.d/lib/conf.sh:166`), following that function's exact pattern; default default is empty string.
- Update the public-interface header comment (`init.d/lib/conf.sh:19-27`) to list it.
- **Verify:** AC-1 (conf.sh only) and AC-2. Both must pass before S2.

### S2 — Config files: new `caddy:` section

- `example.bootstrap.conf.yml`: append a documented `caddy:` section after `versions:` (file ends at line 65). Style: match the file's existing boxed comment banners. Semantics to document: `base_domain` = zone apex; `wildcards` = space-separated DNS labels, label L serves `*.L.<base_domain>`, special label `host` serves `*.<hostname>.<base_domain>`; rendering activates only after `acmedns.json` holds a real acme-dns account; empty `wildcards` = no zone snippets. Values: `base_domain: example.com`, `wildcards: ""`.
- `bootstrap.conf.yml` (live, untracked): same section, values `base_domain: broadminde.org`, `wildcards: "dev host"`.
- **Verify:** `BOOTSTRAP_CONFIG_FILE=example.bootstrap.conf.yml bash -c '. init.d/lib/conf.sh; load_conf; get_caddy_conf wildcards EMPTY'` prints `EMPTY`; same command against `bootstrap.conf.yml` prints `dev host`.

### S3 — Templates: delete three, add one

- `rm user/init.d/60-caddy/stack/ci-wildcard.caddy.tmpl user/init.d/60-caddy/stack/dev-wildcard.caddy.tmpl user/init.d/60-caddy/stack/host-wildcard.caddy.tmpl`
- Create `user/init.d/60-caddy/stack/wildcard.caddy.tmpl`. Required content semantics: header comments state (a) managed-by `user/init.d/60-caddy`, rendered copy must not be hand-edited; (b) purpose: wildcard cert + placeholder for `*.${ZONE_FQDN}` via DNS-01/acme-dns; (c) apps register more-specific site blocks via `caddy-route`, most-specific match wins; (d) prerequisite: `_acme-challenge.<zone>` CNAME pointing at the acme-dns account fulldomain, one account serves many delegations. Body: a single site block for `*.${ZONE_FQDN}` containing a `tls` block with `dns acmedns /etc/caddy/acmedns.json`, and a `respond` directive answering 200 with a body naming the zone. No global block. No other directives.
- **Verify:** AC-5 (file listing part); and `ZONE_FQDN=dev.example.net envsubst '$ZONE_FQDN' < user/init.d/60-caddy/stack/wildcard.caddy.tmpl | grep -c 'dns acmedns'` → `1`.

### S4 — `user/init.d/60-caddy/run.sh`: rewrite Step 7.5

Replace the span recorded in S0.3 (currently lines 197-226) with new logic. Requirements:

- Read zones via `get_caddy_conf wildcards ""` and apex via `get_caddy_conf base_domain ""`.
- Creds gate: rendering proceeds only when `$STACK_DIR/acmedns.json` is valid JSON AND (top-level `fulldomain` key exists OR at least one top-level key exists). `{}` must fail the gate.
- Skip matrix (each branch prints a NOTE naming the condition; wording must name the remediation):
  - `wildcards` empty → render nothing; stale cleanup STILL runs (deliberate opt-out).
  - `wildcards` set, `base_domain` empty → skip everything; existing files untouched.
  - `wildcards` set, creds gate fails → skip everything; existing files untouched; NOTE names `bin/acmedns-register` as remediation.
  - `wildcards` set + gate passes → render active zones; stale cleanup runs.
- Zone mapping: label `host` → `$(hostname).$base_domain`; any other label → `$label.$base_domain`. Labels must match `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`; non-matching label → stderr WARNING naming it, skip that label, continue, exit stays 0.
- Render: one output file per zone, `routes.d/<label>-wildcard.caddy`, from `stack/wildcard.caddy.tmpl` via `envsubst '$ZONE_FQDN'`, compare-before-write (pattern at run.sh:117-123), `chmod 0644`, set `routes_changed=1` and print one log line per ACTUAL write only.
- Stale cleanup: for each existing `routes.d/*-wildcard.caddy` whose filename label is not an active zone, remove it, print a log line naming it, set `routes_changed=1`. Cleanup executes only in the two branches marked "cleanup runs" above. Non-matching files (e.g. `netbird.caddy`) are never candidates.
- `routes_changed` stays uninitialized-by-default (consumed as `${routes_changed:-0}` at run.sh:296); never set it to 0 explicitly.
- Preserve everything outside the replaced span byte-for-byte. `_render_snippet` must not exist afterwards.
- **Verify:** AC-1, then AC-3 via this harness: extract the new Step 7.5 from run.sh with `sed -n '/# Step 7.5:/,/# Step 8:/p'` (drop the final boundary line) into a snippet; run it in subshells with `set -euo pipefail`, stubbed `STACK_DIR`/`SRC_DIR` under a tmp tree, the real modified `init.d/lib/conf.sh` sourced with `BOOTSTRAP_CONFIG_FILE` pointing at per-case fixture configs, real `jq`/`envsubst`. Assert file trees with `ls`, contents with `grep`, logs by capture. All six AC-3 cases must pass; any failure → fix and re-run the FULL matrix.

### S5 — `user/init.d/60-caddy/stack/bin/caddy-route`: reserve managed names

- In `cmd_register` (`caddy-route:173`), immediately after the `check_app_name` call, add a register-time rejection: any app name ending in `-wildcard` dies via `die()` with a message containing `reserved` and pointing at `caddy.wildcards` in `bootstrap.conf.yml`. Register path only; `cmd_deregister` (`caddy-route:199`) and `cmd_list` unchanged.
- **Verify:** AC-1 (caddy-route) + AC-4.

### S6 — Documentation

- `docs/central-caddy.md`:
  - New `## Wildcard zones` section (place after `### DNS-01 setup`, before `## Port conflicts` at docs/central-caddy.md:86). Must state: `caddy:` config schema and label→FQDN expansion incl. `host`; creds gate and the four skip-matrix branches verbatim from S4; cleanup semantics (dropped zones removed and reconciled away; the zone's cert remains unused in `caddy_data`); cert-warming model with most-specific-match-wins; a registered app site MAY obtain its own cert via the same acme-dns account (phrase as possibility, not guarantee); app names ending `-wildcard` are reserved.
  - `### DNS-01 setup` (docs/central-caddy.md:70-84): add that ONE `acmedns-register` run yields ONE account, and EACH zone label needs its own `_acme-challenge.<label>.<base_domain>` (plus `_acme-challenge.<hostname>.<base_domain>` for `host`) CNAME pointing at the SAME fulldomain; note acme-dns holds max 2 TXT records per account — stagger first issuance if errors appear.
  - `## TLS modes` (docs/central-caddy.md:63): add the constraint — per-site TLS policies are preserved at reconcile with their subjects (DNS-01 scoped to declaring names only); one DNS-01 provider (acmedns) per host; introducing a different DNS provider requires reworking the merge in `caddy-route`.
  - `## Related files` (docs/central-caddy.md:216): add `stack/wildcard.caddy.tmpl`.
- `README.md`: in `### Central Caddy (60-caddy)` (README.md:34) add 2-3 sentences: wildcard zones are configured via the `caddy:` section of `bootstrap.conf.yml` (`base_domain` + `wildcards` labels), render only after acme-dns registration, details in `docs/central-caddy.md`. In `## Configuration` (README.md:98) add one line naming the `caddy:` section and its two keys.
- `codemap.md`:
  - Fix `codemap.md:122`: count 13 → 16; enumeration must include `06`, `57`, `58`.
  - Fix `codemap.md:184`: replace the claim that fail2ban/crowdsec reference `/home/stack/netbird-docker/logs/caddy/access.log` with the resolver behavior — shared `init.d/lib/caddy-log.sh` resolves `$CADDY_LOG_PATH` override → live log by mtime → central `~/infra/caddy/logs/access.log` default → legacy as last fallback.
  - Add a `60-caddy` row to the User-Tier Step Ownership Table (starts codemap.md:124): central Caddy at `~/infra/caddy`; compare-before-write sync; `.env` seeded 0600; Caddyfile rendered compare-before-write; wildcard zones from `caddy:` config, creds-gated; never starts a stopped container; reconcile hash-skip.
- `_plans/central-caddy.md` §5 (line 404): append one revision note — implemented 2026-08-05 as config-driven wildcard site blocks per `_plans/wildcard-zones.md`; the single-server sketch shape is superseded.
- **Verify:** AC-6.

### S7 — Executor self-check gate (§8) → final report with evidence.

### S8 — Outside review (HUMAN or different model — mandatory)

Reviewer walks the full diff against every AC. Any failed criterion returns to the relevant step.

### S9 — Live run (OPERATOR ONLY — executor MUST NOT perform)

Pre-checks (operator judgment): confirm nothing is served under `*.ci.broadminde.org` (expectation: nothing; woodpecker not yet deployed); note rollback is config-only (`wildcards: "dev host ci"` re-renders `*.ci.<base>`).

```bash
./user/init.sh 60-caddy
```

Expected: renders `dev` + `host` wildcards (respond-body text differs from WIP renders → `routes_changed`), removes `ci-wildcard.caddy`, no image rebuild (Caddyfile unchanged), reconcile pushes exactly once, Step 9 prints all `PASS:` lines. Then verify AC-7, and after ~5 min check cert storage per R8. If R8 shows one missing cert: wait for Caddy's internal retry, re-check once, then escalate.

## 6. Stop conditions & escalation

- Any S0 anchor mismatch → STOP, report the mismatch; do not improvise.
- Same AC failing after 2 fix attempts → STOP, report the failing command + full output.
- A verify command fails for environmental reasons (missing `jq`/`envsubst`, tmp space) → STOP; installing packages or changing the environment is out of scope.
- Forbidden without exception: running `./user/init.sh` or any step of it; running `caddy-route reconcile/register/deregister` against the live container; any mutating `docker` command (`exec` writes, `cp` into `caddy`, `compose up/down/restart`); `git` mutations of any kind; hand-editing anything under `~/infra/`; "temporary" bypasses of the creds gate or cleanup rules; expanding scope to any finding outside §2's file list.

## 7. Assumptions & open questions

- Live `bootstrap.conf.yml` values are `base_domain: broadminde.org`, `wildcards: "dev host"` — the `host` label is retained for Netbird-overlay services (stated in review; user did not object).
- `ci` retirement is safe: nothing is served under `*.ci.broadminde.org` today. Confirmed only by operator judgment at S9, not by traffic analysis.
- The pending reconcile push on broadminde1 (hash drift from the uncommitted `acme_ca` Caddyfile line) is expected and will ride along with the S9 push; it is not a defect.
- Deferred (needs a host with a plain public site): whether an HTTP-01-only name issues cleanly with dns challenges on the global issuer. Constraint accepted in decision 5; unverified.
- Executor runs as user `luke` on broadminde1 with repo at `/home/luke/bootstrap`; sandbox work happens under `/tmp`.
- No commit is part of this task; the working tree stays uncommitted.

## 8. Executor self-check gate

Before reporting done: re-read §1; for each AC-1…AC-6 paste the exact command run and its observed output as evidence; list every assumption the executor itself introduced beyond §7; confirm §6 produced zero violations.

## 9. Non-negotiables

1. The live edge is operator-only: the executor never runs `user/init.sh`, `caddy-route reconcile/register/deregister`, or any mutating `docker` command.
2. The creds gate and cleanup-only-when-render-ran are inseparable: render without the gate, or cleanup during a skip, both fail the task.
3. Zones come from config only: zero occurrences of `broadminde.org` (or any org domain) in tracked files after this plan lands, except pre-existing history under `_plans/`.
4. Only the files listed in §2 may change; `netbird.caddy`, `netbird-api.caddy`, `compose.override.yaml`, `.env`, `acmedns.json`, and `~/infra/**` are untouchable.
5. Every step's verify command passes, with output captured, before the next step begins.
