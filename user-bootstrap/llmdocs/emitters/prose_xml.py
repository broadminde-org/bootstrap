"""Generic prose emitter for docutils-XML source.

Walks an `xml.etree.ElementTree.Element` root (produced by
`sphinx-build -b xml` or similar) and converts it to dense Markdown.

This is a deliberately minimal emitter — just enough to handle the
80% case (generic Sphinx XML). Per-source wrappers should override
it for sources that need different semantics (e.g. emitting
`<endpoint>` blocks for REST API pages, `<step>` blocks for install
instructions, etc.).

Override by passing your own function in
`BuildConfig.extra_emitters["prose"]` or registering under another
name and setting `sections.json`'s `emitter:` field accordingly.
"""
from __future__ import annotations

import xml.etree.ElementTree as ET

__all__ = ["render", "strip_ns", "children", "text_of", "first_section",
           "section_title", "walk_sections"]


def strip_ns(tag: str) -> str:
    return tag.split("}", 1)[-1] if "}" in tag else tag


def children(el):
    """Children of `el` with `system_message` nodes filtered out."""
    return [c for c in el if strip_ns(c.tag) != "system_message"]


def text_of(el) -> str:
    """Recursively extract text from `el` with lightweight inline markup.

    Inline elements:
      - `<literal>` / `<title_reference>` -> backticks
      - `<strong>` -> **bold**
      - `<emphasis>` -> *italic*
      - everything else: descend + emit .text/.tail verbatim
    """
    if el is None:
        return ""

    parts: list[str] = []

    def walk(node):
        tag = strip_ns(node.tag)
        if tag == "literal":
            txt = (node.text or "").strip()
            if txt:
                parts.append(f"`{txt}`")
        elif tag == "title_reference":
            txt = (node.text or "").strip()
            if txt:
                parts.append(f"`{txt}`")
        elif tag == "strong":
            txt = (node.text or "").strip()
            if txt:
                parts.append(f"**{txt}**")
        elif tag == "emphasis":
            txt = (node.text or "").strip()
            if txt:
                parts.append(f"*{txt}*")
        else:
            if node.text:
                parts.append(node.text)
            for c in list(node):
                walk(c)
        if node.tail:
            parts.append(node.tail)

    walk(el)
    return " ".join("".join(parts).split())


def first_section(root):
    for c in children(root):
        if strip_ns(c.tag) == "section":
            return c
    return None


def section_title(section) -> str:
    for c in children(section):
        if strip_ns(c.tag) == "title":
            return text_of(c)
    return ""


def walk_sections(root):
    """Depth-first iteration over all `<section>` elements in `root`."""
    stack = [root]
    while stack:
        el = stack.pop(0)
        if strip_ns(el.tag) == "section":
            yield el
        kids = [c for c in children(el) if strip_ns(c.tag) == "section"]
        for k in reversed(kids):
            stack.insert(0, k)


def render(root: ET.Element, docname: str, version: str) -> str:
    """Convert a docutils XML root to LLM-friendly Markdown.

    Strategy:
      - Top-level `<section>` title becomes the page H1.
      - Nested sections become H2/H3/...
      - Paragraphs render as plain prose with inline markup preserved.
      - Definition lists -> `- term: def` bullets.
      - Bulleted / enumerated lists -> `- ...` bullets.
      - `<note>` -> `NOTE: ...` block.
      - `<warning>` -> `WARNING: ...` block.
      - `<literal_block>` -> fenced ``` code blocks.
      - `<versionmodified>` -> inline `(since vX.X.X)` parenthetical.

    This is the simple case. Per-source wrappers with structured
    output (REST endpoints, config fields, install steps) should
    provide their own emitters.
    """
    out: list[str] = []
    top = first_section(root)
    if top is None:
        return ""

    title = section_title(top)
    if title:
        out.append(f"# {title}")
        out.append("")

    _emit(top, out, depth=2)
    return "\n".join(out).rstrip() + "\n"


def _emit(section, out, depth):
    for c in children(section):
        tag = strip_ns(c.tag)
        if tag == "title":
            continue
        if tag == "section":
            t = section_title(c)
            if t:
                out.append(f"{'#' * depth} {t}")
                out.append("")
            _emit(c, out, depth + 1)
        elif tag == "paragraph":
            txt = text_of(c)
            if txt:
                out.append(txt)
                out.append("")
        elif tag == "definition_list":
            for item in children(c):
                if strip_ns(item.tag) != "definition_list_item":
                    continue
                term, defn = "", ""
                for sub in children(item):
                    stag = strip_ns(sub.tag)
                    if stag == "term":
                        term = text_of(sub)
                    elif stag == "definition":
                        defn = _collect_prose(sub)
                if term:
                    if defn:
                        out.append(f"- {term}: {defn}")
                    else:
                        out.append(f"- {term}")
            out.append("")
        elif tag in ("bullet_list", "enumerated_list"):
            for item in children(c):
                if strip_ns(item.tag) != "list_item":
                    continue
                txt = _collect_prose(item)
                if txt:
                    out.append(f"- {txt}")
            out.append("")
        elif tag == "literal_block":
            lang = c.get("language") or ""
            if lang == "default":
                lang = ""
            code = "".join(c.itertext()).rstrip()
            out.append(f"```{lang}")
            out.append(code)
            out.append("```")
            out.append("")
        elif tag == "note":
            txt = text_of(c)
            if txt:
                out.append(f"NOTE: {txt}")
                out.append("")
        elif tag == "warning":
            txt = text_of(c)
            if txt:
                out.append(f"WARNING: {txt}")
                out.append("")
        elif tag == "versionmodified":
            v = c.get("version", "")
            kind = c.get("type", "changed")
            txt = _collect_prose(c)
            if txt:
                label = {"versionadded": "Added", "versionchanged": "Changed",
                         "deprecated": "Deprecated"}.get(kind, "Note")
                if v:
                    out.append(f"({label} since v{v}) {txt}")
                else:
                    out.append(f"({label}) {txt}")
                out.append("")
        elif tag == "target":
            pass


def _collect_prose(el) -> str:
    """Concatenate paragraph-like children of `el` into one space-joined
    string. Used to flatten list items and definition bodies."""
    parts: list[str] = []
    for c in children(el):
        tag = strip_ns(c.tag)
        if tag == "paragraph":
            parts.append(text_of(c))
        elif tag in ("note", "warning"):
            parts.append(text_of(c))
    s = " ".join(p for p in parts if p)
    return " ".join(s.split())