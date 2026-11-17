# bmcluster review findings and follow-up status

**Date:** 2026-11-17
**Status:** S0-S4 local validation/review passed; Gate A and operator acceptance blocked
**Scope:** Review findings for the separate, pre-existing bmcluster provisioning work. This note does not represent deployment authorization or a completed two-host verification.

## Current status

The Sol skill was committed separately as `f40e490` (`feat: add GPT-6 Sol execution-plan skill`). None of the bmcluster work was included in that commit.

The findings below prompted edits to `init.d/65-bmcluster/run.sh` and related documentation, which were uncommitted during validation. Existing unrelated work is preserved. This follow-up session changed only `init.d/65-bmcluster/run.sh` and this note in the repository. On 2026-11-17 the operator explicitly requested committing the reviewed bootstrap change set. That request does not approve host acceptance, signing, publishing, activation, or rollout. No provisioning command, privilege escalation, network download, account/service/firewall mutation, push, activation, or live rollout was performed.

The interrupted old harness is not acceptance evidence. A new offline current-source harness retains the removal of invalid in-Match `PermitUserEnvironment` while testing effective `permituserenvironment no`. It reports **87 PASS, zero FAIL**, including real OpenSSH syntax/effective-policy checks and injected failures. Extracted fragments, command mocks, and synthetic fixtures are local regression evidence only, not a real-host installation or a verified signed release.

## Review findings and implemented edits

| Review finding | Provisioning change | Verification status |
|---|---|---|
| Direct sshd writes and early backup deletion could leave an unvalidated or unapplied live policy | Validate a same-directory candidate, atomically install it, retain a backup on restore failure, and report rollback reload/health failures explicitly | **Passed locally:** real candidate checks; initial/idempotent renders; candidate/post-install/reload/health faults; backup content/retention assertion; secondary recovery failures. **Blocked:** real daemon recovery |
| Only an active service was checked, leaving socket activation and enabled units available | Reject active/activating or enabled service and socket units before and after mutations | **Passed locally:** both units' state matrix, supported failed/masked states, and accepted-to-active transitions during mocked provisioning. **Blocked:** host unit tests |
| `BOOTSTRAP_USER=bmcluster` could make the service account its own operator | Reject `DEPLOY_USER=bmcluster` before account/group changes | **Passed locally:** rejection before mutation sentinel and source-order assertion. **Blocked:** host account/group checks |
| Privileged ports were accepted for an unprivileged service | Require `control_port` in `1024..65535` | **Passed locally:** 0, 1023, 65536 and malformed values rejected; 1024 and 65535 accepted by extracted guard |
| Only loopback sshd policy was tested, allowing competing Match contexts to escape review | Put the managed block first with `Match all`, assert restrictions for loopback and a representative remote context, and reject globally enabled `PermitUserEnvironment` | **Passed locally:** real `sshd -t/-T`, all nine restrictions, competing contexts, preserved unrelated policy, valid trailing settings, global user-environment rejection, duplicate/unterminated/nested-Match marker rejection. **Blocked:** real SSH privilege denial |
| Appended UFW denies could sit behind earlier allows, including when UFW was inactive | Require active UFW and insert the managed deny first, then assert effective order and active status | **Passed locally:** broad earlier allow, first insertion, inactive/post-inactive/wrong-order failures, repeated reconciliation. **Blocked:** effective host packet-filter order |
| Endpoint changes left stale managed UFW denies | Match the exact owned comment; delete each duplicate separately with a progress check; assert one physical owned deny and one current endpoint | **Passed locally:** stale IPv4/IPv6 and current IPv4 duplicates, deduplicated `show added`, numbered physical count, unrelated comments/rules preserved, no-progress and duplicate-insertion failures. Selected-current IPv6 binding is not exercised locally |
| Downloads could stall or consume unbounded disk space | Add connection, total, low-speed and retry-window limits plus per-file and post-download size caps | **Passed locally:** all curl bounds/caps traced; all three files' empty/oversize cases; synthetic transport failures; real invalid-signature/checksum failures before mutation sentinel. **Blocked:** signed release/trust and actual transfers |
| The README placed a YAML version key in the environment-variable column | Document `versions.bmcluster` as YAML-only with no environment override | **Passed:** source/documentation inspection and real config-parser fixtures |
| The generic omitted-version `latest` fallback contradicted bmcluster's exact-tag requirement | Exempt bmcluster explicitly in the example configuration and codemap | **Passed:** exact-tag/default-off/gating fixtures and documentation inspection |
| Deploy-account documentation omitted the new account-mutating step | Add `65-bmcluster` and its operator-group behavior to the README and codemap | **Passed:** documentation/source inspection; 18 active root-tier steps accounted for |

## New regressions corrected

- The first retest reproduced cleanup attempting to delete the backup after a failed restore. Cleanup now retains it; the harness asserts its existence and original content, not merely an error message.
- An unterminated managed SSH block could silently truncate unrelated configuration. Both EOF without a terminator and a later unrelated `Match` before a terminator now fail without replacing the original file.
- A substring comment match could misclassify unrelated UFW rules. Ownership now requires the exact quoted managed comment.
- Independent review found that `show added` hides duplicate rules and UFW deletes only one match per operation. Reconciliation now repeats deletion with numbered-output progress checks and verifies the physical owned-rule count; the harness models those semantics rather than deleting all duplicates at once.
- Independent review found silent secondary rollback-reload failures and no recovered-daemon health assertion. Both failures are now explicit nonzero errors requiring console recovery.

## Local evidence

Scratch root: `$HOME/.tmpdir/bmcluster-review-1794877765072/`.

- Baseline: `baseline-status.txt`, `baseline-manifest.txt`, `baseline.patch`, and complete `baseline-source/` copies, including untracked step files. Unrelated user work was neither changed nor attributed to this follow-up.
- Harness command: `UV_OFFLINE=1 uv run --no-project python /home/luke/.tmpdir/bmcluster-review-1794877765072/focused_retest.py`.
- Final output: `final-harness-results.txt`; **87 PASS, zero FAIL**. Detailed extracted cases, traces, transformations, source hashes, and harness hash: `run-20261117T023617347067Z/`.
- Installer SHA-256: `3db8b590e97148969a342ab84a57e47460cd5e538082c379bcbcd358f52ab392`.
- Config-reader SHA-256: `04e58cd735aa0b0ad2a4c7cdcab7314db1b3a5bc11f3e2a7715e2c5036987604`.
- Harness SHA-256: `909c4ad6fa58b04ad859b6121c7441ac9d383f4e0cfd712f5533cd0572a6cbf0`.
- `bash -n init.d/65-bmcluster/run.sh`, `bash -n init.d/lib/conf.sh`, `shellcheck -x init.d/65-bmcluster/run.sh init.d/lib/conf.sh`, and `git diff --check`: **passed**, no diagnostics; outputs saved as `bash-n.txt`, `bash-n-conf.txt`, `shellcheck.txt`, and `diff-check.txt`. Separate syntax checks are intentional: Bash treats a second filename as a script argument, not another file to parse. Plain ShellCheck initially reported SC1091 for a sourced library; `-x` follows and checks the library, without suppressing the diagnostic.
- The read-only independent reviewer initially reported one high and two medium findings. All were reproduced and corrected; corrected-source re-review found no unresolved critical/high finding or missing required S2 category. Its two low documentation precision findings were corrected (separate Bash syntax commands and IPv6 fixture scope). Review disposition is saved in `independent-review.txt`. A clean review cannot replace host acceptance.

The harness executes extracted current-source fragments with only recorded scratch-path transformations. Ownership, account mutation, systemd and UFW operations are mocked or source-inspected; `rm` is trace-only and never deletes scratch. Curl failures are synthetic, so they prove error propagation and configured bounds, not measured transfer time. Disposable OpenSSH keys and a synthetic Ed25519 invalid-signature fixture are not publisher trust anchors. No valid production release was self-signed or claimed. The production files were byte-identical throughout each harness run. This note is updated afterward and therefore has a different hash from the recorded tested snapshot.

## Required follow-up before bmcluster can be accepted

1. **Passed locally:** current-source isolated harness retest after removing invalid in-Match `PermitUserEnvironment`, including new regression fixes.
2. **Passed:** final shell syntax, ShellCheck and whitespace checks. Separate Sol skill validation was not rerun or claimed because no skill was changed.
3. **Passed locally:** complete uncommitted bmcluster diff independently reviewed and corrected-source re-reviewed; initial findings fixed and checks repeated. No unresolved critical/high finding; two low documentation precision findings corrected.
4. **Blocked, unrun:** operator-executed installation, idempotence, rollback, firewall ordering, activation guards and SSH privilege denial on disposable hosts.
5. **Blocked, unrun:** two-host discovery/admission/recovery/partition/privilege matrix and required operator reviews. Gate B has not opened.
6. **Blocked, unrun on a host:** systemd unit validation with the reviewed installed binary. The earlier local absent-binary diagnostic is not installation evidence; this session did not rerun or promote it.

## Operator gates

**Gate A is blocked.** At 2026-11-17T02:45:59Z the operator reported that the hosts are ready and authorized release inspection/building, then approved `/home/luke/cluster` as the checkout and explicitly selected **Trust Not Established**. Per-host identities, supported OS/architecture, deploy users, private interface/IP/port settings, and snapshot/console recovery details have not been supplied. There is still no independently established publisher trust anchor, signed manifest, approved release endpoint or installation/fault-injection runbook. Consequently S5-S8 and Gate B are unrun. No host-specific installation runbook was generated. The foundation plan's task-6 matrix remains a future operator stage, not local evidence; no host acceptance or activation approval is inferred from host readiness.

## Unsigned release candidate

The approved cluster checkout is clean at existing local tag `v0.1.1`, commit `7799c709dcf301bcf3abc533ee7ccb1334e9ee4f`. The previous `dist/cluster` is not eligible for reuse: its embedded metadata records version 0.1.0, source `b55b87e4661b860076afed3ff200c4c734a35a68`, and `vcs.modified=true`. No remote release availability was checked or claimed.

New unsigned artifacts are in `/home/luke/cluster/dist/bmcluster-v0.1.1-unsigned-20261117-d/`. The existing tag was reused; no new version, git tag, source change, commit, push, publication, or signing key was created.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `bmcluster_v0.1.1_linux_amd64` | 8941730 | `27beb60bdc897ea56808cf1b59c431658be3c3b566aa99c2dad5cf921852ea8d` |
| `bmcluster_v0.1.1_linux_arm64` | 8192162 | `23cb7fe884fc0f4c62318117a46cfb2a4e4313ad265a7152496d6220a1d6f481` |

The directory also contains `SHA256SUMS` and `UNSIGNED-CANDIDATE.txt`, but intentionally **no `SHA256SUMS.sig`**. It is not an installable trusted release; the bootstrap installer must continue to reject it until the operator establishes publisher trust and supplies a genuine reviewed signature.

Build evidence and logs: `$HOME/.tmpdir/bmcluster-review-1794877765072/r-v011-20261117-d/`; exact recipe: `build-release-candidate.sh` in the same scratch root. Both artifacts are CGO-disabled, `-trimpath` builds from the full source revision with build number 0 and source-commit timestamp `2026-10-29T21:24:22Z`. Embedded VCS metadata confirms the exact revision and `vcs.modified=false`; rebuilding each architecture with identical metadata was byte-identical. All tracked cluster-file hashes and git status were unchanged before/after building.

Using the already-cached Go 1.26.10 executable with `GOTOOLCHAIN=local`, `GOENV=off`, `GOWORK=off`, `GOPROXY=off`, `GOSUMDB=off`, and telemetry off:

- `CGO_ENABLED=0 go build ./...`: **passed**.
- `go vet ./...`: **passed**.
- `go test -count=1 ./...`: **passed** for all seven packages.
- `CGO_ENABLED=1 go test -race -count=1 ./...`: **passed** for all seven packages.
- `gofmt -l .`: **passed**, empty output; no formatting writes.
- Both cross-builds and identical rebuild comparisons: **passed**.
- amd64 `version` and `help`: **passed**; version reports 0.1.1 and the full source commit. ARM64 runtime behavior remains **unrun**.
- `sha256sum -c SHA256SUMS` from the artifact directory: **passed** for both binaries.

Test commands ran under `umask 022` inside owner-private scratch fixtures. Both `TMPDIR` and `GOTMPDIR` pointed to the approved scratch root to fit Unix-socket pathname limits. Initial attempts are preserved: the host shim exposed Go 1.26.4 when auto-selection was disabled; then restrictive umask and a long socket path invalidated fixtures; a further attempt established that Go 1.26.10's testing package honors `GOTMPDIR` as well as `TMPDIR`. These were diagnosed and corrected in the build environment without changing executable code or bypassing a guard. Tests exercise isolated state and loopback/socket fixtures, not operational enrollment or two-host acceptance. No dependency download or privileged host command was run.

The next gate requires the operator to independently establish the publisher public-key fingerprint, have the reviewed manifest signed by its corresponding publisher, identify the approved HTTPS release directory and artifacts, and supply the non-secret per-host acceptance settings. Locally generated checksums and clean-source provenance do not replace that independent trust review.

## Remaining limitations

- The bmcluster source and documentation remain unverified for production use; a source commit and local evidence are not operator acceptance.
- The signing-key trust anchor and signed release must be established and reviewed before installation can proceed.
- The forced SSH deny remains intentional until live privilege checks and a separate operator decision.
- No finding here changes the completed Sol skill validation or its scoped commit.
