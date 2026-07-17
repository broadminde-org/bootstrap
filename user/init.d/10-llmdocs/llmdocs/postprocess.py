"""Base postprocess primitives shared across all doc sources.

Every doc source runs the section-wrapping transform (T1) plus
whitespace normalization at the end of its pipeline. Sources that
need additional transforms (image rewrites, GFM callout flattening,
link rewriting, etc.) compose their own postprocess function by
calling these primitives + their own regex passes and passing the
combined function to `llmdocs.build()` via `BuildConfig.postprocess`.

This module is intentionally source-agnostic: no assumptions about
RST, Sphinx, GitHub URLs, image syntax, etc.
"""
import re

__all__ = ["wrap_sections", "normalize_whitespace", "_HEADING_RE",
           "_SECTION_OPEN_RE", "slugify"]

_HEADING_RE = re.compile(r"^(#+)\s+(.*)$")

_SECTION_OPEN_RE = re.compile(
    r'<section id="([^"]+)">\s*\n(##\s+[^\n]+)'
)

_SECTION_CLOSE_RE = re.compile(r"</section>")


def slugify(heading: str, seen: set[str]) -> str:
    """Derive a URL-safe slug from a heading. Strips backticks, lowercases,
    collapses non-alphanumeric runs to single dashes. Appends `-N` for
    in-page collisions."""
    h = re.sub(r"`([^`]+)`", r"\1", heading)
    h = h.lower()
    h = re.sub(r"[^a-z0-9]+", "-", h).strip("-")
    base = h or "section"
    slug = base
    n = 1
    while slug in seen:
        n += 1
        slug = f"{base}-{n}"
    seen.add(slug)
    return slug


def wrap_sections(text: str) -> str:
    """Wrap each H2 and H3 heading + its body in `<section id="slug">` blocks.

    H1 stays outside any `<section>` (the topic wrapper already anchors the
    page). H3 nests inside its parent H2; H4+ are left unwrapped. Slug
    collisions within a document get `-N` suffixes.
    """
    lines = text.split("\n")
    out: list[str] = []
    stack: list[tuple[int, str]] = []
    seen: set[str] = set()

    for line in lines:
        m = _HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            heading = m.group(2).strip()
            while stack and stack[-1][0] >= level:
                out.append("</section>")
                stack.pop()
            if level >= 2:
                slug = slugify(heading, seen)
                out.append(f'<section id="{slug}">')
                stack.append((level, slug))
            out.append(line)
        else:
            out.append(line)

    while stack:
        out.append("</section>")
        stack.pop()

    return "\n".join(out)


def normalize_whitespace(text: str) -> str:
    """Strip trailing whitespace per line, collapse 3+ blank lines to 1,
    ensure a single trailing newline. Last step in every postprocess
    pipeline."""
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = "\n".join(line.rstrip() for line in text.splitlines())
    text = text.rstrip() + "\n"
    return text


def build_sections_index(topic_text: str, min_sections: int = 2) -> str:
    """Scan a topic's body for `<section id="...">` + H2 pairs and return a
    `SECTIONS:` bullet block. Returns "" when fewer than `min_sections`
    sections exist (the index is overhead for short topics).

    The H2 heading text is taken from the line immediately following the
    `<section>` open tag. Backticks in headings are stripped from the
    label so the index reads cleanly (the slug anchor still resolves to
    the right section).
    """
    matches = _SECTION_OPEN_RE.findall(topic_text)
    if len(matches) < min_sections:
        return ""
    lines = ["SECTIONS:"]
    for slug, heading in matches:
        title = re.sub(r"`([^`]+)`", r"\1", heading[2:].strip()).strip()
        lines.append(f"- {title}  (#{slug})")
    return "\n".join(lines) + "\n"


def insert_sections_index(topic_text: str, sections_index: str) -> str:
    """Insert a SECTIONS block right after the `PAGES: N` header line."""
    lines = topic_text.split("\n")
    out: list[str] = []
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted and line.startswith("PAGES:"):
            out.append("")
            out.append(sections_index.rstrip())
            out.append("")
            inserted = True
    return "\n".join(out)