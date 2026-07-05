"""sections.json loader + page resolver.

A sections.json maps topic names to upstream source pages:

    {
      "<topic>": {
        "source":  ["<docname>", ...],
        "include": ["<glob>", ...],
        "emitter": "<name>",
        "source_overrides": {
          "<docname>": {"drop_headings": ["..."]}
        }
      }
    }

`source` entries are exact docname matches (resolved to `<docs_subdir>/<docname>.<ext>`).
`include` entries are fnmatch globs relative to `<docs_subdir>/`.
`emitter` is the registry name; defaults to "prose" when omitted.
`source_overrides` applies page-level edits before emission (currently
just `drop_headings` — list of H2 headings to strip, useful for
README-style navigation blocks).

This module is format-agnostic: it does not assume Markdown vs XML vs
anything else. The page list is returned as `(docname, file_path)`
pairs and the file extension is whatever was configured on the call.
"""
from __future__ import annotations

import fnmatch
import json
import re
from pathlib import Path

__all__ = ["load", "resolve_pages", "apply_source_overrides", "DEFAULT_EMITTER"]

DEFAULT_EMITTER = "prose"


def load(sections_file: Path) -> dict:
    with sections_file.open() as f:
        return json.load(f)


def resolve_pages(topic_cfg: dict, source_dir: Path, ext: str) -> list[tuple[str, Path]]:
    """Return `[(docname, file_path), ...]` for a single topic.

    `docname` is the path-relative-to-source_dir with the extension
    stripped (e.g. `intro/gui`, `architecture`, `plugin-protocol/README`).
    `file_path` is an absolute Path on disk.

    `source_dir` is the directory the docs live in (either the upstream
    `src/<docs_subdir>` or the prep output, e.g. `_build/json/`).
    `ext` is the file extension to look for, with leading dot (e.g.
    `.md`, `.xml`, `.rst`).
    """
    pages: list[tuple[str, Path]] = []
    seen: set[str] = set()

    for name in topic_cfg.get("source", []):
        path = source_dir / f"{name}{ext}"
        if path.exists() and name not in seen:
            pages.append((name, path))
            seen.add(name)

    for pattern in topic_cfg.get("include", []):
        glob = f"{pattern}{ext}"
        for path in sorted(source_dir.glob(glob)):
            if not path.is_file():
                continue
            docname = path.relative_to(source_dir).with_suffix("").as_posix()
            if docname not in seen:
                pages.append((docname, path))
                seen.add(docname)

    return pages


def apply_source_overrides(source: str, override: dict) -> str:
    """Apply per-source-page edits before emission.

    Currently supports `drop_headings`: list of H2 headings (and all
    content until the next H2 of equal-or-higher level) to strip from
    the page. Used to remove navigation-only sections like link lists
    from README files.

    The override dict comes from `sections.json:<topic>.source_overrides.<docname>`.
    """
    drop = override.get("drop_headings") or []
    if not drop:
        return source

    lines = source.split("\n")
    out: list[str] = []
    skipping = False
    skip_at_level: int | None = None

    for line in lines:
        m = re.match(r"^(#+)\s+(.*)$", line)
        if m:
            level = len(m.group(1))
            heading = m.group(2).strip()
            if skipping:
                if level <= skip_at_level:
                    skipping = False
                    skip_at_level = None
                else:
                    continue
            if level == 2 and heading in drop:
                skipping = True
                skip_at_level = 2
                continue
        if not skipping:
            out.append(line)

    return "\n".join(out)