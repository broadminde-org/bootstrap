# LLM instructions — adding a new doc source to `llmdocs`

When the user asks you to add a new upstream-doc generator (e.g.
"also build LLM-friendly docs for Kubernetes" or "do the same for
Vault"), follow this recipe. The goal is a per-source `build.py`
wrapper of ~50-150 lines plus optional emitter / postprocess modules,
leveraging `llmdocs` for everything that's already universal.

## Inputs to gather

Ask the user (or read from the workspace) for:

1. The upstream repo URL.
2. The pinned version (or a VERSION file path).
3. The docs location inside the repo:
   - a subdirectory like `docs/` or `website/content/en/docs/`
   - or the repo root if docs are at the top level
4. The source format:
   - `markdown` — `.md` files, no transformation needed
   - `rst` — `.rst` files (needs Sphinx prep stage)
   - `xml-root` — already-XML (Sphinx output, an OpenAPI spec, etc.)
   - anything else — read a sample, figure out the dispatch, write
     a small prep stage

## Recipe

### 1. Survey the source

Clone the upstream at the pinned version and inspect the docs
directory:

```
git clone --depth 1 --branch <version> <repo_url> /tmp/src
ls /tmp/src/<docs_subdir>/
head -50 /tmp/src/<docs_subdir>/<a-typical-file>
```

Identify:
- File extension (`.md`, `.rst`, `.adoc`, etc.)
- How pages link to each other (relative `.md`, full URLs, anchors)
- Whether there are callout patterns (GFM `> [!NOTE]`, RST `.. note::`,
  custom admonitions)
- Whether there are images, and whether they're useful as text labels
- Whether any page needs structured output (REST endpoints, config
  fields, install steps) rather than prose

### 2. Decide the customization surface

Fill in this table for the new source:

| Question | Answer |
|---|---|
| Prep stage needed? | yes (Sphinx) / no (already Markdown or XML) |
| Source format | `markdown` / `xml-root` / ... |
| Default emitter | `prose` / custom |
| Structured emitters needed? | list (e.g. `endpoint` for REST API topics) |
| Postprocess transforms | list (image→text, GFM callouts, link rewriting, ...) |
| `ext` | `.md` / `.rst` / ... |
| `docs_subdir` | path inside cloned repo or None |

### 3. Create the per-source wrapper

Lay it out under a sibling folder of `llmdocs/`:

```
<source>/
├── build.py             # argparse + BuildConfig + build()
├── sections.json        # topic → source page mapping
├── <SOURCE>_VERSION     # single-line version pin
├── README.md
└── (optional) emitters.py, postprocess.py
```

The `build.py` is the entry point. It instantiates `BuildConfig` and
calls `llmdocs.build(config)`. Example skeleton:

```python
#!/usr/bin/env python3
import argparse, sys
from pathlib import Path
from llmdocs import BuildConfig, build
from llmdocs import postprocess as pp

WORKSPACE = Path(__file__).resolve().parents[2]
HERE = WORKSPACE / "<source>"

def make_config(args) -> BuildConfig:
    return BuildConfig(
        name="<source>",
        repo_url="https://github.com/.../...git",
        version_file=HERE / "<SOURCE>_VERSION",
        src_dir=HERE / "_build" / "src",
        sections_file=HERE / "sections.json",
        output_dir=HERE / "ref",
        docs_subdir="<docs_subdir>",
        ext=".<ext>",
        source_format="<markdown|xml-root>",
        prep=... if needed else None,
        prep_dir=HERE / "_build" / "json" if needed else None,
        postprocess=my_postprocess if needed else None,
        extra_emitters={"endpoint": endpoint.render} if needed else None,
    )

def my_postprocess(text, version, docname):
    # compose your transforms
    text = pp.wrap_sections(text)
    text = pp.normalize_whitespace(text)
    return text

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--check", action="store_true")
    p.add_argument("--refresh", action="store_true")
    p.add_argument("--json-stats", action="store_true")
    p.add_argument("--version")
    args = p.parse_args()
    cfg = make_config(args)
    if args.check: cfg.check = True
    if args.refresh: cfg.refresh = True
    if args.json_stats: cfg.json_stats = True
    if args.version:
        cfg.version_override = args.version
        cfg.version_file.write_text(args.version + "\n")
    sys.exit(build(cfg))

if __name__ == "__main__":
    main()
```

### 4. Write `sections.json`

Map topic names to source pages. Use `source:` for explicit pages,
`include:` for globs. Pick the emitter per topic.

```json
{
  "<topic>": {
    "source": ["<docname>", ...],
    "include": ["<glob>", ...],
    "emitter": "<registry name>"
  }
}
```

Test that the resolver returns non-empty page lists — empty topics
emit a warning to stderr and skip the file. If a topic resolves to
zero pages, check the extension and the glob pattern.

### 5. Write emitters (if needed)

The default `prose` emitter works for 80% of topics. Write a custom
emitter only when the page has structured output worth extracting
(e.g. one REST endpoint per file, one config field per page, etc.).

```python
# emitters.py in your per-source wrapper
from llmdocs.emitters import register

@register("endpoint", fmt="xml-root")  # or fmt="markdown"
def render(payload, docname, version, ext=""):
    """One endpoint per source file -> one <endpoint> block per output."""
    ...
```

Then pass `extra_emitters={"endpoint": render}` in `BuildConfig`. The
framework combines it with the built-ins and exposes it under the name
you specify.

### 6. Write postprocess (if needed)

If the source needs image rewrites, GFM callout flattening, link
rewriting, or anything else, define a `postprocess` function and pass
it in `BuildConfig`. The framework always runs `wrap_sections` and
`normalize_whitespace` if your function doesn't — but you can call
those primitives yourself to control ordering.

```python
import re
from llmdocs.postprocess import wrap_sections, normalize_whitespace

def my_postprocess(text, version, docname):
    text = _convert_images_to_text(text)
    text = _convert_gfm_callouts(text)
    text = _rewrite_links(text, version, docname, base_url=...)
    text = wrap_sections(text)
    text = normalize_whitespace(text)
    return text
```

Pattern templates for common transforms (image → text label,
GFM callout flattening, link rewriting, redundant-link stripping) are
in widespread use across doc generators. When you encounter one,
lift the regex and adapt it to your source's syntax — the framework's
primitives (`wrap_sections`, `normalize_whitespace`) slot in at the
end of your postprocess chain.

### 7. Test end-to-end

Run the wrapper. Check that:
- The clone succeeds.
- Prep stage (if any) exits 0.
- Each topic resolves to ≥ 1 page.
- Output files look right (open them and skim).
- `--check` passes on a re-run.
- `--refresh` re-clones cleanly.

### 8. Add a slash command

Mirror the existing `.opencode/command/build-<source>-docs.md`
pattern in your workspace: short description, when-to-use, run
command, what it produces, multi-topic loading order reminder. Keep
the structure consistent across wrappers.

### 9. Update the workspace `.gitignore`

Add lines to ignore the per-source clone and output:

```
_build/<source>-src/   # or wherever the clone lives
ref/<source>-md/       # or wherever the output lives
```

The existing `_build/` and `ref/` patterns already cover most cases.

## What you don't need to do

The framework already handles:
- Idempotent clone + version pinning
- Topic envelope assembly (`<topic>`, `SOURCE:`, `PAGES:`)
- Section wrapping (`<section id="...">`) at H2/H3
- SECTIONS index emission when ≥ 2 sections
- Whitespace normalization
- `--check` mode (pre-build snapshot + diff)
- `--json-stats` output
- `--refresh` flag
- The SECTIONS index insertion

Don't re-implement those. If you find yourself writing a transform
that overlaps with what's already in `llmdocs.postprocess`, factor
it out as a per-source helper instead of duplicating it.

## When the framework is wrong

Three legitimate reasons to bypass `llmdocs` entirely for a source:

1. **Multiple distinct source formats.** E.g. a single upstream repo
   ships `.md` for one section, `.rst` for another, and `.adoc` for
   a third. Don't shoehorn this — write a per-source orchestrator
   that runs three separate `llmdocs` builds (or none).

2. **The output is not topic-structured.** The framework's output is
   always one `.md` per topic with a `<topic>` envelope. If the
   desired output is one file per source page, or one big file, or
   a database, `llmdocs` is the wrong tool.

3. **The source requires non-git fetches.** `llmdocs.clone` only
   handles `git clone`. For tarball + checksum sources, scrape-and-
   cache sources, or vendor copies, write a different fetcher and
   skip `llmdocs.clone`. The remaining stages still apply.

## Example: adapting the framework for a hypothetical new tool

User: "Build LLM-friendly docs for Vault (`github.com/hashicorp/vault`),
version 1.18.x, docs at `website/content/docs/`."

Step 1: Clone `https://github.com/hashicorp/vault`, look at
`website/content/docs/`. Files end in `.md`. H2 sections are dense,
images are common, GFM callouts are used.

Step 2: Decisions:
- Prep: no (already Markdown)
- Source format: `markdown`
- Default emitter: `prose` (pass-through works; no structured output
  beyond standard prose)
- Structured emitters: none
- Postprocess transforms: image → text label, GFM callout flattening
- `ext`: `.md`
- `docs_subdir`: `website/content/docs`

Step 3: Create `vault/build.py`:
- 60 lines, mostly argparse + `BuildConfig` instantiation
- Define `vault_postprocess(text, version, docname)` that calls the
  framework's `wrap_sections` + `normalize_whitespace` plus
  source-specific image-rewrite and GFM-callout passes (the
  regex strings will need tweaking to match Vault's exact syntax,
  but the overall pass shape is the same)

Step 4: `vault/sections.json`:
- Map `auth-methods`, `secrets-engines`, `api`, etc. to source pages

Step 5: Test, add slash command, update .gitignore.

Time estimate for a typical new source: 30-90 minutes once the source
is surveyed. The bulk of the time is in writing `sections.json` and
tuning any custom emitters.