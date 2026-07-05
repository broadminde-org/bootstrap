"""Build orchestrator.

The orchestrator owns the universal pipeline shape:

    1. Resolve version (--version flag, VERSION file, fallback files,
       or auto-resolve from upstream tags)
    2. Clone upstream at the pinned tag (idempotent)
    3. Run prep stage if configured (e.g. sphinx-build via Docker)
    4. Load sections.json and loop over topics:
         a. resolve source pages for the topic
         b. for each page, read payload, apply source_overrides,
            dispatch to the configured emitter
         c. run the source-specific postprocess function
         d. concatenate into a <topic>...</topic> block with
            SOURCE/PAGES header + optional SECTIONS index
         e. write to output_dir/<topic>.md
    5. If check=True, diff against pre-build snapshot and return 1 on
       change. Otherwise return 0.

Per-source customization happens entirely through `BuildConfig`:
  - `repo_url` + `version_file` — what to clone
  - `prep` — optional intermediate transform (sphinx, asciidoctor, ...)
  - `docs_subdir` + `ext` — where source files live and what extension
    they have
  - `source_format` — "markdown" (text payload) or "xml-root"
    (parsed XML element payload)
  - `postprocess` — source-specific transforms applied per page
  - `extra_emitters` — additional emitters registered for this run
"""
from __future__ import annotations

import dataclasses
import json
import sys
from pathlib import Path
from typing import Callable

from . import clone
from . import sections as sections_mod
from . import topic as topic_mod
from . import postprocess as pp
from . import emitters as emitters_mod

__all__ = ["build", "BuildConfig", "DEFAULT_EMITTER"]

DEFAULT_EMITTER = sections_mod.DEFAULT_EMITTER


@dataclasses.dataclass
class BuildConfig:
    """All knobs needed to build one upstream source's docs.

    A per-source wrapper script instantiates this with its specific
    settings and calls `llmdocs.build(config)`. Fields with defaults
    are optional; required fields have no default.
    """
    name: str
    repo_url: str
    version_file: Path
    src_dir: Path
    sections_file: Path
    output_dir: Path

    docs_subdir: str | None = None
    ext: str = ".md"
    source_format: str = "markdown"

    prep_dir: Path | None = None
    prep: Callable[[Path, Path], int] | None = None

    postprocess: Callable[[str, str, str], str] | None = None

    version_file_fallbacks: tuple[Path, ...] = ()
    allow_resolve_latest: bool = False

    extra_emitters: dict | None = None
    emitter_resolver: Callable[[dict], str] | None = None

    clone_marker: str = ".git"
    clone_post: Callable[[Path, str], None] | None = None

    check: bool = False
    json_stats: bool = False
    refresh: bool = False

    version_override: str | None = None
    version_validation_regex: str | None = r"^v\d+\.\d+\.\d+"


def build(config: BuildConfig) -> int:
    """Run a full build with the given config. Returns the process exit
    code (0 = success, 1 = --check failure, >1 = error)."""
    version = clone.resolve_version(
        version_arg=config.version_override,
        version_file=config.version_file,
        fallback_files=config.version_file_fallbacks,
        allow_resolve_latest=config.allow_resolve_latest,
        repo_url=config.repo_url,
        validation_regex=config.version_validation_regex,
    )
    print(f"VERSION: {version}", file=sys.stderr)

    src_dir = clone.ensure_src(
        version=version,
        repo_url=config.repo_url,
        src_dir=config.src_dir,
        marker=config.clone_marker,
        post_clone=config.clone_post,
        force=config.refresh,
    )

    if config.prep is not None:
        if config.prep_dir is None:
            raise SystemExit("prep configured but prep_dir is None")
        rc = config.prep(src_dir, config.prep_dir)
        if rc != 0:
            print(f"prep stage failed with exit code {rc}", file=sys.stderr)
            return rc
        source_dir = config.prep_dir
    elif config.docs_subdir:
        source_dir = src_dir / config.docs_subdir
    else:
        source_dir = src_dir

    if not source_dir.is_dir():
        print(f"source dir not found: {source_dir}", file=sys.stderr)
        return 1

    sections = sections_mod.load(config.sections_file)

    postprocess = config.postprocess or _default_postprocess
    emitter_resolver = config.emitter_resolver or _default_emitter_resolver
    registry = emitters_mod.make_registry(config.extra_emitters)
    render = emitters_mod.make_render(registry)

    # Pre-build snapshot for --check. We write new files first, then
    # diff against the pre-build state.
    pre_existing: dict[str, str] = {}
    if config.check and config.output_dir.exists():
        for f in config.output_dir.glob("*.md"):
            pre_existing[f.name] = f.read_text()

    config.output_dir.mkdir(parents=True, exist_ok=True)

    stats = {"topics": 0, "pages": 0, "chars": 0, "version": version}

    for topic_name, topic_cfg in sections.items():
        path = topic_mod.generate_topic(
            topic_name=topic_name,
            topic_cfg=topic_cfg,
            source_dir=source_dir,
            output_dir=config.output_dir,
            ext=config.ext,
            source_format=config.source_format,
            version=version,
            emitter_for_topic=emitter_resolver,
            render=render,
            postprocess=postprocess,
            stats=stats,
        )
        if path:
            print(f"  + {path.name}", file=sys.stderr)

    stats["est_tokens"] = stats["chars"] // 4

    if config.check:
        changed, new_files = [], []
        for f in config.output_dir.glob("*.md"):
            old = pre_existing.get(f.name)
            if old is None:
                new_files.append(f.name)
            elif old != f.read_text():
                changed.append(f.name)
        if changed or new_files:
            print(f"check failed: {len(changed)} changed, "
                  f"{len(new_files)} new", file=sys.stderr)
            for f in changed:
                print(f"  CHANGED: {f}", file=sys.stderr)
            for f in new_files:
                print(f"  NEW: {f}", file=sys.stderr)
            return 1
        print("check: output matches existing files", file=sys.stderr)
        return 0

    if config.json_stats:
        print(json.dumps(stats))
    else:
        print(file=sys.stderr)
        print(f"Generated {stats['topics']} topic files "
              f"({stats['pages']} pages, ~{stats['est_tokens']:,} est tokens) "
              f"from {config.name} {version}", file=sys.stderr)

    return 0


def _default_postprocess(text: str, version: str, docname: str) -> str:
    """Default postprocess: section wrapping + whitespace. Use this when
    the source is already clean Markdown (or already-converted XML→MD)
    and you don't need image rewrites, GFM callout flattening, or link
    rewriting. Override per source as needed."""
    text = pp.wrap_sections(text)
    text = pp.normalize_whitespace(text)
    return text


def _default_emitter_resolver(topic_cfg: dict) -> str:
    return topic_cfg.get("emitter", DEFAULT_EMITTER)