---
name: artifacts-builder
description: >-
  Create complex multi-component HTML artifacts with React, TypeScript,
  Tailwind CSS and bundled shadcn/ui sources. Use when state management,
  routing or reusable components warrant a project, not for simple single-file
  HTML/JSX. Initialization prepares local dependencies; bundling requires that
  prepared workspace and does not install dependencies.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: artifacts-builder
    license_path: artifacts-builder/LICENSE.txt
---

# Artifacts Builder

Use the existing project's design system and the user's intent. For a new UI,
avoid interchangeable centered layouts, excessive gradients and uniform cards;
choose typography, hierarchy and interaction deliberately. Preserve accessibility
and responsive behavior. Use a simpler single-file implementation when a project
is unnecessary.

## Entry Points

Resolve this loaded skill's directory as `SKILL_DIR`; do not assume its scripts
exist in the project or in the current working directory. These examples use
placeholder paths and require appropriate execution/dependency authority:

```bash
SKILL_DIR=/absolute/path/to/artifacts-builder
# Run from the intended existing, nonredirected parent directory.
bash "$SKILL_DIR/scripts/init-artifact.sh" artifact-demo
# After editing the generated project, bundle from any working directory.
bash "$SKILL_DIR/scripts/bundle-artifact.sh" /absolute/path/to/artifact-demo
```

The initializer accepts exactly one simple lowercase project name, not a path.
The destination must be absent, including empty directories and dangling links.
The bundler accepts exactly one prepared project directory; parent traversal and
redirected ancestors, source paths, configuration and owned state are rejected.
Do not use these helpers to adopt or overwrite an existing project. A copied
marker is insufficient: admission also checks directory identities, canonical
configurations, pinned manifests, the prepared lock and installed package versions.

## Preparation And Editing

Use the host's configured Node toolchain, not an implicit upgrade. This stack
requires Node **22.9 or newer** and existing **npm 11.20.0**. Missing/incompatible
tooling is a blocker; the helper never installs global tooling. Direct package
pins are in `scripts/stack.json`: React 18.3.1, TypeScript 5.9.3, Vite 6.4.1,
React plugin 4.7.0, Tailwind 3.4.17 and single-file plugin 2.3.0. This is a local
deterministic scaffold, not an unpinned `create-vite` download. Both development
and artifact bundling use Vite; Parcel/html-inline are no longer used.

Initialization first checks arguments, existing Node/npm, the absent destination,
required archive assets, checksums, path containment and tar entry/link types.
Only then does it create the workspace and prepare dependencies locally with
npm. Registry access and dependency lifecycle scripts belong to this explicit
preparation step and need authorization. npm configuration/cache/temp are reserved
under `.artifact-output`; distinct `user.npmrc` and `global.npmrc` files are admitted
and fingerprinted together. Installation explicitly uses the new project as its
`--prefix` and disables workspaces with `--workspaces=false`, rather than selecting
an ancestor monorepo. No global install or HOME-config write is requested.
Failed preparation leaves the incomplete new directory for inspection, without
a prepared receipt or a successful-initialization claim. A retry does not erase
or reuse it: inspect it and choose a new absent destination.

Edit `src/App.tsx`, other source files, CSS and `index.html`. Import components
using `@/components/ui/button`, for example. Import local images/fonts from source
so Vite can process them; the artifact bundler disables `public/` copying.
Generated `src/vite-env.d.ts` references `vite/client` for asset and URL/raw import
types. Keep that declaration available to the all-source TypeScript check.
Manifest, lock and managed configuration edits invalidate admission. To change
the stack/configuration, review this skill's source and initialize a new absent
workspace; do not recompute receipts from current files to bypass a rejection.
Keep the generated lock with the project: exact direct pins do not freeze every
transitive resolution before initialization.

For authorized interactive development, run the prepared project's `npm run dev`
using the available process supervisor. Development server output/ports are not
part of the offline artifact. No host/domain/port is forced by this skill.

## Prepared-Only Bundling

The bundler imports installed local packages and runs the local TypeScript
compiler across `src` without emitting files. It does not use npm/pnpm/npx, dependency
installation, registry resolution or manifest/lock/config writes. Missing or
mismatched preparation is a failure, not permission to install. It disables Vite
config loading and `.env` loading, supplies the reviewed build configuration, and
stages build output, cache and temporary files inside a newly owned
`.artifact-output/stage-*` directory. It does not clean root `dist/` or root
`bundle.html`. The workspace, output directory and ownership receipt must remain
private. Compiler/install diagnostics are suppressed by the helper to avoid
publishing source/environment/credential-bearing errors; reproduce a diagnostic
only with authorized project tooling and screen it before reporting.

The published file is **`<project>/.artifact-output/bundle.html`**. Publication
requires a nonempty inlined HTML build with no additional emitted assets and a
conservative remaining-reference check. Repeated publication requires the prior
file to match its recorded successful hash. Modified, unknown, redirected or
missing recorded outputs are refused rather than overwritten. Unknown extras
outside the newly owned stage are preserved. Build/inlining failure leaves the
prior bundle intact. Rollback snapshots are read before stage reservation; all
postreservation setup is cleanup-guarded. Cleanup removes only the stage matching
its captured directory identity; failure to capture that identity or a replacement
stage leaves unknown state for manual review, never an unauthenticated deletion.
Ordinary receipt-publication failure attempts restoration
only if the just-published bytes still match. Interrupted publication or concurrent
changes can leave an unknown baseline requiring manual review. Receipts are local
ownership evidence, not an adversarial sandbox; avoid concurrent workspace writers.

Vite's single-file plugin is intended to inline build-generated JavaScript and
CSS, with imported assets converted to data URLs. This is **not** proof that
arbitrary application code is offline, that all fonts/chunks work, or that the
result can be rendered as a native artifact by the active client. Dynamic fetches,
navigation, remote embeds and other application behavior need explicit review and
offline qualification. Do not describe a file as fully self-contained solely
because bundling returned success.

## Verification And Presentation

Before declaring the artifact finished, qualify the generated all-component
source build and the final file's interactions, accessibility, desktop/mobile
layout and offline assets/chunks/fonts using an authorized executor. Preserve
required checks from the project and frontend/testing skills. If execution,
dependency preparation or browser access is unavailable, report the source-only
result and the exact missing qualification instead of skipping it as optional.

The original component archive is retained unchanged. Static inspection found
calendar `DayButton`/`DayPicker` imports and resizable `PanelGroup`/
`PanelResizeHandle` references; a build/export mismatch has **not** been
reproduced. Do not patch those APIs without reproducing against the selected
prepared stack. API correction and functional/offline qualification remain pending.

Return the published file path through the client's supported file/link surface.
Use a native artifact renderer only if the active client actually provides one;
Kilo conversation text alone does not guarantee inline HTML rendering. Distinguish
source work, produced files and verified behavior in the final report.

Future qualification cases are inventoried in `scripts/qualification-cases.json`.
Runnable, **UNRUN** Node built-in regression source is in `tests/artifact.test.mjs`.
It calls the production wrappers, with synthetic archive/admission fixtures and
no-mutation assertions. An installer stub records arguments and generated scaffold
files in new synthetic projects, including ancestor workspace/lock/dependency/script
sentinels, then deliberately fails without preparing dependencies or a receipt.
That contract test is not real npm workspace/install qualification.
It never automatically initializes or installs the
prepared bundle fixture. The lifecycle requires a fresh production-initialized
synthetic workspace directly under the executor's temporary parent, named
`artifact-regression-prepared-...`, with all pinned/native dependencies available.
Do not copy/rewrite receipts to create that prerequisite. Use an existing Node
>=22.9 and non-root Linux `/bin/bash`/`/usr/bin/dirname` inside a separately authorized
network-denied executor. An environment flag alone is not network isolation.

After that separate authorization and manual preparation, the invocation is:

```bash
ARTIFACT_TEST_OFFLINE_EXECUTOR=1 \
ARTIFACT_TEST_OLD_NODE=/absolute/existing-node-below-22.9 \
ARTIFACT_TEST_PREPARED_WORKSPACE=/absolute/disposable-temp/artifact-regression-prepared-case \
TMPDIR=/absolute/disposable-temp \
node --test "$SKILL_DIR/tests/artifact.test.mjs"
```

The harness changes only dedicated synthetic fixtures and the supplied disposable
workspace, leaving that workspace's last valid bundle for inspection. Missing
prepared/offline prerequisites fail the lifecycle rather than trigger preparation.
The required real below-minimum Node case fails with prerequisite guidance unless
an existing `ARTIFACT_TEST_OLD_NODE` binary is explicitly supplied; missing
executors do not waive qualification. Tests check type/build and
post-inlining refusal, repeat publication, modified/unknown/missing outputs,
redirected paths, forged config baselines, missing dependencies, unchanged
manifests/locks/config (including both npm config files), unknown extras and incidental
scratch writes. Added asset cases exercise imported SVG/font URLs, URL/raw queries
and CSS URLs through the prepared type/build path; synthetic font bytes do not
qualify font decoding or rendering. Private copied-helper fault cases inject early
rollback-read and stage-setup failures and check that no stage or changed baseline
remains. All of these tests remain UNRUN. They do not
provide a browser executor or prove arbitrary app networking is absent.

Required remaining qualification includes a forced all-component runtime import
build, offline browser assets/chunks/fonts/interactions/accessibility/mobile cases,
real npm installation under an ancestor monorepo with unchanged ancestor sentinels,
missing transitive/native dependencies and injected inliner/receipt-rename/
interruption/concurrent-writer failures. These need the prepared toolchain and an
authorized offline browser/fault-injection executor; the API mismatch remains
unreproduced. Original license/provenance and dated local changes are retained in
`LICENSE`, `LICENSE.txt` and `local.patch`.

Reference: https://ui.shadcn.com/docs/components
