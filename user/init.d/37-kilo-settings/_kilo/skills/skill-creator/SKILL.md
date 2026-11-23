---
name: skill-creator
description: >-
  Guide for creating effective skills. This skill should be used when users want
  to create a new skill (or update an existing skill) that extends Kilo's
  capabilities with specialized knowledge, workflows, or tool integrations.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: skill-creator
    license_path: skill-creator/LICENSE.txt
---

# Skill Creator

Bootstrap-modified 2026-11-23; preserve both original license files and the
historical adaptation/current repair record in local.patch on refresh.

## Authoring Workflow

1. Establish concrete selecting tasks and the intended outcome. Use supplied
   examples; ask only about unresolved decisions that affect the result.
2. Inspect the existing skill before editing. Preserve permission, trust,
   credential, acceptance, and applicable executor boundaries. A size target or
   link to an unloaded document is not a replacement for a required safeguard.
3. Write non-obvious, task-specific instructions. Prefer imperative workflow
   steps, usable entry points, failure handling, and explicit acceptance checks.
4. Include only resources the workflow needs. Instruction-only skills need just
   SKILL.md. Add scripts for repeated deterministic work, references for details
   loaded on demand, and assets for files used in output. Link exact paths, not
   imaginary placeholders. Inspect scripts before executing them; a skill is not
   execution authorization.
5. Validate structure when an explicitly prepared parser is available. Review
   description usefulness and instruction quality manually. Exercise the real
   selecting tasks only under applicable execution authority; static validation
   does not prove behavior, effective loading, or permissions.
6. Package only when distribution is requested, after reviewing the exact file
   inventory and licensing. Ordinary authoring/iteration does not need a ZIP,
   dependency preparation, or an initializer execution.

Keep selection metadata concise and specific. Put core workflow/boundaries in
SKILL.md and lengthy details in resources. Actual loading depends on the client;
do not promise fixed token costs, unlimited resources, or filesystem precedence.
Retain external-executor instructions when that executor cannot load host rules.

## Metadata And References

Use YAML frontmatter delimited by lines containing exactly `---`, with nonempty
string `name` and `description`. The name must match the directory and contain
1-40 lowercase letters/digits separated by single hyphens. Folded, literal, and
quoted YAML text are decoded, not matched as description text by a regex.

The validator rejects duplicate mapping keys at any depth, non-string keys,
aliases/anchors/merges, unsupported fields, wrong types, empty instructions, and
name-directory mismatches. Optional `license`, `compatibility`, and `allowed-tools`
are nonempty strings. Optional `metadata` is a mapping of JSON-compatible values.
Optional `references` is a unique list of exact local paths, a helper convention
for explicit checks, not a promise of client loading support.

The validator checks single-line Markdown inline links and link definitions,
plus backticked paths beginning with scripts/, references/, or assets/. It checks
local existence/containment and rejects links through symlinks or lexical parent
traversal (including encoded traversal). It does not fetch external HTTP(S) or
mailto links, validate anchor existence, infer prose filenames, or implement a
complete Markdown parser. Use these explicit link forms for bundled resources;
review other syntax manually. Packaging additionally checks these references in
every selected Markdown file (case-insensitive `.md` extension) and requires
referenced resources in the inventory.

## Explicit Parser Preparation

Preparation is a separate, authorized operation, never part of validation or
packaging invocation. Use existing uv and an already installed Python interpreter
(Python 3.10+ for these helpers); do not install uv, download Python, upgrade the
host toolchain, or silently fall back to a system/project environment. PyYAML
6.0.3 is pinned in `scripts/requirements.txt` and has no runtime dependencies.
Registry metadata was checked on 2026-11-23 at
https://pypi.org/pypi/PyYAML/6.0.3/json. The pin fixes the parser release, not a
cross-platform interpreter/build lock or a proof of installed package integrity.

After separately authorizing preparation, set `CREATOR` to this skill's reviewed
absolute directory, `EXISTING_PYTHON` to an existing interpreter, and `CREATOR_ENV`
to an absent, private, nonredirected directory outside projects/loaded context.
Use the host-approved scratch policy. These commands create that environment and
install the pinned parser; **do not run them during source/static-only work**:

```bash
uv venv --no-python-downloads --python "$EXISTING_PYTHON" "$CREATOR_ENV"
uv pip install --python "$CREATOR_ENV/bin/python" --no-deps --only-binary :all: -r "$CREATOR/scripts/requirements.txt"
```

Do not use uv run, uvx, pip auto-install, activation-based ambient discovery, or
another command that creates/synchronizes an environment on invocation. If the
prepared interpreter or exact parser version is absent, report the blocker.
Never prepare dependencies just to make a source-only check pass.

## Production Invocations

Set `CREATOR_PYTHON` explicitly to the previously prepared environment's Python
and use absolute paths. `-B` prevents bytecode writes and `-s` disables user-site
packages. These invocations do not install dependencies/create environments or
execute resources; initialization and packaging still write their declared outputs
and require corresponding authority. They work from unrelated or project CWDs.
Run only against private, owned, quiescent directories without concurrent writers.
Path admission is not an OS sandbox: ancestor replacement races, mount redirection,
malicious interpreter/module replacement, and abrupt host failure are not covered.

```bash
"$CREATOR_PYTHON" -B -s "$CREATOR/scripts/quick_validate.py" "$SKILL_DIR"
"$CREATOR_PYTHON" -B -s "$CREATOR/scripts/init_skill.py" "$SKILL_NAME" --path "$SKILLS_PARENT"
"$CREATOR_PYTHON" -B -s "$CREATOR/scripts/package_skill.py" "$SKILL_DIR" --output-dir "$PACKAGE_DIR" --inventory "$REVIEW_INVENTORY"
```

Initialization requires an existing parent and an absent destination, even if an
existing directory is empty or a link is dangling. It validates all inputs before
writes, reserves the destination exclusively, and creates only SKILL.md. It requires
Linux directory-relative/no-follow operations, `pthread_sigmask` and `sigtimedwait`,
running in a standalone single-thread interpreter's main thread; unsupported
platforms fail before writes, without a fallback or new
dependency. It temporarily records SIGINT/SIGTERM without raising from Python
callbacks, then reports the first signal at explicit protected-cleanup checkpoints
as KeyboardInterrupt/nonzero exit. While helper handlers are active, already queued
callbacks and later signals cannot interrupt cleanup or replace the first
interruption. It blocks kernel delivery only
while reservation/open establishes descriptor-pinned
ownership and during bounded cleanup/signal-state restoration. Pending reservation
or file-open signals are delivered after unmasking inside the cleanup guard; writes
stay interruptible and use the pinned file descriptor directly (including partial
writes). Before restoring the original mask, bounded native-pending signal drains
and a recorded-callback checkpoint retain authenticated cleanup and nonzero
interruption. Prior handlers and masks are restored on exit. After that final mask
handoff, restored caller policy owns any newly arriving signal; this is not immunity
after the helper's guarded operation has ended.

On a handled failure, cleanup compares live identities with the still-open owned
descriptors, removes only authenticated files and the empty authenticated directory,
and preserves replacements/extras. Missing ownership or failed cleanup is reported
without caller paths/content, never as success. SIGKILL, other unhandled termination,
host failure, and concurrent ancestor/mount replacement cannot guarantee cleanup.
An inherited ignored or blocked SIGINT/SIGTERM is incompatible: refuse before writes
without changing caller handlers, masks or pending signals. Default/custom handlers
and unrelated blocked signals are preserved. No foreign threads/external signal
state mutation may participate in the standalone invocation. Initialization neither
creates parents nor resources/examples, nor edits an existing skill. Its TODO
description is valid YAML but must be completed manually before use. If cleanup
is prevented by filesystem failure/concurrent changes, inspect the partial owned
directory rather than treating it as success or recursively deleting it.

## Reviewed Distribution

Require an explicitly reviewed JSON inventory outside the skill. Format:

```json
{"files": [{"path": "SKILL.md", "sha256": "<64 lowercase hex characters>"}]}
```

Review every selected path and its complete contents, then record its SHA-256.
Add the needed resources and all existing LICENSE, LICENSE.txt, NOTICE, and
local.patch files. Inventory hashes bind approval to exact bytes; changed inputs
fail rather than being automatically admitted. Do not generate an approval from
a recursive walk or let the helper's screening replace human review. Include no
real credentials in fixtures, logs, inventories, or reports.

The packager refuses duplicate/invalid inventory entries, redirected ancestors or
leaves, links/special files anywhere in the skill, hardlinked files, traversal,
hidden paths, recognizable secret names/content, common local/generated/cache
paths, archives, and existing ZIP destinations. The output directory must already
exist outside the skill; the inventory must also be outside it. No recursive
selection, self-inclusion, output-directory creation, or overwrite option exists.
Unselected ordinary files stay out of the archive. Binary assets still require
content review; heuristics cannot prove absence of credentials or recognize every
generated file. Use only reviewed public inputs, not an arbitrary project tree.

The archive is built from screened, hash-matched bytes in a private output-local
stage, integrity-checked, and atomically published without clobbering. Failure
before publication leaves no ZIP; a handled post-publication cleanup failure
removes only the owned archive identity. Temporary stages are not named ZIPs.
Existing outputs are left unchanged, including on failures. Abrupt process/host
termination can leave a private temporary stage; filesystem cleanup failures are
blockers, never success. No helper prints source snippets, secret matches, raw
parser exceptions, selected filenames, or caller path values in its result.

## Qualification Gates

[Source tests](tests/test_creator_static.py) contain source-only assertions: they
parse helper source without importing or executing it, creating fixtures, or
preparing tools.
It is not functional qualification. Source/static checks may compile text in
memory and run installed lint with caching disabled; never compileall/py_compile
to disk. Under source-only authority, inspect but do not run tests or helpers.

[Runtime test source](tests/test_creator_runtime.py) supplies focused, unrun
unittest cases using the production CLIs from an unrelated owned CWD, with Q6
initializer fault cases also repeated from an owned fixture project CWD. After
separate runtime authorization, explicitly export `CREATOR_PYTHON` (the prepared
interpreter above) and `CREATOR_TEST_SCRATCH` (an existing, nonredirected scratch
parent outside real HOME and this skill), then invoke:

```bash
"$CREATOR_PYTHON" -B -s "$CREATOR/tests/test_creator_runtime.py"
```

The suite fails its prerequisite gate if the interpreter/parser/scratch is
unavailable; it never installs, creates an environment, or silently skips. Only
owned TemporaryDirectories are created. Child HOME, XDG, and temp paths are
isolated there; no host environment values are passed through. A site-disabled
child checks the unprepared-parser case without uninstalling anything. The
staged-write failure case patches ZipFile in an isolated child that runs the
production command's main entry point. Initializer fault wrappers run the same CLI
entry point: SIGINT/SIGTERM are sent to the owned child just after directory/file
creation before wrapper return, verifying deferred delivery, failure cleanup, retry,
and restored prior handlers/masks. Parent-descriptor acquisition is guarded too;
its pending-signal/open-failure cases require exact descriptor-release receipts.
Writing, signals after replacement/extra creation,
combined pending SIGINT/SIGTERM, second signals/queued callbacks during cleanup and
restoration (including native pending signals with prior default/custom handlers),
open/write/cleanup/descriptor-close failures, unsupported primitives and unchanged
prior ignored/blocked-state refusal (including pending blocked signals),
and normal success are also
covered in UNRUN source. No PID-churn or unrelated-process signals are used.
These test sources are not passed evidence.
The full qualification inventory below still includes cases not implemented by
this focused suite, especially other helpers' project-CWD and packaging failure
boundaries.

After separate isolated runtime authorization, qualify production entry points
from unrelated and project CWDs with synthetic fixtures: folded/literal/quoted
YAML; nested duplicates/wrong types/name mismatch/missing or escaping references;
unprepared/wrong-version parser without installation; instruction-only/repeated
initialization and invalid/traversal names with unchanged existing destinations;
SIGINT/SIGTERM during reservation, exclusive file creation and writing, pending
delivery after masking, restored prior signal state, open/write/cleanup failures,
combined pending signals, second/queued cleanup and restoration callbacks, and
descriptor-close/native-wait failures (no buffered flush phase exists);
parent-open-to-bookkeeping interruption, failed parent admission and descriptor
release receipts;
normal success/retry, and preserved file/directory replacements and extras;
inventory hash mismatch/omitted resources/licenses; symlink/root/parent/leaf,
hardlink and special-file refusal; synthetic secrets and local/generated paths;
self-inclusion, existing output, injected ZIP-write/integrity/publication/cleanup
failure with no new success-looking archive. Compare bytes, directory inventories,
and exit statuses before/after, not success messages alone. Missing execution
authority or prepared tooling leaves these required cases blocked.
