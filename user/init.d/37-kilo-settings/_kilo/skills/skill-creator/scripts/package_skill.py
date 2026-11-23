#!/usr/bin/env python3
"""Package only a reviewed hash inventory, staging before no-clobber publication.

Bootstrap modification, 2026-11-23. Upstream provenance: ../local.patch.
"""

import hashlib
import json
import os
import re
import stat
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from quick_validate import (
    SafeArgumentParser,
    checked_path,
    inspect_skill,
    read_regular,
    resource_references,
    validate_name,
)

DENIED_PARTS = {
    "node_modules",
    "__pycache__",
    "dist",
    "build",
    "target",
    "coverage",
    "secrets",
    "credentials",
    "private",
    "local",
    "tmp",
    "temp",
    "venv",
}
DENIED_SUFFIXES = {
    ".zip",
    ".skill",
    ".pyc",
    ".pyo",
    ".log",
    ".pem",
    ".key",
    ".p12",
    ".pfx",
    ".sqlite",
    ".db",
    ".bak",
    ".swp",
    ".tar",
    ".gz",
    ".tgz",
}
SECRET_RE = re.compile(
    rb"-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----"
    rb"|(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"
    rb"|AKIA[0-9A-Z]{16}"
    rb"|(?i:(?:password|passwd|token|secret|api[_-]?key)\s*[:=]\s*"
    rb"[\"']?(?!\$|<|TODO|placeholder|example|changeme)[A-Za-z0-9_/+.-]{8,})"
)


def inventory_pairs(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate inventory key")
        result[key] = value
    return result


def walk_error(error: OSError) -> None:
    raise error


def reviewed_files(root: Path, inventory: Path) -> dict[str, bytes]:
    """Bind approval to exact bytes; do not recursively select files."""
    data = json.loads(read_regular(inventory), object_pairs_hook=inventory_pairs)
    if not isinstance(data, dict) or set(data) != {"files"}:
        raise ValueError("Inventory must contain only files")
    entries = data["files"]
    if not isinstance(entries, list) or not entries:
        raise ValueError("Inventory files must be a nonempty list")
    payload = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
            raise ValueError("Each inventory entry requires path and sha256 only")
        name, digest = entry["path"], entry["sha256"]
        if not isinstance(name, str) or not isinstance(digest, str):
            # Keep malformed inventory failures in the screened ValueError boundary.
            raise ValueError("Inventory paths and hashes must be strings")  # noqa: TRY004
        relative = PurePosixPath(name)
        if (
            not name
            or relative.is_absolute()
            or relative.as_posix() != name
            or ".." in relative.parts
            or "\\" in name
            or any(ord(c) < 32 or ord(c) == 127 for c in name)
            or name in payload
        ):
            raise ValueError("Invalid or duplicate inventory path")
        if SECRET_RE.search(name.encode("utf-8")):
            raise ValueError("Recognizable sensitive input name refused")
        lowered = [part.lower() for part in relative.parts]
        if name != "local.patch" and (
            any(part.startswith(".") or part in DENIED_PARTS for part in lowered)
            or any(
                re.search(
                    r"(?:^|[-_.])(secrets?|credentials?|tokens?|passwords?|generated|local)(?:[-_.]|$)",
                    part,
                )
                for part in lowered
            )
            or relative.suffix.lower() in DENIED_SUFFIXES
            or any(part.startswith(("id_rsa", "id_ed25519")) for part in lowered)
        ):
            raise ValueError("Inventory contains secret, generated, or local inputs")
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError("Inventory requires lowercase SHA-256 hashes")
        content = read_regular(root / name)
        if hashlib.sha256(content).hexdigest() != digest:
            raise ValueError("Reviewed input changed")
        if SECRET_RE.search(content):
            raise ValueError("Recognizable sensitive content refused")
        payload[name] = content
    if "SKILL.md" not in payload:
        raise ValueError("Inventory must include SKILL.md")
    # Preserve existing redistribution/provenance notices, never silently omit them.
    for notice in ("LICENSE", "LICENSE.txt", "NOTICE", "local.patch"):
        if os.path.lexists(root / notice) and notice not in payload:
            raise ValueError("Inventory omits existing license or provenance notice")
    return payload


def package_skill(
    skill_path: str | Path,
    output_dir: str | Path,
    inventory_path: str | Path,
) -> Path | None:
    try:
        root = checked_path(skill_path)
        validate_name(root.name)
        if not root.is_dir():
            raise ValueError("Skill directory not found")
        output = checked_path(output_dir)
        inventory = checked_path(inventory_path)
        if not output.is_dir():
            raise ValueError("Output directory must already exist")
        if output.is_relative_to(root) or inventory.is_relative_to(root):
            raise ValueError("Output and review inventory must be outside the skill")
        archive = checked_path(output / f"{root.name}.zip")
        if os.path.lexists(archive):
            raise ValueError("Archive destination exists; replacement is not supported")
        # Reject links/special files anywhere in the source tree, even if unselected.
        for directory, dirs, files in os.walk(
            root, followlinks=False, onerror=walk_error
        ):
            for name in dirs + files:
                path = checked_path(Path(directory) / name)
                info = path.lstat()
                if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                    raise ValueError("Source tree contains a special file")
                if stat.S_ISREG(info.st_mode) and info.st_nlink != 1:
                    raise ValueError("Source tree contains a hardlink")
        payload = reviewed_files(root, inventory)
        _, references = inspect_skill(root, payload["SKILL.md"].decode("utf-8"))
        for name, content in payload.items():
            if Path(name).suffix.lower() == ".md":
                references |= resource_references(
                    root, root / name, content.decode("utf-8")
                )
        included = {root / name for name in payload}
        for reference in references:
            if reference not in included and not (
                reference.is_dir()
                and any(p.is_relative_to(reference) for p in included)
            ):
                raise ValueError("Inventory omits a referenced resource")
    except (OSError, ValueError, UnicodeError):
        print("Packaging refused: review metadata, inventory, inputs, and destination")
        return None

    # The ZIP uses the already screened bytes, not a second read of mutable sources.
    published_identity = None
    try:
        with tempfile.TemporaryDirectory(prefix="skill-package-", dir=output) as stage:
            staged = Path(stage) / "package.tmp"
            with zipfile.ZipFile(staged, "x", zipfile.ZIP_DEFLATED) as zipf:
                for name, content in sorted(payload.items()):
                    zipf.writestr(f"{root.name}/{name}", content)
            with zipfile.ZipFile(staged) as zipf:
                if zipf.testzip() is not None:
                    raise ValueError("Staged archive integrity check failed")
            staged.chmod(0o600)
            checked_path(output)
            info = staged.stat()
            published_identity = (info.st_dev, info.st_ino)
            # Same-filesystem link publishes atomically and refuses any existing leaf.
            os.link(staged, archive, follow_symlinks=False)
        print("Packaged reviewed inventory successfully")
        return archive
    except BaseException as error:
        # A cleanup failure after publication must not leave a success-looking ZIP.
        if published_identity is not None:
            try:
                checked_path(archive)
                info = archive.lstat()
                if (info.st_dev, info.st_ino) == published_identity:
                    archive.unlink()
            except FileNotFoundError:
                pass  # Publication did not happen, or the owned output is absent.
            except (OSError, ValueError):
                print("Packaging failed; owned output cleanup could not be confirmed")
                if isinstance(error, (OSError, ValueError, RuntimeError)):
                    return None
                raise
        if isinstance(error, (OSError, ValueError, zipfile.BadZipFile, RuntimeError)):
            print("Packaging failed; no archive was published")
            return None
        raise


def main() -> None:
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("skill_directory")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--inventory", required=True, help="Reviewed external JSON inventory"
    )
    args = parser.parse_args()
    result = package_skill(args.skill_directory, args.output_dir, args.inventory)
    raise SystemExit(0 if result else 1)


if __name__ == "__main__":
    main()
