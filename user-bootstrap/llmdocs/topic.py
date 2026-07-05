"""Topic assembly: per-topic header, per-page content, SECTIONS index.

A "topic" is one output `.md` file. It aggregates zero or more source
pages (resolved by `sections.resolve_pages`), runs each through the
configured emitter, applies source_overrides + postprocess, wraps the
whole thing in a `<topic>` XML block with a `SOURCE:` / `PAGES:` header,
and optionally emits a `SECTIONS:` index for fast self-locating.
"""
from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Callable

from . import sections as sections_mod
from . import postprocess as pp

__all__ = ["generate_topic", "read_payload"]


SourceFormat = str  # "markdown" | "xml-root"


def read_payload(path: Path, source_format: SourceFormat):
    """Load a source page into the payload type the emitter expects.

    - `markdown` (default): returns the file contents as a string.
    - `xml-root`: parses the file as XML and returns the root element.

    Emitters declare the format they expect by being registered with a
    specific name; the build orchestrator passes the format hint
    through `BuildConfig.source_format`.
    """
    if source_format == "markdown":
        return path.read_text(encoding="utf-8")
    if source_format == "xml-root":
        return ET.parse(path).getroot()
    raise ValueError(f"unknown source_format: {source_format!r}")


def generate_topic(
    *,
    topic_name: str,
    topic_cfg: dict,
    source_dir: Path,
    output_dir: Path,
    ext: str,
    source_format: SourceFormat,
    version: str,
    emitter_for_topic: Callable[[dict], str],
    render: Callable[..., str],
    postprocess: Callable[[str, str, str], str],
    stats: dict,
) -> Path | None:
    """Build one topic file. Returns the output path, or None if zero
    pages resolved.

    `emitter_for_topic(topic_cfg)` returns the emitter name to use for
    this topic (allows per-topic emitter overrides via `topic_cfg["emitter"]`).
    `render(emitter_name, payload, docname, version, ext=...)` is the
    emitter dispatcher. `ext` is forwarded so emitters like `prose_md`
    can include the right suffix in their citation preamble.
    `postprocess(text, version, docname)` is the per-source postprocess
    function (typically composed of `llmdocs.postprocess.wrap_sections`
    + source-specific transforms + `normalize_whitespace`).
    """
    pages = sections_mod.resolve_pages(topic_cfg, source_dir, ext)
    if not pages:
        print(f"warning: topic {topic_name!r} resolved to 0 pages",
              file=__import__("sys").stderr)
        return None

    chunks: list[str] = [
        f"<{topic_name}>",
        f"SOURCE: {topic_cfg.get('source', [])} @ {version}",
        f"PAGES: {len(pages)}",
        "",
    ]

    emitter = emitter_for_topic(topic_cfg)
    overrides = topic_cfg.get("source_overrides", {})

    for docname, file_path in pages:
        try:
            payload = read_payload(file_path, source_format)
        except (OSError, ET.ParseError) as e:
            print(f"warning: read error in {file_path}: {e}",
                  file=__import__("sys").stderr)
            continue

        if source_format == "markdown" and docname in overrides:
            payload = sections_mod.apply_source_overrides(payload, overrides[docname])

        body = render(emitter, payload, docname, version, ext=ext)
        if not body:
            continue
        processed = postprocess(body, version, docname)
        chunks.append(processed.rstrip())
        chunks.append("")

    chunks.append(f"</{topic_name}>")
    topic_text = "\n".join(chunks).rstrip() + "\n"

    # Insert SECTIONS index right after the PAGES: header. Suppressed
    # when fewer than 2 sections exist (the index is overhead for short
    # topics).
    idx = pp.build_sections_index(topic_text)
    if idx:
        topic_text = pp.insert_sections_index(topic_text, idx)

    out_path = output_dir / f"{topic_name}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(topic_text, encoding="utf-8")

    stats["topics"] += 1
    stats["pages"] += len(pages)
    stats["chars"] += out_path.stat().st_size
    return out_path