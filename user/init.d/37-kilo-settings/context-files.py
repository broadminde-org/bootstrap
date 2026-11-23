"""Step-37 file deployment receipts and selected reverse imports (stdlib only)."""

from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import stat
import sys
import tempfile
from pathlib import Path

NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
HASH = re.compile(r"[a-f0-9]{64}\Z")
SECRET_NAME = re.compile(
    r"(^|[./_-])(secrets?|tokens?|credentials?|passwords?|private|\.env)"
    r"([./_-]|$)|\.(?:pem|key|p12|pfx)$",
    re.IGNORECASE,
)
SECRET_CONTENT = re.compile(
    rb"-----BEGIN (?:[A-Z ]*PRIVATE KEY|PGP PRIVATE KEY)|"
    rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
    rb"sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})\b|"
    rb"(?im:^\s*(?:export\s+)?[A-Z0-9_]*(?:TOKEN|PASSWORD|SECRET|API_KEY)"
    rb"\s*[:=]\s*[\"']?[^\s\"'<#]{8,})"
)
FEATURES = {
    "air": "30-scripts (canonical user/init.d/30-scripts/templates/air.toml.template)",
    "image-build": "30-scripts",
    "central-caddy": "60-caddy (canonical docs/central-caddy.md)",
    "frontend-shared-access": "98-npm-shared",
    "go-shared-access": "99-go-shared",
}
RETIRED = {
    "config/rules/privilege-escalation.md": (
        ".config/kilo/rules/privilege-escalation.md"
    ),
    "config/rules/workspace-temp.md": ".config/kilo/rules/workspace-temp.md",
    "config/commands/standards.md": ".config/kilo/commands/standards.md",
    "tmpfiles/kilo-agent-tmp.conf": ".config/user-tmpfiles.d/kilo-agent-tmp.conf",
}


def safe_path(path: Path, *, directory: bool = False) -> None:
    """Reject redirected components, including roots and broken symlinks."""
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("unsafe path")
    for parent in reversed((path, *path.parents)):
        if parent.is_symlink():
            raise ValueError("redirected path")
        if parent.exists():
            info = parent.stat()
            mode = info.st_mode
            if parent != path or directory:
                if not stat.S_ISDIR(mode):
                    raise ValueError("non-directory parent")
            elif not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError("nonregular path")
            elif stat.S_ISREG(mode) and info.st_nlink != 1:
                raise ValueError("hard-linked file")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def manifests(step: Path) -> tuple[set[str], set[str]]:
    result = []
    for name in ("default-skills.txt", "optional-skills.txt"):
        path = step / name
        safe_path(path)
        entries = set()
        for line in path.read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            if not NAME.fullmatch(line) or line in entries:
                raise ValueError("invalid or duplicate manifest entry")
            entries.add(line)
        result.append(entries)
    defaults, optionals = result
    if defaults & optionals or (defaults | optionals) & FEATURES.keys():
        raise ValueError("conflicting manifests")
    root = step / "_kilo/skills"
    safe_path(root, directory=True)
    actual = set()
    for child in root.iterdir():
        safe_path(child, directory=True)
        if not NAME.fullmatch(child.name) or not (child / "SKILL.md").is_file():
            raise ValueError("unrecognized source skill")
        actual.add(child.name)
    if actual != defaults | optionals:
        raise ValueError("source and manifests disagree")
    return defaults, optionals


def walk_error(error: OSError) -> None:
    raise error


def inventory(step: Path) -> dict[str, Path]:
    manifests(step)
    files = {}
    roots = [
        (f"config/{name}", step / f"_config/kilo/{name}")
        for name in ("agents", "commands", "rules")
    ]
    roots.append(("skills", step / "_kilo/skills"))
    for prefix, root in roots:
        safe_path(root, directory=True)
        if not root.is_dir():
            raise ValueError("canonical inventory root missing")
        for directory, dirs, names in os.walk(
            root, followlinks=False, onerror=walk_error
        ):
            for name in dirs:
                safe_path(Path(directory) / name, directory=True)
            for name in names:
                source = Path(directory) / name
                safe_path(source)
                if not source.is_file():
                    raise ValueError("nonregular source")
                key = f"{prefix}/{source.relative_to(root).as_posix()}"
                if (
                    not re.fullmatch(r"[A-Za-z0-9_./-]+", key)
                    or key in RETIRED
                    or SECRET_NAME.search(key)
                    or SECRET_CONTENT.search(key.encode())
                ):
                    raise ValueError("ineligible managed filename")
                files[key] = source
    return files


def destination(home: Path, key: str) -> Path:
    if key in RETIRED:
        return home / RETIRED[key]
    if key.startswith("config/"):
        return home / ".config/kilo" / key.removeprefix("config/")
    if key.startswith("skills/"):
        return home / ".kilo" / key
    raise ValueError("unknown managed path")


def state_root(home: Path) -> Path:
    root = home / ".local/state/bootstrap/kilo-context"
    safe_path(root, directory=True)
    if root.exists() and (
        root.stat().st_uid != os.getuid() or stat.S_IMODE(root.stat().st_mode) != 0o700
    ):
        raise ValueError("receipt directory must be private and user-owned")
    return root


def receipt_path(root: Path, key: str) -> Path:
    path = root / (digest(key.encode()) + ".json")
    safe_path(path)
    return path


def receipt(root: Path, key: str) -> dict[str, str] | None:
    path = receipt_path(root, key)
    if not path.exists():
        return None
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise ValueError("receipt must be private and user-owned")
    data = json.loads(path.read_text())
    if (
        not isinstance(data, dict)
        or set(data) != {"path", "source", "content"}
        or data["path"] != key
        or not all(
            isinstance(data[k], str) and HASH.fullmatch(data[k])
            for k in ("source", "content")
        )
        or data["source"] != data["content"]
    ):
        raise ValueError("invalid deployment receipt")
    return data


def replace(path: Path, data: bytes, mode: int) -> None:
    safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".bootstrap-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), mode)
        safe_path(path)
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def record(root: Path, key: str, source: bytes, content: bytes) -> None:
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    safe_path(root, directory=True)
    data = {"path": key, "source": digest(source), "content": digest(content)}
    replace(receipt_path(root, key), (json.dumps(data) + "\n").encode(), 0o600)


def preflight(step: Path, home: Path, files: dict[str, Path]) -> Path:
    safe_path(step, directory=True)
    safe_path(home, directory=True)
    for path in (home / ".config/kilo", home / ".kilo"):
        safe_path(path, directory=True)
    root = state_root(home)
    for key in set(files) | RETIRED.keys():
        target = destination(home, key)
        safe_path(target)
        if target.exists() and not target.is_file():
            raise ValueError("managed destination is not regular")
        receipt(root, key)
    for name in ("kilo.json", "kilo.jsonc"):
        source = step / "_config/kilo" / name
        target = home / ".config/kilo" / name
        safe_path(source)
        safe_path(target)
        if not source.is_file() or (target.exists() and not target.is_file()):
            raise ValueError("config path is not a regular file")
        if name == "kilo.json" and not isinstance(json.loads(source.read_text()), dict):
            raise ValueError("canonical JSON config must be an object")
    ignore = step.parents[2] / ".kilocodeignore"
    ignore_source = step / ".kilocodeignore"
    safe_path(ignore_source)
    if not ignore_source.is_file():
        raise ValueError("workspace ignore source is not a regular file")
    safe_path(ignore)
    if ignore.exists() and not ignore.is_file():
        raise ValueError("workspace ignore is not a regular file")
    return root


def selected_skills(step: Path, raw: str) -> set[str]:
    defaults, optionals = manifests(step)
    selected = optionals if raw == "all" else set(raw.split(",")) if raw else set()
    if not selected <= optionals or (
        raw and raw != "all" and len(raw.split(",")) != len(selected)
    ):
        raise ValueError("invalid optional selection")
    return defaults | selected


def deploy(
    step: Path,
    home: Path,
    files: dict[str, Path],
    root: Path,
    phase: str,
    optional: str,
) -> None:
    selected = selected_skills(step, optional)
    for key, source in sorted(files.items()):
        if (phase == "config") != key.startswith("config/"):
            continue
        if key.startswith("skills/") and key.split("/")[1] not in selected:
            continue
        target = destination(home, key)
        data = source.read_bytes()
        mode = 0o755 if source.stat().st_mode & 0o111 else 0o644
        if not target.exists() or target.read_bytes() != data:
            replace(target, data, mode)
        else:
            target.chmod(mode)
        safe_path(target)
        deployed = target.read_bytes()
        if deployed != data:
            raise ValueError("deployment comparison changed before receipt")
        # Record each successful comparison/write before a later phase can fail.
        # Interruption before recording deliberately leaves ownership unknown.
        record(root, key, data, deployed)
        print(f"deployed: {key}")
    if phase == "skills":
        _, optionals = manifests(step)
        for name in sorted(optionals - selected):
            installed = (home / ".kilo/skills" / name).exists()
            print(
                f"optional {name}: "
                f"{'retained, not refreshed' if installed else 'not installed'}"
            )


def retire(home: Path, root: Path) -> None:
    for key in sorted(RETIRED):
        target = destination(home, key)
        identity = receipt(root, key)
        if not target.exists():
            print(f"retired {key}: absent")
        elif identity is None or digest(target.read_bytes()) != identity["content"]:
            print(f"retired {key}: preserved (modified or ownership unknown)")
        else:
            safe_path(target)
            target.unlink()
            receipt_path(root, key).unlink()
            print(f"retired {key}: removed unchanged owned file")


def agent_frontmatter(data: bytes) -> bytes:
    # Requiring identical frontmatter also protects future permission keys.
    lines = data.splitlines(keepends=True)
    if not lines or lines[0].strip() != b"---":
        raise ValueError("agent frontmatter missing")
    for index in range(1, len(lines)):
        if lines[index].strip() == b"---":
            return b"".join(lines[: index + 1])
    raise ValueError("agent frontmatter malformed")


def reverse(
    files: dict[str, Path], home: Path, root: Path, selection: list[str], apply: bool
) -> None:
    if apply and not selection:
        raise ValueError("apply requires reviewed selection")
    if len(set(selection)) != len(selection) or any(k not in files for k in selection):
        raise ValueError("unknown, retired, or duplicate selection")
    if any(Path(key).suffix.lower() in (".json", ".jsonc") for key in selection):
        raise ValueError("JSON/JSONC is never reverse imported")
    pending = []
    for key in selection or sorted(files):
        if Path(key).suffix.lower() in (".json", ".jsonc"):
            print(f"excluded JSON/JSONC: {key}")
            continue
        source, live = files[key], destination(home, key)
        if not live.exists():
            if apply:
                raise ValueError("selected live file missing; absence is not deletion")
            print(f"missing: {key}")
            continue
        original, incoming = source.read_bytes(), live.read_bytes()
        if incoming == original:
            print(f"unchanged: {key}")
            continue
        identity = receipt(root, key)
        valid = identity is not None and identity["source"] == digest(original)
        if not apply:
            print(
                f"changed: {key} "
                f"({'baseline current' if valid else 'baseline missing/stale'})"
            )
            continue
        if (
            SECRET_NAME.search(key)
            or SECRET_CONTENT.search(incoming)
            or b"\x00" in incoming
        ):
            raise ValueError("recognizable sensitive or binary input")
        text = incoming.decode("utf-8")
        if any(ord(char) < 32 and char not in "\t\n\r" for char in text):
            raise ValueError("non-text import")
        if not valid:
            raise ValueError("deployment baseline missing or stale")
        if key.startswith("config/agents/") and agent_frontmatter(
            incoming
        ) != agent_frontmatter(original):
            raise ValueError("agent frontmatter requires manual review")
        pending.append(
            (source, original, incoming, stat.S_IMODE(source.stat().st_mode))
        )
    if not apply:
        print("JSON/JSONC excluded: deliberate canonical template edits only")
        for name, owner in FEATURES.items():
            print(f"feature-owned skill: {name} -> {owner}; not imported")
        print("Unknown files are excluded; add source and manifests deliberately.")
        return
    written = []
    try:
        for source, original, incoming, mode in pending:
            # Register before replacement: interruption can occur after the
            # atomic rename but before the replace() caller regains control.
            written.append((source, original, incoming, mode))
            replace(source, incoming, mode)
    except BaseException:
        handlers = {
            sig: signal.signal(sig, signal.SIG_IGN)
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
        }
        rollback_failed = False
        try:
            for source, original, incoming, mode in reversed(written):
                try:
                    safe_path(source)
                    current = source.read_bytes()
                    if current == original:
                        continue
                    if current != incoming:
                        raise ValueError("source changed outside this import")
                    replace(source, original, mode)
                except (OSError, ValueError):
                    # Preserve conflicts, but still restore independent files.
                    rollback_failed = True
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
        if rollback_failed:
            print(
                "ERROR: import rollback incomplete; conflicting or inaccessible "
                "source files preserved. Verify source and paired receipts "
                "before retry. No live values reported.",
                file=sys.stderr,
            )
        raise
    # Import never advances receipts; rollback pairs original source/receipts.
    print(f"imported {len(written)} reviewed files; deployment receipts unchanged")


def main() -> int:
    try:
        if sys.version_info < (3, 10):  # noqa: UP036 - external host interpreter varies
            raise ValueError("existing Python 3.10+ is required")
        action = sys.argv[1] if len(sys.argv) > 1 else ""
        selection = sys.argv[2:]
        if action not in (
            "preflight",
            "config",
            "skills",
            "retire",
            "preview",
            "apply",
        ):
            raise ValueError("unknown action")
        if os.getuid() == 0:
            raise ValueError("run as non-root")
        step, home = Path(__file__).absolute().parent, Path(os.environ["HOME"])
        safe_path(step, directory=True)
        files = inventory(step)
        root = preflight(step, home, files)
        optional = os.environ.get("KILO_OPTIONAL_SKILLS", "")
        selected_skills(step, optional)
        if selection and action not in ("preview", "apply"):
            raise ValueError("unexpected selection")
        if action in ("config", "skills"):
            deploy(step, home, files, root, action, optional)
        elif action == "retire":
            retire(home, root)
        elif action in ("preview", "apply"):

            def interrupted(_signum: int, _frame: object) -> None:
                raise KeyboardInterrupt

            previous = {
                sig: signal.signal(sig, interrupted)
                for sig in (signal.SIGTERM, signal.SIGHUP)
            }
            try:
                reverse(files, home, root, selection, action == "apply")
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
    except KeyboardInterrupt:
        print(
            "ERROR: context operation interrupted; "
            "verify source and paired receipts before retry.",
            file=sys.stderr,
        )
        return 130
    except (OSError, ValueError, KeyError):
        # Parser/filesystem messages can contain unknown names or live values.
        print(
            "ERROR: context operation rejected; check paths, manifests, "
            "private receipts, selection and non-sensitive inputs. "
            "No live values reported.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
