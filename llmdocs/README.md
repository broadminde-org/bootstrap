# llmdocs

LLM-friendly upstream-docs generator framework.

Stdlib-only Python framework that turns upstream Sphinx/Markdown/
XML docs into token-dense, scannable Markdown for use as LLM context.
The framework owns the universal pipeline (clone, prep, page
resolution, emit, postprocess, write); per-source wrappers (a small
folder each) supply the parts that vary: repo URL, source format,
emitters, and any source-specific transforms.

## Why

Upstream-doc generators tend to converge on the same pipeline shape
(clone upstream → prepare source → resolve pages → emit → postprocess
→ write). `llmdocs` extracts that shared shape so each new doc
generator doesn't reinvent it. New sources get a thin per-source
wrapper (~50-150 lines) instead of a from-scratch build orchestrator.

## Layout

```
llmdocs/                              # framework
├── __init__.py                       # public API: BuildConfig, build, submodules
├── build.py                          # orchestrator + BuildConfig dataclass
├── clone.py                          # git clone + version resolution + idempotency
├── prep.py                           # prep-stage helpers (sphinx_xml_via_docker, ...)
├── sections.py                       # sections.json loader + page resolver
├── topic.py                          # topic assembly + sections index
├── postprocess.py                    # wrap_sections, normalize_whitespace, ...
├── emitters/                         # emitter registry + built-in emitters
│   ├── __init__.py                   # make_registry, make_render, register
│   ├── prose_md.py                   # markdown passthrough emitter
│   └── prose_xml.py                  # docutils XML walker
├── PIPELINE.md                       # the universal pipeline shape + customization surface
├── LLM_INSTRUCTIONS.md               # recipe for an LLM adapting this to a new source
└── README.md                         # this file

llmdocs_examples/                     # working examples (underscore: Python-importable)
└── hello/                            # minimal end-to-end usage
    ├── build.py
    ├── sections.json
    ├── HELLO_VERSION
    └── README.md
```

## Usage

Each per-source generator is a sibling folder with:

```
<source>/
├── build.py             # argparse + BuildConfig + build() (~50-150 lines)
├── sections.json        # topic → source page mapping
├── <SOURCE>_VERSION     # pinned upstream version
├── README.md
└── (optional) emitters.py, postprocess.py
```

The `build.py` instantiates a `BuildConfig` and calls `llmdocs.build()`.
See `llmdocs_examples/hello/build.py` for the minimal version.

## Run the hello example

From workspace root:

```
python3 -m llmdocs.llmdocs_examples.hello.build           # build
python3 -m llmdocs.llmdocs_examples.hello.build --check   # fail-fast on output drift
python3 -m llmdocs.llmdocs_examples.hello.build --refresh # force re-clone
python3 -m llmdocs.llmdocs_examples.hello.build --json-stats
```

## Adding a new source

Read `LLM_INSTRUCTIONS.md`. The recipe is 9 steps and lands a working
generator in ~30-90 minutes once the upstream source has been
surveyed.

## Public API surface

```python
from llmdocs import (
    BuildConfig,    # dataclass — all knobs for one build
    build,          # run a build with the given config
    DEFAULT_EMITTER # "prose"
)
from llmdocs import (
    clone,          # ensure_src, resolve_version, stamp_version
    prep,           # sphinx_xml_via_docker, no_prep
    sections,       # load, resolve_pages, apply_source_overrides
    topic,          # generate_topic, read_payload
    postprocess,    # wrap_sections, normalize_whitespace, build_sections_index, ...
    emitters,       # REGISTRY, make_registry, make_render, register
)
```

Every per-source wrapper imports from this surface and nothing else.
The internal layout is free to evolve.

## Dependencies

Stdlib only. Python 3.14+. No third-party packages.

Optional external dependencies (only when the per-source wrapper
needs them):
- `docker` on PATH + `sphinxdoc/sphinx:latest` image (Sphinx prep)
- `git` on PATH (always — for clone)

## Testing the framework

The `llmdocs_examples/hello` example doubles as an end-to-end test:
it exercises clone, idempotency, page resolution, emit, postprocess,
section wrapping, SECTIONS-index insertion, --check, and --json-stats
against a public repo. If `python3 -m llmdocs.llmdocs_examples.hello.build`
succeeds, the framework core is working.

Per-module unit tests are not yet in place. Each per-source wrapper
that adopts `llmdocs` is its own regression test — it exercises the
framework's primitives against production code paths.

## Conventions

- T1 section wrapping (`<section id="slug">` blocks) is applied to
  every output by default. Strip it from your postprocess function if
  you don't want it.
- Whitespace normalization (collapse 3+ blank lines, strip trailing
  whitespace, single trailing newline) is always applied last.
- The SECTIONS index is auto-emitted when a topic has ≥ 2 H2/H3
  sections. Suppress by overriding `BuildConfig.emitter_resolver` or
  by stripping the index from your postprocess.
- Source citations use the pattern `<!-- source: <docname><ext> @ <version> -->`
  in the per-page preamble. Strip via a custom emitter if you don't
  want this.
- Output filenames are `<topic>.md` per topic, all under one
  `output_dir`.