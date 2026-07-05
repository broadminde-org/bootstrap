"""Generic prose emitter for already-Markdown source.

Pass-through with a configurable preamble. Lives in the framework so
per-source wrappers don't have to re-derive it.

Override per source by passing your own function in
`BuildConfig.extra_emitters["prose"]` (or register under a different
name and set `sections.json`'s `emitter:` to it).
"""

_PREAMBLE = "<!-- source: {docname}{ext} @ {version} -->\n\n"


def render(source: str, docname: str, version: str, ext: str = "") -> str:
    """Emit `source` unchanged, prefixed by a `<!-- source: ... -->` line
    so LLM context has a clear citation anchor.

    `ext` defaults to "" rather than ".md" so sources without an
    extension get a clean preamble (`README` not `README.md`). The
    framework passes `ext` through from `BuildConfig.ext` automatically.
    """
    preamble = _PREAMBLE.format(docname=docname, ext=ext, version=version)
    return preamble + source