"""Idempotent upstream clone + version resolution.

The clone stage is the same for every doc source:
  - clone with `git clone --depth 1 --branch <version>` if missing or
    at the wrong tag
  - if the clone exists at the right tag, leave it
  - supports a post-clone hook (e.g. write RELEASE/TAG files for
    Sphinx sources that shell out to `git describe`)
"""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path
from typing import Callable

__all__ = ["ensure_src", "resolve_version", "stamp_version"]

_VERSION_RE = re.compile(r"^v\d+\.\d+\.\d+")


def resolve_version(
    *,
    version_arg: str | None,
    version_file: Path,
    fallback_files: tuple[Path, ...] = (),
    allow_resolve_latest: bool = False,
    repo_url: str | None = None,
    validation_regex: str | None = r"^v\d+\.\d+\.\d+",
) -> str:
    """Return the version string to use for this build.

    Lookup order:
      1. `version_arg` (from --version CLI flag)
      2. `version_file` (the per-source VERSION file)
      3. Each path in `fallback_files` in order
      4. If `allow_resolve_latest` and `repo_url` are provided, query
         `git ls-remote --tags --sort=-v:refname` and take the highest

    `validation_regex` (default: `^v\\d+\\.\\d+\\.\\d+`) is applied to
    the final value. Set to None to skip validation (useful for repos
    that don't tag releases with a vX.Y.Z scheme).
    """
    candidates = [version_arg.strip() if version_arg else None,
                  _read_if_exists(version_file),
                  *(_read_if_exists(p) for p in fallback_files)]
    for v in candidates:
        if v:
            _validate(v, validation_regex)
            return v

    if allow_resolve_latest and repo_url:
        v = _latest_stable_tag(repo_url)
        _validate(v, validation_regex)
        version_file.write_text(v + "\n")
        return v

    raise SystemExit(
        f"version not found: tried --version, {version_file}, "
        f"{', '.join(str(p) for p in fallback_files)}; "
        f"pass --version, create the VERSION file, or enable "
        f"allow_resolve_latest with a repo_url"
    )


def _read_if_exists(p: Path) -> str | None:
    if p and p.exists():
        v = p.read_text().strip()
        return v or None
    return None


def _validate(v: str, regex: str | None) -> None:
    if regex is None:
        return
    if not re.match(regex, v):
        raise SystemExit(f"VERSION must match {regex!r}, got: {v!r}")


def _latest_stable_tag(repo_url: str) -> str:
    """Highest semver tag in the upstream repo, by `git ls-remote --tags`."""
    out = subprocess.check_output(
        ["git", "ls-remote", "--tags", "--sort=-v:refname", repo_url],
        text=True,
    )
    candidates = []
    for line in out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        ref = parts[1]
        if ref.endswith("^{}"):
            ref = ref[:-3]
        if not ref.startswith("refs/tags/v"):
            continue
        tag = ref[len("refs/tags/"):]
        try:
            nums = tag[1:].split("-")[0].split(".")
            major = int(nums[0]); minor = int(nums[1]); patch = int(nums[2])
            if major < 1:
                continue
            candidates.append(((major, minor, patch), tag))
        except (ValueError, IndexError):
            continue
    if not candidates:
        raise SystemExit(f"no vX.Y.Z tags found in {repo_url}")
    candidates.sort(reverse=True)
    return candidates[0][1]


def _resolve_remote_ref(repo_url: str, ref: str) -> str | None:
    """Return the SHA at `ref` in `repo_url`, or None if the ref doesn't
    exist. Used for idempotency checks against branches."""
    try:
        out = subprocess.check_output(
            ["git", "ls-remote", repo_url, ref],
            text=True,
        )
    except subprocess.CalledProcessError:
        return None
    for line in out.splitlines():
        sha, remote_ref = line.split("\t", 1)
        if remote_ref.strip() in (f"refs/tags/{ref}", f"refs/heads/{ref}",
                                   ref):
            return sha
    return None


def _current_commit(src_dir: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(src_dir), "rev-parse", "HEAD"],
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None


def ensure_src(
    *,
    version: str,
    repo_url: str,
    src_dir: Path,
    force: bool = False,
    post_clone: Callable[[Path, str], None] | None = None,
    marker: str = ".git",
) -> Path:
    """Clone `repo_url` at `version` into `src_dir`. Idempotent.

    The `marker` argument controls how we detect "already cloned":
      - `.git` (default) — works for bare git clones
      - `conf.py` — for Sphinx sources cloned to a different layout
      - anything else — pick whatever file you expect at the repo root

    Idempotency is SHA-based: we compare the local clone's HEAD against
    `git ls-remote <repo_url> <version>` (works for both tags and
    branches). On a mismatch we wipe and reclone.

    `post_clone(src_dir, version)` runs after every successful clone
    (not on the idempotent skip path). Use it to write RELEASE/TAG
    stamp files, chmod binaries, etc.
    """
    if src_dir.exists() and (src_dir / marker).exists():
        remote_sha = _resolve_remote_ref(repo_url, version)
        local_sha = _current_commit(src_dir)
        if remote_sha and local_sha and remote_sha == local_sha and not force:
            return src_dir
        print(f"refreshing {src_dir} to {version}...", file=__import__("sys").stderr)
        shutil.rmtree(src_dir)

    src_dir.parent.mkdir(parents=True, exist_ok=True)
    print(f"cloning {repo_url}@{version} -> {src_dir}",
          file=__import__("sys").stderr)
    subprocess.check_call(
        ["git", "clone", "--depth", "1", "--branch", version,
         repo_url, str(src_dir)],
    )
    if post_clone:
        post_clone(src_dir, version)
    return src_dir


def stamp_version(src_dir: Path, version: str) -> None:
    """Write `RELEASE` and `TAG` files at the repo root.

    Some Sphinx `conf.py` files shell out to `git describe` to populate
    the build's `release`/`version` variables. That shell-out fails in
    minimal Sphinx Docker images (git isn't installed there). Writing
    these stamp files short-circuits the shell-out. Reused by any
    Sphinx-based source that uses `git describe` from `conf.py`.
    """
    (src_dir / "RELEASE").write_text(version + "\n")
    (src_dir / "TAG").write_text(version + "\n")