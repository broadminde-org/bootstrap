# Pipeline shape

Every `llmdocs`-based generator runs the same six-stage pipeline. The
framework provides each stage; per-source customization happens by
substituting the parts that vary.

```
+-----------+   +-------+   +---------+   +---------+   +-----------+   +---------+
| 1. CLONE  |-->|2. PREP|-->|3. RESOLVE|-->|4. EMIT  |-->|5. POSTPROCESS|-->|6. WRITE|
+-----------+   +-------+   +---------+   +---------+   +-----------+   +---------+
     |              |            |             |               |              |
  llmdocs.clone   llmdocs.prep  llmdocs.    llmdocs.        llmdocs.       llmdocs.
                                       sections    emitters          postprocess      build
```

## Stage 1 — Clone (`llmdocs.clone`)

What it does: shallow-clones the upstream repo at the pinned version
into a local directory. Idempotent — re-runs reuse the existing clone
unless the upstream SHA has moved.

Inputs:
- `repo_url` — git clone URL
- `version` — tag, branch, or any git ref (validated against
  `BuildConfig.version_validation_regex`, default `^vX.Y.Z`)
- `src_dir` — destination directory

Customization:
- `clone_post(src_dir, version)` — runs after every successful clone.
  Used by Sphinx-based sources to write `RELEASE`/`TAG` stamp files so
  `conf.py` doesn't shell out to `git describe` (which fails in the
  sphinxdoc/sphinx Docker image since git isn't installed there).
- `clone_marker` — file used to detect "already cloned". Default `.git`
  (works for bare git clones). Set to `conf.py` for Sphinx sources
  cloned to a non-standard layout.

## Stage 2 — Prep (`llmdocs.prep`)

What it does: optional intermediate transformation between clone and
emit. Default: no-op.

When you need it:
- Sphinx/RST sources → `prep.sphinx_xml_via_docker()` runs
  `sphinx-build -b xml` inside a Docker image and dumps structured XML
  into a `prep_dir`
- AsciiDoc sources → run Asciidoctor to produce DocBook/HTML, then
  walk that
- Anything else where the upstream is not directly walkable

Inputs:
- `prep_dir` — where the prep output goes (e.g. `_build/json/`)
- `prep(src_dir, prep_dir)` — callable returning exit code

If `prep` is None, `BuildConfig.docs_subdir` is used to point at the
docs directory inside the cloned repo. If both are None, the cloned
repo root is treated as the source directory.

## Stage 3 — Resolve (`llmdocs.sections`)

What it does: read `sections.json` and turn each topic entry into a
concrete list of `(docname, file_path)` pairs on disk.

`sections.json` schema:

```json
{
  "<topic>": {
    "source": ["<docname>", ...],
    "include": ["<fnmatch glob>", ...],
    "emitter": "<registry name>",
    "source_overrides": {
      "<docname>": {
        "drop_headings": ["<h2 heading text>", ...]
      }
    }
  }
}
```

- `source` — exact docname matches. Resolved to
  `<source_dir>/<docname><BuildConfig.ext>`.
- `include` — fnmatch globs relative to `<source_dir>`. Useful for
  REST-API-style sources where one topic covers a whole directory of
  per-endpoint pages.
- `emitter` — registry name for the per-topic emitter. Defaults to
  `"prose"`.
- `source_overrides.drop_headings` — H2 headings to strip from a
  page before emission. Used to remove navigation-only sections like
  link lists from README files.

The `docname` is the path relative to `source_dir` with the extension
stripped (e.g. `intro/gui`, `architecture`, `plugin-protocol/README`).
It is passed to emitters and postprocess as a stable identifier.

## Stage 4 — Emit (`llmdocs.emitters`)

What it does: dispatch each page to the configured emitter, which
turns the source payload into Markdown.

Two payload types are supported:

- `markdown` (default) — emitter receives the file contents as a
  string. Used for sources that are already Markdown or that have
  been converted to Markdown by an earlier tool.
- `xml-root` — emitter receives a parsed `xml.etree.ElementTree.Element`.
  Used for sources that come out of `sphinx-build -b xml` or any
  other docutils-XML producer.

The emitter signature is always:

```python
def render(payload, docname: str, version: str, ext: str = "") -> str:
    """Return Markdown for this page. Empty string skips the page."""
    ...
```

`ext` is forwarded from `BuildConfig.ext` so emitters can include the
file extension in citation preambles.

Built-in emitters:

| Name | Payload | Use for |
|------|---------|---------|
| `prose` (alias `prose_md`) | markdown | Markdown sources (pass-through with preamble) |
| `prose_xml` | xml-root | Sphinx XML sources (walks docutils tree) |

Per-source emitters are registered via
`BuildConfig.extra_emitters={"<name>": fn, ...}`. The framework
combines those with the built-ins and resolves `sections.json`'s
`emitter:` field through the combined registry.

## Stage 5 — Postprocess (`llmdocs.postprocess`)

What it does: apply transforms to each emitter output. The default
postprocess is just `wrap_sections` + `normalize_whitespace`. Per-source
postprocess functions compose their own transforms (image rewrites,
GFM callout flattening, link rewriting, etc.) by calling the
primitives in `llmdocs.postprocess` plus their own regex passes.

Always-on primitives (apply to every source):

- `wrap_sections(text)` — wraps H2/H3 headings + their content in
  `<section id="slug">` blocks for LLM scannability. Per
  `.opencode/proper_context_writing.md` XML wrapping rules. Slug
  collisions within a document get `-N` suffixes.
- `normalize_whitespace(text)` — strip trailing whitespace per line,
  collapse 3+ blank lines to 1, ensure a single trailing newline.
- `build_sections_index(text)` / `insert_sections_index(text, idx)` —
  emit a `SECTIONS:` bullet block right after the `PAGES:` header
  when the topic has ≥ 2 sections. The framework calls these
  automatically — emitters and postprocess don't need to.

Typical source-specific transforms:

- `_convert_images_to_text(text)` — `![alt](url)` → `[Image: alt]`.
  Drop image URLs because LLMs can't fetch bytes and the URLs are
  pure token waste.
- `_convert_gfm_callouts(text)` — `> [!NOTE]` blockquotes → `NOTE: ...`
  single-line form.
- `_rewrite_links(text, version, docname, base_url)` — relative `.md`
  links → absolute upstream URLs so the file remains valid when the
  LLM strips or relocates it.

Order is significant: link rewriting runs before section wrapping so
the section pass doesn't have to understand Markdown link syntax; GFM
callout conversion runs before whitespace cleanup so subsequent passes
don't see blockquote-prefixed content.

## Stage 6 — Write (`llmdocs.topic` + `llmdocs.build`)

What it does: assemble the per-page content into a topic file with
the standard envelope:

```
<topic>
SOURCE: [<docnames>] @ <version>
PAGES: <n>

[per-page content, separated by blank lines]

</topic>
```

A `SECTIONS:` bullet block is inserted between the header and the
first page when the topic has ≥ 2 sections.

If `BuildConfig.check=True`, the framework captures a snapshot of
the existing output directory before regenerating, then diffs each
file at the end. Returns 1 on change, 0 on match.

If `BuildConfig.json_stats=True`, the framework emits a JSON object
to stdout: `{topics, pages, chars, est_tokens, version}`.

## Customization surface summary

| Stage | Universal (framework) | Per-source customization |
|-------|-----------------------|--------------------------|
| Clone | git clone, idempotency, version validation | `clone_post`, `clone_marker`, `version_validation_regex` |
| Prep | no-op default | `prep_dir`, `prep` (e.g. `sphinx_xml_via_docker()`) |
| Resolve | `sections.json` parsing, docname/glob resolution | `ext`, `docs_subdir`, `source_overrides` |
| Emit | emitter registry + dispatcher | `extra_emitters`, per-topic `emitter:` field, `source_format` |
| Postprocess | `wrap_sections`, `normalize_whitespace`, sections index | `postprocess(text, version, docname)` — your function |
| Write | topic envelope, output writing, --check, --json-stats | output dir, topic name |

Everything in the "Universal" column is one piece of code shared by
all sources. Everything in "Per-source customization" lives in the
per-source `build.py` wrapper (a ~50-line script that instantiates
`BuildConfig` with its specific values).

See `LLM_INSTRUCTIONS.md` for the step-by-step recipe when adapting
this to a new doc source.