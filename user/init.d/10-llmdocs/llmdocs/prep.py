"""Source preparation stage.

Between `git clone` and per-page emission, some doc sources need an
intermediate transformation step:

  - Sphinx/RST sources → run `sphinx-build -b xml` to produce
    structured XML the emitters can walk
  - AsciiDoc sources → run Asciidoctor to produce DocBook or HTML,
    then walk that
  - Markdown sources → no prep (skip this stage entirely)

A prep stage is a callable `(src_dir, prep_dir) -> int` that returns
a subprocess exit code (0 = success). It runs once before the per-topic
loop. If omitted, the framework reads source files directly from
`src_dir/<docs_subdir>`.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

__all__ = ["PrepStage", "no_prep", "sphinx_xml_via_docker"]

PrepStage = Callable[[Path, Path], int]


def no_prep(src_dir: Path, prep_dir: Path) -> int:
    """Default no-op prep. Returns 0."""
    return 0


def sphinx_xml_via_docker(
    *,
    image: str = "sphinxdoc/sphinx:latest",
    workdir: str = "/docs",
    src_mount: str = "/docs",
    out_mount: str = "/out",
    extra_args: tuple[str, ...] = ("-q", "-E"),
) -> PrepStage:
    """Build a prep stage that runs `sphinx-build -b xml` inside a
    Sphinx Docker image.

    Returns a closure suitable for `BuildConfig.prep`. The closure:
      1. Runs `docker image inspect <image>` and pulls if missing
      2. Mounts `src_dir` and `prep_dir` into the image
      3. Invokes `sphinx-build -b xml <extra_args> . <prep_dir>`

    Use this verbatim for any Sphinx-based source — no need to re-derive
    the Docker invocation.
    """
    import shutil
    import subprocess
    import sys

    def _run(src_dir: Path, prep_dir: Path) -> int:
        if not shutil.which("docker"):
            print("error: docker not found on PATH", file=sys.stderr)
            return 127

        if subprocess.call(
            ["docker", "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) != 0:
            print(f"pulling {image}...", file=sys.stderr)
            if subprocess.call(["docker", "pull", image]) != 0:
                return 1

        src_abs = src_dir.resolve()
        out_abs = prep_dir.resolve()
        out_abs.mkdir(parents=True, exist_ok=True)

        cmd = [
            "docker", "run", "--rm",
            "-v", f"{src_abs}:{src_mount}",
            "-v", f"{out_abs}:{out_mount}",
            "-w", workdir,
            image,
            "sphinx-build", "-b", "xml", *extra_args,
            "-D", "suppress_warnings=ref.option",
            workdir, out_mount,
        ]
        print(f"+ {' '.join(cmd)}", file=sys.stderr)
        return subprocess.call(cmd)

    return _run