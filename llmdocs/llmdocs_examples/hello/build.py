#!/usr/bin/env python3
"""Minimal `llmdocs` wrapper example.

Builds LLM-friendly Markdown from a public repo using only the
framework defaults. ~30 lines, stdlib-only.

From workspace root:
    python3 -m llmdocs.examples.hello.build

Add `--check`, `--refresh`, `--json-stats` for the standard CI
flags.
"""
import argparse
import sys
from pathlib import Path

from llmdocs import BuildConfig, build


WORKSPACE = Path(__file__).resolve().parents[3]
HERE = WORKSPACE / "llmdocs" / "llmdocs_examples" / "hello"


def make_config() -> BuildConfig:
    return BuildConfig(
        name="hello",
        repo_url="https://github.com/octocat/Hello-World.git",
        version_file=HERE / "HELLO_VERSION",
        src_dir=HERE / "_build" / "src",
        sections_file=HERE / "sections.json",
        output_dir=HERE / "ref",
        # The octocat/Hello-World repo has a single "README" file at the
        # root with no extension, so:
        #   - docs_subdir=None reads from src_dir (no docs/ subdir)
        #   - ext="" matches files with no extension
        #   - sections.json uses include:["*"] to glob everything
        # The repo only has a master branch (no vX.Y.Z tags), so relax
        # version validation.
        ext="",
        version_validation_regex=None,
    )


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--check", action="store_true",
                   help="Exit 1 if output would change")
    p.add_argument("--refresh", action="store_true",
                   help="Force re-clone")
    p.add_argument("--json-stats", action="store_true",
                   help="Emit stats JSON to stdout")
    p.add_argument("--version", help="Override version (writes to VERSION file)")
    args = p.parse_args()

    cfg = make_config()
    if args.check:
        cfg.check = True
    if args.refresh:
        cfg.refresh = True
    if args.json_stats:
        cfg.json_stats = True
    if args.version:
        cfg.version_override = args.version.strip()
        cfg.version_file.write_text(args.version.strip() + "\n")

    return build(cfg)


if __name__ == "__main__":
    sys.exit(main())