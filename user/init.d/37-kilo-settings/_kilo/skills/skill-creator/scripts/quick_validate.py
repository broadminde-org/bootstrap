#!/usr/bin/env python3
"""Validate decoded skill metadata and explicit local resource references.

Bootstrap modification, 2026-11-23. Upstream provenance: ../local.patch.
No installation, environment creation, resource execution, or network access.
"""

import argparse
import math
import os
import re
import stat
from pathlib import Path
from urllib.parse import unquote, urlsplit

PARSER_VERSION = "6.0.3"
MAX_FILE_BYTES = 16 * 1024 * 1024
NAME_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.exit(2, "Invalid arguments; use --help for usage\n")


def validate_name(name: str) -> None:
    if not isinstance(name, str) or len(name) > 40 or not NAME_RE.fullmatch(name):
        raise ValueError(
            "Name must be 1-40 lowercase letters/digits with single hyphens"
        )


def checked_path(path: str | Path) -> Path:
    """Reject lexical traversal and symlinks, including ancestors and dangling links."""
    path = Path(path)
    if ".." in path.parts:
        raise ValueError("Parent traversal is not permitted")
    path = path.absolute()
    for part in (*reversed(path.parents), path):
        try:
            mode = part.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise ValueError("Redirected paths are not permitted")
        if part != path and not stat.S_ISDIR(mode):
            raise ValueError("Path ancestor is not a directory")
    return path


def read_regular(path: Path, max_bytes: int = MAX_FILE_BYTES) -> bytes:
    """Read at most max_bytes from a nonredirected, single-link regular file."""
    checked_path(path)
    with os.fdopen(
        os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb"
    ) as f:
        info = os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise ValueError("Input must be a regular file with one link")
        if info.st_size > max_bytes:
            raise ValueError("Input exceeds the per-file size limit")
        content = f.read(max_bytes + 1)
        if len(content) > max_bytes:
            # The descriptor may have grown after fstat; never read it unbounded.
            raise ValueError("Input exceeds the per-file size limit")
        return content


def local_reference(root: Path, base: Path, target: str) -> Path | None:
    """Admit local links within the skill; external links are not fetched."""
    target = unquote(target)
    try:
        url = urlsplit(target)
    except ValueError as error:
        # urllib can include an untrusted credential-bearing netloc in errors.
        raise ValueError("Malformed resource URL") from error
    if url.scheme in {"http", "https", "mailto"}:
        return None
    if url.scheme or url.netloc or "\\" in target:
        raise ValueError("Unsupported resource reference")
    if not url.path:
        return None
    relative = Path(url.path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Resource references must stay within the skill")
    result = checked_path(base / relative)
    if not result.is_relative_to(root) or not result.exists():
        raise ValueError("Missing or escaping local resource reference")
    if not (result.is_file() or result.is_dir()):
        raise ValueError("Resource reference is not a file or directory")
    return result


def resource_references(root: Path, source: Path, content: str) -> set[Path]:
    """Check single-line Markdown links, link definitions, and backticked resources."""
    targets = re.findall(r"\[[^\]\n]*\]\(<?([^\s)>]+)>?(?:\s+[^)\n]*)?\)", content)
    targets += re.findall(r"(?m)^\s*\[[^\]\n]+\]:\s*<?([^\s>]+)>?", content)
    targets += re.findall(r"`((?:scripts|references|assets)/[^`\n]+)`", content)
    references = set()
    for target in targets:
        reference = local_reference(root, source.parent, target)
        if reference is not None:
            references.add(reference)
    return references


def decode_metadata(text: str) -> dict:
    try:
        import yaml
    except ImportError as error:
        raise ValueError(
            "Parser unprepared: use the prepared interpreter from SKILL.md"
        ) from error
    if yaml.__version__ != PARSER_VERSION:
        raise ValueError("Parser version mismatch: prepare PyYAML==6.0.3 explicitly")

    def check_node(node: object) -> None:
        if isinstance(node, yaml.MappingNode):
            keys = set()
            for key, value in node.value:
                if key.tag != "tag:yaml.org,2002:str" or key.value == "<<":
                    raise ValueError(
                        "Metadata keys must be strings; merges are not permitted"
                    )
                if key.value in keys:
                    raise ValueError("Duplicate metadata key")
                keys.add(key.value)
                check_node(value)
        elif isinstance(node, yaml.SequenceNode):
            for value in node.value:
                check_node(value)

    try:
        if any(
            isinstance(token, (yaml.AliasToken, yaml.AnchorToken))
            for token in yaml.scan(text)
        ):
            raise ValueError("Metadata aliases/anchors are not permitted")
        node = yaml.compose(text, Loader=yaml.SafeLoader)
        check_node(node)
        metadata = yaml.safe_load(text)
    except yaml.YAMLError as error:
        # Parser exceptions contain source snippets: never echo them.
        raise ValueError("Invalid YAML metadata") from error
    if not isinstance(metadata, dict):
        # The CLI screens malformed metadata through its ValueError boundary.
        raise ValueError("Metadata must be a mapping")  # noqa: TRY004
    string_fields = {"name", "description", "license", "compatibility", "allowed-tools"}
    if set(metadata) - string_fields - {"metadata", "references"}:
        raise ValueError("Unsupported metadata field")
    for field in string_fields & metadata.keys():
        if not isinstance(metadata[field], str) or not metadata[field].strip():
            raise ValueError("Metadata text fields must be nonempty strings")
    if not {"name", "description"} <= metadata.keys():
        raise ValueError("Metadata requires name and description")
    if "metadata" in metadata and not isinstance(metadata["metadata"], dict):
        raise ValueError("Optional metadata must be a mapping")

    def check_value(value: object) -> None:
        if isinstance(value, dict):
            for child in value.values():
                check_value(child)
        elif isinstance(value, list):
            for child in value:
                check_value(child)
        elif value is not None and not isinstance(value, (str, bool, int, float)):
            raise ValueError("Optional metadata values must have JSON-compatible types")
        elif isinstance(value, float) and not math.isfinite(value):
            raise ValueError("Optional metadata numbers must be finite")

    check_value(metadata.get("metadata", {}))
    if "references" in metadata:
        refs = metadata["references"]
        if (
            not isinstance(refs, list)
            or any(not isinstance(r, str) or not r for r in refs)
            or len(refs) != len(set(refs))
        ):
            raise ValueError("References must be a unique list of nonempty strings")
    return metadata


def inspect_skill(
    skill_path: str | Path, content: str | None = None
) -> tuple[Path, set[Path]]:
    root = checked_path(skill_path)
    if not root.is_dir():
        raise ValueError("Skill directory not found")
    validate_name(root.name)
    source = root / "SKILL.md"
    if content is None:
        content = read_regular(source).decode("utf-8")
    lines = content.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("Missing YAML frontmatter delimiter")
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        raise ValueError("Missing closing frontmatter delimiter") from error
    metadata = decode_metadata("\n".join(lines[1:end]))
    validate_name(metadata["name"])
    if metadata["name"] != root.name:
        raise ValueError("Metadata name must match directory name")
    body = "\n".join(lines[end + 1 :])
    if not body.strip():
        raise ValueError("Skill instructions are empty")
    references = resource_references(root, source, body)
    for target in metadata.get("references", []):
        reference = local_reference(root, root, target)
        if reference is None:
            raise ValueError("Metadata references must be local resources")
        references.add(reference)
    return root, references


def validate_skill(skill_path: str | Path) -> tuple[bool, str]:
    try:
        inspect_skill(skill_path)
    except (OSError, UnicodeError):
        return False, "Skill input cannot be read safely as UTF-8"
    except ValueError as error:
        return False, str(error)
    return True, "Skill metadata and explicit resource references are valid"


def main() -> None:
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("skill_directory")
    args = parser.parse_args()
    valid, message = validate_skill(args.skill_directory)
    print(message)
    raise SystemExit(0 if valid else 1)


if __name__ == "__main__":
    main()
