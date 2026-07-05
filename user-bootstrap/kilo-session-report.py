"""Analyze Kilo session export JSON for context bloat and tool failures.

This script fetches Kilo sessions via the local `kilo` CLI, exports matching
sessions, and emits a compact LLM-friendly report or structured JSON.

Usage:
  kilo-session-report
  kilo-session-report --start-date 2026-06-03 --end-date 2026-06-10
  uv run kilo-session-report.py --days 14

## Duplication rules when reading exported session JSON

Exported Kilo session JSON frequently carries the same logical data in two or
more locations, or in multiple shapes. Use these rules so the analyzer reads
each datum once and from its canonical source:

- **Token duplication** — `messages[].info.tokens` is the primary source for
  per-message token accounting. The `step-finish` part also has a `tokens`
  field that describes the same step; do NOT sum both when computing totals.
  The script reads `info.tokens` and intentionally ignores `step-finish.tokens`.

- **Tool output duplication** — `state.output` and `state.metadata.output` can
  contain the same stdout text twice (common for `bash`). Prefer
  `state.output`; only fall back to `state.metadata.output` when
  `state.output` is absent (see `analyze_turn_bloat`'s `output_value` lookup).

- **Read output duplication** — `state.output` carries the full formatted
  content; `state.metadata.preview` carries a shortened preview. Use
  `preview` for triage, `output` only when the file contents matter.

- **Patch duplication** — patch data lives in `messages[].info.summary.diffs[].patch`,
  `apply_patch` `state.input.patchText`, `apply_patch` `state.metadata.files[].patch`,
  and the `parts[]` entry with `type == "patch"`. For edit detection, read the
  patch summary part + file list first; load full patch text only when
  code-change analysis is required.

- **Synthetic file-bundle duplication** — a replayed or injected file read
  may appear as a bundle of adjacent parts (synthetic text saying the tool was
  called, synthetic text containing the formatted read output, `type == "file"`
  with a `file://` URL). Treat these as ONE logical embedded file/read, not
  three. Use the `file://` URL as the stable identifier for deduplication.

- **Todo duplication** — `todowrite` writes the same list to
  `state.input.todos`, `state.output`, `state.metadata.todos`, and
  `state.metadata.view.todos`. Use `state.input.todos` as the canonical
  structured source. Ignore `state.metadata.view` (UI presentation state).

- **Task output shape** — the `task` tool's `state.input` is structured, but
  `state.output` is assistant-generated text (often with a `task_id:` line
  and a `<task_result>...</task_result>` wrapper), NOT JSON. Do not parse
  `state.output` as JSON.

- **Non-uniform shapes** — aborted assistant turns may be empty (`parts: []`)
  or partially populated; `bash` can fail with `state.status == "completed"`
  when only `state.metadata.exit` is non-zero; `file` parts may be references
  without inline body. Use capability-based checks (field exists, type
  matches, fallback if absent) rather than assuming every object of a given
  type has the same fields.
"""

# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for report generation.

    Returns:
        Parsed argparse namespace.
    """
    parser = argparse.ArgumentParser(
        description=(
            "Fetch Kilo sessions via the CLI and analyze them for context "
            "bloat hotspots and tool-call failures."
        )
    )
    parser.add_argument(
        "--start-date",
        help="Inclusive UTC start date in YYYY-MM-DD format.",
    )
    parser.add_argument(
        "--end-date",
        help="Exclusive UTC end date in YYYY-MM-DD format.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=7,
        help="Fallback lookback window in days when explicit dates are not provided (default: 7).",
    )
    parser.add_argument(
        "--last",
        type=int,
        default=0,
        help="Select the last N sessions by updated time, bypassing date filters (0 = disabled).",
    )
    parser.add_argument(
        "--session-search",
        default="",
        help="Optional title filter passed to `kilo session list --search`.",
    )
    parser.add_argument(
        "--session-limit",
        type=int,
        default=0,
        help="Optional cap on listed sessions before filtering by date (0 = no cap).",
    )
    parser.add_argument(
        "--all-projects",
        action="store_true",
        help="Include sessions from all projects via `kilo session list --all`.",
    )
    parser.add_argument(
        "--sanitize",
        action="store_true",
        help="Use `kilo export --sanitize` when exporting sessions.",
    )
    parser.add_argument(
        "--top-turns",
        type=int,
        default=10,
        help="Number of high-cost assistant turns to include (default: 10).",
    )
    parser.add_argument(
        "--top-tool-failures",
        type=int,
        default=50,
        help="Number of tool failures to include (default: 50).",
    )
    parser.add_argument(
        "--top-sessions",
        type=int,
        default=20,
        help="Max sessions shown in session_summary section (default: 20). JSON always includes all.",
    )
    parser.add_argument(
        "--min-input-tokens",
        type=int,
        default=5000,
        help="Secondary input-token threshold for high-cost turns (default: 5000).",
    )
    parser.add_argument(
        "--min-total-tokens",
        type=int,
        default=20000,
        help="Primary total-token threshold for high-cost turns (default: 20000). Checks tokens.total.",
    )
    parser.add_argument(
        "--min-bytes",
        type=int,
        default=12000,
        help="Byte threshold for large payload detection (default: 12000).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Parallel export workers (default: 8).",
    )
    parser.add_argument(
        "--format",
        choices=("compact", "json"),
        default="compact",
        help="Output format: compact or json (default: compact).",
    )
    parser.add_argument(
        "--output-dir",
        default="",
        help=(
            "Directory to write per-session JSON exports AND the report. "
            "Default: ./kilo-session-reports/<UTC-timestamp>/. "
            "Pass an explicit path or '' to use the default."
        ),
    )
    parser.add_argument(
        "--no-keep-exports",
        action="store_true",
        help="Delete the per-session export directory after the report finishes (default: keep).",
    )
    parser.add_argument(
        "--top-diffs",
        type=int,
        default=20,
        help="Max session-level file-diff rows to include (default: 20).",
    )
    parser.add_argument(
        "--top-truncated",
        type=int,
        default=20,
        help="Max truncated-read rows to include (default: 20).",
    )
    parser.add_argument(
        "--report-name",
        default="",
        help=(
            "Base name for the report file written next to the exports. "
            "Default: report.<format>.txt/json. Use the same name across runs to overwrite."
        ),
    )
    parser.add_argument(
        "--timestamp-filename",
        action="store_true",
        help=(
            "Include UTC creation timestamp in export filenames "
            "(format: YYYYMMDDTHHMMSSZ, derived from info.time.created). "
            "Default: off."
        ),
    )
    args = parser.parse_args()

    if args.top_turns < 0:
        parser.error("--top-turns must be >= 0")
    if args.top_tool_failures < 0:
        parser.error("--top-tool-failures must be >= 0")
    if args.top_sessions < 0:
        parser.error("--top-sessions must be >= 0")
    if args.min_input_tokens < 0:
        parser.error("--min-input-tokens must be >= 0")
    if args.min_total_tokens < 0:
        parser.error("--min-total-tokens must be >= 0")
    if args.min_bytes < 0:
        parser.error("--min-bytes must be >= 0")
    if args.workers < 1:
        parser.error("--workers must be >= 1")
    if args.days < 0:
        parser.error("--days must be >= 0")
    if args.session_limit < 0:
        parser.error("--session-limit must be >= 0")
    if bool(args.start_date) ^ bool(args.end_date):
        parser.error("--start-date and --end-date must be provided together")
    if args.last < 0:
        parser.error("--last must be >= 0")
    if args.last > 0 and (args.start_date or args.end_date):
        parser.error("--last cannot be combined with --start-date/--end-date")
    if args.top_diffs < 0:
        parser.error("--top-diffs must be >= 0")
    if args.top_truncated < 0:
        parser.error("--top-truncated must be >= 0")

    return args


def as_dict(value: Any) -> dict[str, Any]:
    """Return value when dict, otherwise an empty dict."""
    return value if isinstance(value, dict) else {}


def as_list(value: Any) -> list[Any]:
    """Return value when list, otherwise an empty list."""
    return value if isinstance(value, list) else []


def as_text(value: Any) -> str:
    """Convert any value to a safe text representation."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def as_int(value: Any) -> int | None:
    """Parse integer-like values safely.

    Args:
        value: Any candidate value.

    Returns:
        Parsed integer or None when conversion fails.
    """
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return None
        try:
            return int(float(stripped))
        except ValueError:
            return None
    return None


def parse_utc_date(raw: str) -> datetime:
    """Parse YYYY-MM-DD as a UTC datetime at midnight."""
    return datetime.strptime(raw, "%Y-%m-%d").replace(tzinfo=timezone.utc)


def resolve_window(args: argparse.Namespace) -> tuple[datetime, datetime]:
    """Resolve the inclusive/exclusive UTC window for session filtering."""
    if args.start_date and args.end_date:
        start = parse_utc_date(args.start_date)
        end = parse_utc_date(args.end_date)
        return start, end

    end = datetime.now(timezone.utc)
    start = end - timedelta(days=args.days)
    return start, end


def resolve_output_dir(args: argparse.Namespace) -> Path:
    """Resolve the per-session export directory and create it.

    The directory also receives the rendered report (default
    `report.<format>.txt` or `report.json`) so the raw exports and the
    report stay co-located.
    """
    if args.output_dir:
        base = Path(args.output_dir)
    else:
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        base = Path.cwd() / "kilo-session-reports" / ts
    base.mkdir(parents=True, exist_ok=True)
    return base


def report_path(output_dir: Path, args: argparse.Namespace) -> Path:
    """Resolve the report file path written into `output_dir`."""
    if args.report_name:
        return output_dir / args.report_name
    ext = "json" if args.format == "json" else "txt"
    return output_dir / f"report.{ext}"


# Default filename format string.
# Components: prefix, title_slug, timestamp, id_suffix
_FILENAME_FORMAT_DEFAULT = "{prefix}{title_slug}__{id_suffix}"
_FILENAME_FORMAT_TS = "{prefix}{title_slug}__{time_created_str}__{id_suffix}"


def session_filename_parts(
    session: dict[str, Any],
    session_id: str,
    is_subagent: bool = False,
) -> dict[str, Any]:
    """Extract all available filename components from a session export.

    Returns a dict with every potentially useful filename component,
    derived once from ``session`` so callers can recombine them freely
    without re-extracting. Unavailable fields fall back to safe defaults.

    Fields
    ------
    id_full : str
        Full session ID (e.g. ``ses_114c81546ffe9J2AOGYkMNgdvl``)
    id_suffix : str
        Last 12 characters of session ID (e.g. ``2AOGYkMNgdvl``)
    slug : str
        Session slug as exported (e.g. ``gentle-nebula``)
    project_id : str
        Project ID (e.g. ``2b666eb759de7bbcaf4ebd128f85720d5e5204cb``)
    title_raw : str
        Untouched title string
    title_slug : str
        Filesystem-safe, lowercased, truncated title
    agent : str
        Agent name (e.g. ``code``)
    model_id : str
        Full model ID (e.g. ``minimax/minimax-m2.7``)
    model_variant : str
        Model variant (e.g. ``thinking``)
    model_provider : str
        Model provider (e.g. ``kilo``)
    time_created_ms : int | None
        ``info.time.created`` as milliseconds since epoch
    time_updated_ms : int | None
        ``info.time.updated`` as milliseconds since epoch
    time_created_str : str | None
        ``info.time.created`` as a ``YYYYMMDDTHHMMSSZ`` UTC string
    time_updated_str : str | None
        ``info.time.updated`` as a ``YYYYMMDDTHHMMSSZ`` UTC string
    time_created_iso : str | None
        ``info.time.created`` as an ISO-8601 UTC string
    time_updated_iso : str | None
        ``info.time.updated`` as an ISO-8601 UTC string
    prefix : str
        ``subagent_`` when ``is_subagent`` else ``agent_``
    is_subagent : bool
        Reflects the ``is_subagent`` argument
    """
    info = as_dict(session.get("info"))
    time_info = as_dict(info.get("time"))
    model = as_dict(info.get("model"))

    id_full = session_id
    id_suffix = session_id[-12:] if session_id else "unknown"
    slug = as_text(info.get("slug")) or ""
    project_id = as_text(info.get("projectID")) or ""
    title_raw = as_text(info.get("title")) or "untitled"
    title_slug = re.sub(
        r"[^a-zA-Z0-9_-]+", "-", title_raw
    ).strip("-").lower()
    title_slug = title_slug[:60] or "untitled"
    agent = as_text(info.get("agent")) or ""
    model_id = as_text(model.get("id")) or ""
    model_variant = as_text(model.get("variant")) or ""
    model_provider = as_text(model.get("providerID")) or ""

    created_ms = as_int(time_info.get("created"))
    updated_ms = as_int(time_info.get("updated"))
    time_created_str: str | None = None
    time_updated_str: str | None = None
    time_created_iso: str | None = None
    time_updated_iso: str | None = None

    if created_ms is not None:
        created_dt = datetime.fromtimestamp(
            created_ms / 1000, tz=timezone.utc
        )
        time_created_str = created_dt.strftime("%Y%m%dT%H%M%SZ")
        time_created_iso = created_dt.isoformat()
    if updated_ms is not None:
        updated_dt = datetime.fromtimestamp(
            updated_ms / 1000, tz=timezone.utc
        )
        time_updated_str = updated_dt.strftime("%Y%m%dT%H%M%SZ")
        time_updated_iso = updated_dt.isoformat()

    return {
        "id_full": id_full,
        "id_suffix": id_suffix,
        "slug": slug,
        "project_id": project_id,
        "title_raw": title_raw,
        "title_slug": title_slug,
        "agent": agent,
        "model_id": model_id,
        "model_variant": model_variant,
        "model_provider": model_provider,
        "time_created_ms": created_ms,
        "time_updated_ms": updated_ms,
        "time_created_str": time_created_str,
        "time_updated_str": time_updated_str,
        "time_created_iso": time_created_iso,
        "time_updated_iso": time_updated_iso,
        "prefix": "subagent_" if is_subagent else "agent_",
        "is_subagent": is_subagent,
    }


def export_filename(
    session: dict[str, Any],
    session_id: str,
    is_subagent: bool = False,
    timestamp_filename: bool = False,
) -> str:
    """Build a filesystem-safe filename from session title + id suffix.

    Filenames are prefixed with ``agent_`` for top-level sessions and
    ``subagent_`` for sessions discovered via ``task`` tool parts in a
    parent session. The prefix is what callers use to visually
    distinguish the two tiers in the output directory listing.

    When ``timestamp_filename`` is True, the UTC creation timestamp
    (from ``info.time.created``) is embedded between the title slug
    and the session ID suffix in the format
    ``prefix_title__YYYYMMDDTHHMMSSZ__sessionIdSuffix.json``.

    All derived filename components are also available via
    :func:`session_filename_parts` for callers that need custom
    filename formats.
    """
    parts = session_filename_parts(session, session_id, is_subagent)
    if timestamp_filename and parts["time_created_str"] is not None:
        return _FILENAME_FORMAT_TS.format(**parts)
    return _FILENAME_FORMAT_DEFAULT.format(**parts)


def bytes_len(value: Any) -> int:
    """Estimate payload size in UTF-8 bytes."""
    if value is None:
        return 0
    if isinstance(value, str):
        return len(value.encode("utf-8", errors="replace"))
    try:
        rendered = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError):
        rendered = as_text(value)
    return len(rendered.encode("utf-8", errors="replace"))


def one_line_excerpt(value: Any, max_len: int = 160) -> str:
    """Build a compact one-line excerpt.

    Args:
        value: Source text or object.
        max_len: Maximum output length.

    Returns:
        Single-line excerpt.
    """
    if isinstance(value, (dict, list)):
        text = json.dumps(value, ensure_ascii=False, sort_keys=True)
    else:
        text = as_text(value)
    collapsed = " ".join(text.split())
    if len(collapsed) <= max_len:
        return collapsed
    return collapsed[: max_len - 1] + "…"


def classify_failure(text: str) -> str:
    """Classify failure cause into broad categories.

    Returns one of: environmental, usage-related, data-related, unknown.
    """
    hay = text.lower()
    if not hay:
        return "unknown"

    environmental = (
        "command not found",
        "executable file not found",
        "permission denied",
        "eacces",
        "connection refused",
        "network is unreachable",
        "could not resolve host",
        "name or service not known",
        "timed out",
        "timeout",
        "dns",
        "tls",
        "certificate",
    )
    usage_related = (
        "404",
        "file not found",
        "path not found",
        "no such file",
        "no such directory",
        "invalid url",
        "bad request",
        "unknown flag",
        "invalid option",
        "missing required",
        "does not exist",
        "not found",
    )
    data_related = (
        "malformed",
        "schema",
        "json",
        "yaml",
        "toml",
        "decode",
        "parse",
        "unexpected token",
        "invalid character",
        "validation",
        "unmarshal",
    )

    if any(marker in hay for marker in environmental):
        return "environmental"
    if any(marker in hay for marker in usage_related):
        return "usage-related"
    if any(marker in hay for marker in data_related):
        return "data-related"
    return "unknown"


def add_source_total(
    source_totals: dict[str, dict[str, int]],
    source: str,
    size_bytes: int,
) -> None:
    """Accumulate source totals for large-body attribution."""
    row = source_totals[source]
    row["count"] += 1
    row["bytes"] += max(size_bytes, 0)


def run_kilo_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    """Run a Kilo CLI command and return the completed process."""
    return subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def load_sessions(args: argparse.Namespace) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    """List and date-filter sessions using the Kilo CLI."""
    critical_exceptions: list[dict[str, str]] = []
    cmd = ["kilo", "session", "list", "--format", "json"]
    if args.all_projects:
        cmd.append("--all")
    if args.session_search:
        cmd.extend(["--search", args.session_search])
    if args.session_limit > 0:
        cmd.extend(["-n", str(args.session_limit)])

    result = run_kilo_command(cmd)
    if result.returncode != 0:
        critical_exceptions.append(
            {
                "file": "kilo session list",
                "error": one_line_excerpt(result.stderr or result.stdout or "list_failed"),
            }
        )
        return [], critical_exceptions

    if not result.stdout or not result.stdout.strip():
        critical_exceptions.append(
            {
                "file": "kilo session list",
                "error": (
                    f"empty_stdout: rc={result.returncode}; "
                    f"stderr={one_line_excerpt(result.stderr or '', max_len=200)}; "
                    f"cmd={' '.join(cmd)}"
                ),
            }
        )
        return [], critical_exceptions

    try:
        sessions = as_list(json.loads(result.stdout))
    except json.JSONDecodeError as exc:
        stdout_excerpt = one_line_excerpt(result.stdout or "", max_len=200)
        stderr_excerpt = one_line_excerpt(result.stderr or "", max_len=200)
        critical_exceptions.append(
            {
                "file": "kilo session list",
                "error": (
                    f"parse_error: {exc}; "
                    f"stdout_head={stdout_excerpt}; "
                    f"stderr={stderr_excerpt}"
                ),
            }
        )
        return [], critical_exceptions

    filtered: list[dict[str, Any]] = []
    if args.last > 0:
        for raw_session in sessions:
            session = as_dict(raw_session)
            if as_int(session.get("updated")) is not None:
                filtered.append(session)
        filtered.sort(
            key=lambda row: -(as_int(as_dict(row).get("updated")) or 0),
        )
        filtered = filtered[: args.last]
    else:
        start, end = resolve_window(args)
        for raw_session in sessions:
            session = as_dict(raw_session)
            updated_ms = as_int(session.get("updated"))
            if updated_ms is None:
                continue
            updated_at = datetime.fromtimestamp(updated_ms / 1000, tz=timezone.utc)
            if start <= updated_at < end:
                filtered.append(session)

    filtered.sort(
        key=lambda row: (
            -(as_int(as_dict(row).get("updated")) or 0),
            as_text(as_dict(row).get("id")),
        )
    )
    return filtered, critical_exceptions


def export_session_json(
    session_id: str,
    sanitize: bool,
    output_path: Path,
) -> tuple[dict[str, Any] | None, dict[str, str] | None]:
    """Export one session as JSON to a file via shell redirect.

    Writes to a file (not a pipe) to avoid Linux pipe-buffer truncation
    when multiple kilo processes run concurrently. See
    `_plans_temp/kilo-session-report-refactor.md` for the full investigation.
    """
    cmd = ["kilo", "export", session_id]
    if sanitize:
        cmd.append("--sanitize")

    proc: subprocess.Popen[bytes] | None = None
    try:
        with output_path.open("wb") as f_out, \
             subprocess.Popen(cmd, stdout=f_out, stderr=subprocess.PIPE) as proc:
            _, stderr_bytes = proc.communicate()
    except OSError as exc:
        return None, {
            "file": str(output_path),
            "error": f"spawn_failed: {exc}",
        }

    if proc.returncode != 0:
        stderr_text = stderr_bytes.decode("utf-8", errors="replace") if stderr_bytes else ""
        return None, {
            "file": str(output_path),
            "error": f"export_failed: rc={proc.returncode}; stderr={one_line_excerpt(stderr_text, max_len=200)}",
        }

    if not output_path.exists() or output_path.stat().st_size == 0:
        return None, {
            "file": str(output_path),
            "error": "empty_output: rc=0 but file is missing or empty",
        }

    raw = output_path.read_text(encoding="utf-8", errors="replace")

    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, {
            "file": str(output_path),
            "error": (
                f"parse_error: {exc}; "
                f"size={len(raw)}; "
                f"tail={one_line_excerpt(raw[-200:], max_len=200)}"
            ),
        }


def build_message_index(messages: list[Any]) -> list[dict[str, Any]]:
    """Build a compact index from messages[].info and parts[] shapes."""
    index: list[dict[str, Any]] = []
    for offset, message_raw in enumerate(messages):
        message = as_dict(message_raw)
        info = as_dict(message.get("info"))
        parts = as_list(message.get("parts"))

        tokens = as_dict(info.get("tokens"))
        part_types = sorted(
            {
                as_text(as_dict(part).get("type"))
                for part in parts
                if as_text(as_dict(part).get("type"))
            }
        )

        index.append(
            {
                "offset": offset,
                "id": as_text(info.get("id")) or f"msg#{offset}",
                "role": as_text(info.get("role")) or "unknown",
                "parent_id": as_text(info.get("parentID")),
                "time": as_text(info.get("time")),
                "input_tokens": as_int(tokens.get("input")) or 0,
                "total_tokens": as_int(tokens.get("total")) or 0,
                "has_error": bool(info.get("error")),
                "has_synthetic": any(
                    as_dict(part).get("synthetic") is True for part in parts
                ),
                "part_types": part_types,
            }
        )
    return index


def tool_input_size(tool: str, input_obj: Any) -> int:
    """Estimate the byte size of a tool-call's input payload.

    Used for per-tool input attribution in `source_totals` (e.g. giant
    `bash` commands, oversized `write` content, large `apply_patch`
    patches beyond the special-cased `patchText`).
    """
    if not isinstance(input_obj, dict):
        return bytes_len(input_obj)

    if tool == "apply_patch":
        return bytes_len(input_obj.get("patchText"))
    if tool == "bash":
        return bytes_len(input_obj.get("command")) + bytes_len(input_obj.get("description"))
    if tool == "read":
        return bytes_len(input_obj.get("filePath")) + bytes_len(input_obj.get("offset")) + bytes_len(input_obj.get("limit"))
    if tool == "write":
        return bytes_len(input_obj.get("filePath")) + bytes_len(input_obj.get("content"))
    if tool == "edit":
        return (
            bytes_len(input_obj.get("filePath"))
            + bytes_len(input_obj.get("oldText"))
            + bytes_len(input_obj.get("newText"))
        )
    if tool == "webfetch":
        return bytes_len(input_obj.get("url")) + bytes_len(input_obj.get("format"))
    if tool == "todowrite":
        return bytes_len(input_obj.get("todos"))
    if tool == "task":
        return bytes_len(input_obj.get("prompt")) + bytes_len(input_obj.get("description"))

    return bytes_len(input_obj)


def analyze_turn_bloat(
    message_info: dict[str, Any],
    parts: list[Any],
    min_bytes: int,
    source_totals: dict[str, dict[str, int]],
) -> dict[str, Any]:
    """Infer probable context-bloat sources for one assistant message."""
    synthetic_count = 0
    file_part_count = 0
    tool_names: list[str] = []
    large_tool_outputs: list[dict[str, Any]] = []
    large_apply_patch_input_sizes: list[int] = []
    large_diff_patch_sizes: list[int] = []
    truncated_outputs: list[dict[str, Any]] = []

    for part_raw in parts:
        part = as_dict(part_raw)
        part_type = as_text(part.get("type"))

        if part.get("synthetic") is True:
            synthetic_count += 1
            synthetic_size = max(
                bytes_len(part.get("text")),
                bytes_len(part.get("content")),
                bytes_len(part.get("value")),
            )
            if synthetic_size >= min_bytes:
                add_source_total(source_totals, "synthetic_text", synthetic_size)

        if part_type == "file":
            file_part_count += 1

        if part_type != "tool":
            continue

        tool = as_text(part.get("tool")) or "unknown"
        tool_names.append(tool)

        state = as_dict(part.get("state"))
        state_metadata = as_dict(state.get("metadata"))
        output_value = state.get("output")
        if output_value is None:
            output_value = state_metadata.get("output")
        output_size = bytes_len(output_value)
        if output_size >= min_bytes:
            large_tool_outputs.append({"tool": tool, "bytes": output_size})
            add_source_total(source_totals, f"tool_output:{tool}", output_size)

        truncated_flag = state_metadata.get("truncated")
        if truncated_flag is True or truncated_flag == "true":
            preview_excerpt = one_line_excerpt(state_metadata.get("preview"), max_len=160)
            loaded_excerpt = one_line_excerpt(state_metadata.get("loaded"), max_len=160)
            truncated_outputs.append(
                {
                    "tool": tool,
                    "title": as_text(state.get("title")),
                    "output_bytes": output_size,
                    "preview": preview_excerpt,
                    "loaded": loaded_excerpt,
                }
            )
            add_source_total(
                source_totals,
                f"truncated_output:{tool}",
                output_size,
            )

        if tool == "apply_patch":
            patch_text = as_dict(state.get("input")).get("patchText")
            patch_size = bytes_len(patch_text)
            if patch_size >= min_bytes:
                large_apply_patch_input_sizes.append(patch_size)
                add_source_total(
                    source_totals,
                    "apply_patch_input.patchText",
                    patch_size,
                )

        input_size = tool_input_size(tool, state.get("input"))
        if input_size >= min_bytes:
            add_source_total(
                source_totals,
                f"tool_input:{tool}",
                input_size,
            )

    summary = as_dict(message_info.get("summary"))
    for diff in as_list(summary.get("diffs")):
        patch_size = bytes_len(as_dict(diff).get("patch"))
        if patch_size >= min_bytes:
            large_diff_patch_sizes.append(patch_size)
            add_source_total(source_totals, "summary_diff_patch", patch_size)

    probable_sources: list[str] = []
    if synthetic_count > 0:
        probable_sources.append("synthetic_parts")
    if any(row["bytes"] >= min_bytes for row in large_tool_outputs):
        probable_sources.append("large_tool_output")
    if large_apply_patch_input_sizes:
        probable_sources.append("large_apply_patch_input")
    if large_diff_patch_sizes:
        probable_sources.append("large_diff_patch")
    if truncated_outputs:
        probable_sources.append("truncated_outputs")
    if file_part_count > 0:
        probable_sources.append("file_parts")
    if tool_names:
        probable_sources.append("tool_parts")

    large_tool_outputs.sort(key=lambda row: (-row["bytes"], row["tool"]))
    truncated_outputs.sort(key=lambda row: (-row["output_bytes"], row["tool"]))

    return {
        "synthetic_content_count": synthetic_count,
        "tool_part_count": len(tool_names),
        "tool_names": sorted(set(tool_names)),
        "large_tool_outputs": large_tool_outputs,
        "large_apply_patch_input_sizes": sorted(
            large_apply_patch_input_sizes,
            reverse=True,
        ),
        "large_diff_patch_sizes": sorted(large_diff_patch_sizes, reverse=True),
        "truncated_outputs": truncated_outputs,
        "file_part_count": file_part_count,
        "probable_sources": probable_sources,
    }


def parse_iso_ms(value: Any) -> int | None:
    """Parse a millisecond Unix timestamp or ISO 8601 string to int ms."""
    if isinstance(value, (int, float)):
        return int(value)
    if not isinstance(value, str) or not value:
        return None
    try:
        return int(float(value))
    except ValueError:
        pass
    text = value.replace("Z", "+00:00") if value.endswith("Z") else value
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def compute_session_duration_ms(info: dict[str, Any]) -> int | None:
    """Compute session duration in ms from `info.time.{created,updated}`."""
    t = as_dict(info.get("time"))
    created = parse_iso_ms(t.get("created"))
    updated = parse_iso_ms(t.get("updated"))
    if created is None or updated is None:
        return None
    delta = updated - created
    return delta if delta > 0 else None


def collect_session_diffs(
    info: dict[str, Any],
) -> list[dict[str, Any]]:
    """Extract session-level `info.summary.diffs` as lightweight rows."""
    summary = as_dict(info.get("summary"))
    rows: list[dict[str, Any]] = []
    for diff in as_list(summary.get("diffs")):
        row = as_dict(diff)
        rows.append(
            {
                "file": as_text(row.get("file")),
                "additions": as_int(row.get("additions")) or 0,
                "deletions": as_int(row.get("deletions")) or 0,
                "status": as_text(row.get("status")),
            }
        )
    rows.sort(
        key=lambda r: (
            -(r["additions"] + r["deletions"]),
            r["file"] or "",
        )
    )
    return rows


def collect_all_models(
    messages: list[Any],
) -> tuple[list[str], list[str]]:
    """Collect distinct model IDs and variants across all messages."""
    model_ids: set[str] = set()
    variants: set[str] = set()
    for message in messages:
        info = as_dict(as_dict(message).get("info"))
        model = as_dict(info.get("model"))
        mid = as_text(model.get("modelID")) or as_text(info.get("modelID"))
        var = as_text(model.get("variant")) or as_text(info.get("variant"))
        if mid:
            model_ids.add(mid)
        if var:
            variants.add(var)
    return sorted(model_ids), sorted(variants)


def _looks_like_session_id(value: Any) -> bool:
    """Return True if ``value`` plausibly identifies a Kilo session.

    Heuristic: a non-empty string that doesn't start with common non-id
    prefixes (``msg_``, ``call_``, ``prt_``, ``part_``) and has at least
    8 characters. We deliberately accept any alphanumeric/dash/underscore
    shape because Kilo session IDs are opaque strings.
    """
    if not isinstance(value, str):
        return False
    text = value.strip()
    if len(text) < 8:
        return False
    lowered = text.lower()
    for bad in ("msg_", "call_", "prt_", "part_"):
        if lowered.startswith(bad):
            return False
    return bool(re.fullmatch(r"[A-Za-z0-9_-]+", text))


def find_subagent_session_ids_in_export(
    export_root: dict[str, Any],
) -> list[tuple[str, str]]:
    """Extract subagent session IDs from ``task`` tool parts.

    Walks the messages of one exported session and, for every part of
    type ``tool`` with tool name ``task``, looks for a subagent session
    ID in the tool input (``state.input``) and tool result metadata
    (``state.metadata`` and ``state.metadata.output``).

    Returns:
        A list of ``(parent_session_id, subagent_session_id)`` tuples
        for every subagent reference discovered. Duplicates within a
        single export are removed while preserving discovery order.
    """
    messages = as_list(export_root.get("messages"))
    seen: set[str] = set()
    out: list[tuple[str, str]] = []
    candidate_keys = (
        "sessionID",
        "sessionId",
        "session_id",
        "subagent_session_id",
    )

    for message in messages:
        message = as_dict(message)
        info = as_dict(message.get("info"))
        msg_session_id = as_text(info.get("id")) or as_text(info.get("sessionID"))
        for part in as_list(message.get("parts")):
            part = as_dict(part)
            if as_text(part.get("type")) != "tool":
                continue
            if as_text(part.get("tool")) != "task":
                continue

            state = as_dict(part.get("state"))
            state_input = as_dict(state.get("input"))
            metadata = as_dict(state.get("metadata"))

            search_targets: list[dict[str, Any]] = [
                state_input,
                metadata,
                as_dict(metadata.get("output")),
            ]
            nested: list[dict[str, Any]] = []
            for target in search_targets:
                nested.append(as_dict(target.get("metadata")))
                nested.append(as_dict(as_dict(target.get("output")).get("metadata")))
            search_targets.extend(nested)

            for target in search_targets:
                if not target:
                    continue
                for key in candidate_keys:
                    raw_value = target.get(key)
                    if _looks_like_session_id(raw_value):
                        sub_id = as_text(raw_value).strip()
                        if sub_id in seen:
                            continue
                        seen.add(sub_id)
                        out.append((msg_session_id, sub_id))
                        break
                else:
                    continue
                break

    return out


def _analyze_one_session_export(
    session: dict[str, Any],
    export_root: dict[str, Any],
    accum: dict[str, Any],
    min_input_tokens: int,
    min_total_tokens: int,
    min_bytes: int,
) -> None:
    """Analyze a single successfully-exported session in-place.

    Mutates the shared ``accum`` dict in place. The ``accum`` shape
    mirrors the per-run collector state in :func:`analyze_sessions` and
    carries the per-session summary row back via
    ``accum["session_summary"]``.
    """
    session_row = as_dict(session)
    session_id = as_text(session_row.get("id"))
    session_title = as_text(session_row.get("title"))

    messages = as_list(export_root.get("messages"))
    accum["files_parsed"] += 1
    accum["messages_total"] += len(messages)

    session_cost = 0.0
    session_tokens_total = 0
    session_agents: set[str] = set()
    session_primary_model = ""
    session_assistant_turns = 0
    session_failure_count = 0
    session_high_cost_count = 0
    session_invalid_tool_count = 0
    session_truncated_count = 0
    session_model_ids: set[str] = set()
    session_variants: set[str] = set()

    session_info = as_dict(export_root.get("info"))

    message_index = build_message_index(messages)
    index_by_offset = {row["offset"]: row for row in message_index}

    for offset, message_raw in enumerate(messages):
        message = as_dict(message_raw)
        info = as_dict(message.get("info"))
        parts = as_list(message.get("parts"))

        idx = as_dict(index_by_offset.get(offset))
        msg_id = as_text(idx.get("id") or info.get("id") or f"msg#{offset}")
        role = as_text(idx.get("role") or info.get("role") or "unknown")
        parent_id = as_text(idx.get("parent_id") or info.get("parentID"))
        msg_time = as_text(idx.get("time") or info.get("time"))

        tokens = as_dict(info.get("tokens"))
        input_tokens = as_int(tokens.get("input")) or 0
        output_tokens = as_int(tokens.get("output")) or 0
        total_tokens = as_int(tokens.get("total")) or 0
        reasoning_tokens = as_int(tokens.get("reasoning")) or 0
        cache = as_dict(tokens.get("cache"))
        cache_read = as_int(cache.get("read")) or 0
        cache_write = as_int(cache.get("write")) or 0

        if role == "assistant":
            accum["assistant_messages_total"] += 1
            session_assistant_turns += 1
            session_tokens_total += total_tokens

            agent = as_text(info.get("agent") or "")
            cost = float(info.get("cost") or 0)
            model_id = as_text(info.get("modelID") or "")
            variant = as_text(
                as_dict(info.get("model")).get("variant")
                or info.get("variant")
                or ""
            )

            if agent:
                session_agents.add(agent)
            if model_id:
                session_model_ids.add(model_id)
            if variant:
                session_variants.add(variant)
            session_cost += cost
            if not session_primary_model and model_id:
                session_primary_model = model_id

            is_high_cost = (
                total_tokens >= min_total_tokens
                or input_tokens >= min_input_tokens
            )
            if is_high_cost:
                session_high_cost_count += 1
                bloat = analyze_turn_bloat(
                    message_info=info,
                    parts=parts,
                    min_bytes=min_bytes,
                    source_totals=accum["source_totals"],
                )
                turn_truncated = as_list(bloat.get("truncated_outputs"))
                session_truncated_count += len(turn_truncated)
                for row in turn_truncated:
                    accum["truncated_rows"].append(
                        {
                            "file": session_id,
                            "session_title": session_title,
                            "message_id": msg_id,
                            "tool": row.get("tool"),
                            "title": row.get("title"),
                            "output_bytes": row.get("output_bytes"),
                            "preview": row.get("preview"),
                            "loaded": row.get("loaded"),
                            "agent": agent,
                        }
                    )
                accum["all_high_cost_turns"].append(
                    {
                        "file": session_id,
                        "session_title": session_title,
                        "message_id": msg_id,
                        "time": msg_time,
                        "role": role,
                        "agent": agent,
                        "cost": cost,
                        "parent_id": parent_id,
                        "tokens": {
                            "input": input_tokens,
                            "output": output_tokens,
                            "total": total_tokens,
                            "reasoning": reasoning_tokens,
                            "cache_read": cache_read,
                            "cache_write": cache_write,
                        },
                        **bloat,
                        "_offset": offset,
                    }
                )

        msg_agent = as_text(info.get("agent") or "")

        for part_raw in parts:
            part = as_dict(part_raw)
            if as_text(part.get("type")) != "tool":
                continue

            tool = as_text(part.get("tool")) or "unknown"
            call_id = as_text(part.get("callID"))
            state = as_dict(part.get("state"))
            status = as_text(state.get("status"))
            metadata = as_dict(state.get("metadata"))
            exit_code = as_int(metadata.get("exit"))

            accum["tool_call_counts"][tool] += 1
            output_value = state.get("output")
            if output_value is None:
                output_value = metadata.get("output")
            accum["tool_output_bytes_acc"][tool] += bytes_len(output_value)

            if tool == "invalid":
                state_input = as_dict(state.get("input"))
                requested_tool = as_text(state_input.get("tool")) or "unknown"
                error_text = (
                    as_text(state_input.get("error"))
                    or as_text(state.get("error"))
                    or "invalid_tool_call"
                )
                cause_excerpt = one_line_excerpt(error_text, max_len=200)
                session_invalid_tool_count += 1

                bucket = accum["invalid_tool_attempts"].setdefault(
                    requested_tool,
                    {
                        "requested_tool": requested_tool,
                        "count": 0,
                        "session_ids": set(),
                        "example_error": cause_excerpt,
                        "example_session_id": session_id,
                    },
                )
                bucket["count"] += 1
                bucket["session_ids"].add(session_id)
                if (
                    not bucket.get("example_error")
                    or len(bucket["example_error"]) < len(cause_excerpt)
                ):
                    bucket["example_error"] = cause_excerpt
                    bucket["example_session_id"] = session_id

                accum["all_tool_failures"].append(
                    {
                        "file": session_id,
                        "session_title": session_title,
                        "message_id": msg_id,
                        "call_id": call_id,
                        "tool": f"invalid:{requested_tool}",
                        "agent": msg_agent,
                        "status": status or "",
                        "exit_code": exit_code,
                        "title": as_text(state.get("title")),
                        "truncated": bool(metadata.get("truncated")),
                        "classification": "data-related",
                        "cause_excerpt": cause_excerpt,
                        "_offset": offset,
                    }
                )
                continue

            explicit_failure = status == "error"
            bash_failure = (
                tool == "bash" and exit_code is not None and exit_code != 0
            )
            if not (explicit_failure or bash_failure):
                continue

            session_failure_count += 1
            accum["tool_failure_counts"][tool] += 1

            error_text = state.get("error")
            output_text = state.get("output")
            if error_text is None and output_text is None:
                output_text = metadata.get("output")
            cause_source = error_text if error_text is not None else output_text
            cause_excerpt = one_line_excerpt(cause_source, max_len=160)

            accum["all_tool_failures"].append(
                {
                    "file": session_id,
                    "session_title": session_title,
                    "message_id": msg_id,
                    "call_id": call_id,
                    "tool": tool,
                    "agent": msg_agent,
                    "status": status or "",
                    "exit_code": exit_code,
                    "title": as_text(state.get("title")),
                    "truncated": bool(metadata.get("truncated")),
                    "classification": classify_failure(cause_excerpt),
                    "cause_excerpt": cause_excerpt,
                    "_offset": offset,
                }
            )

    for diff_row in collect_session_diffs(session_info):
        accum["session_diffs"].append(
            {
                "session_id": session_id,
                "session_title": session_title,
                **diff_row,
            }
        )

    all_model_ids, all_variants = collect_all_models(messages)
    session_model_ids.update(all_model_ids)
    session_variants.update(all_variants)
    duration_ms = compute_session_duration_ms(session_info)

    accum["session_summaries"].append(
        {
            "session_id": session_id,
            "title": session_title,
            "total_cost": round(session_cost, 4),
            "total_tokens": session_tokens_total,
            "assistant_turns": session_assistant_turns,
            "agents": ",".join(sorted(session_agents)),
            "primary_model": session_primary_model,
            "model_ids": ",".join(sorted(session_model_ids)),
            "variants": ",".join(sorted(session_variants)),
            "duration_ms": duration_ms,
            "failure_count": session_failure_count,
            "high_cost_turns": session_high_cost_count,
            "invalid_tool_calls": session_invalid_tool_count,
            "truncated_outputs": session_truncated_count,
        }
    )


def _export_sessions_parallel(
    sessions: list[dict[str, Any]],
    output_dir: Path,
    sanitize: bool,
    workers: int,
    is_subagent: bool,
    timestamp_filename: bool = False,
) -> list[tuple[dict[str, Any], dict[str, Any] | None, dict[str, str] | None]]:
    """Export a batch of sessions in parallel.

    Each ``session`` dict is the same shape used elsewhere in the
    module (an item from ``kilo session list`` or a synthesized
    placeholder for subagent sessions).
    """
    results: list[
        tuple[dict[str, Any], dict[str, Any] | None, dict[str, str] | None]
    ] = []
    if not sessions:
        return results

    with ThreadPoolExecutor(max_workers=workers) as executor:
        future_to_session = {}
        for s in sessions:
            sid = as_text(as_dict(s).get("id"))
            future_to_session[
                executor.submit(
                    export_session_json,
                    sid,
                    sanitize,
                    output_dir
                    / export_filename(
                        s, sid, is_subagent=is_subagent,
                        timestamp_filename=timestamp_filename,
                    ),
                )
            ] = s
        for future in as_completed(future_to_session):
            session = future_to_session[future]
            try:
                export_root, export_error = future.result()
            except Exception as exc:  # noqa: BLE001
                session_id = as_text(as_dict(session).get("id"))
                export_root = None
                export_error = {
                    "file": f"kilo export {session_id}",
                    "error": one_line_excerpt(str(exc)),
                }
            results.append((session, export_root, export_error))
    return results


def analyze_sessions(
    sessions: list[dict[str, Any]],
    output_dir: Path,
    min_input_tokens: int,
    min_total_tokens: int,
    min_bytes: int,
    sanitize: bool,
    workers: int,
    timestamp_filename: bool = False,
    initial_exceptions: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """Analyze exported Kilo sessions fetched through the CLI.

    The workflow runs in three logical phases:

    1. **Top-level export** — export every session returned by
       ``kilo session list`` in parallel and record their paths.
    2. **Top-level analysis + subagent discovery** — analyze each
       top-level export, scanning its ``task`` tool parts for embedded
       subagent session IDs. The discovered subagents are deduplicated
       against an internal set and recorded in the report.
    3. **Subagent export + analysis** — export the newly-discovered
       subagent sessions, then run the same per-session analysis over
       them. Recursive subagents (a subagent that itself spawns
       subagents) are processed iteratively until the queue is empty.
    """
    critical_exceptions: list[dict[str, str]] = list(initial_exceptions or [])
    accum: dict[str, Any] = {
        "files_parsed": 0,
        "messages_total": 0,
        "assistant_messages_total": 0,
        "all_high_cost_turns": [],
        "all_tool_failures": [],
        "source_totals": defaultdict(lambda: {"count": 0, "bytes": 0}),
        "tool_call_counts": defaultdict(int),
        "tool_failure_counts": defaultdict(int),
        "tool_output_bytes_acc": defaultdict(int),
        "invalid_tool_attempts": {},
        "session_summaries": [],
        "session_diffs": [],
        "truncated_rows": [],
    }

    export_paths: dict[str, str] = {}
    subagent_records: list[dict[str, Any]] = []
    subagent_sessions_skipped_duplicate = 0

    # `exported_ids` is the dedup set for sessions that have been or
    # are about to be exported. `exported_ids_top` tracks ids from the
    # original `kilo session list` separately so we can distinguish
    # "top-level" sessions from "subagent" sessions in the report.
    exported_ids: set[str] = set()
    exported_ids_top: set[str] = set()
    # Subagent sessions waiting to be exported, in discovery order.
    pending_subagents: list[tuple[str, str]] = []
    # session_id -> title (best-known at discovery time; updated after export).
    discovered_titles: dict[str, str] = {}

    files_total_top_level = len(sessions)
    files_total_subagent = 0

    # --- Phase 1: Top-level parallel export -----------------------------
    top_level_exports = _export_sessions_parallel(
        sessions=sessions,
        output_dir=output_dir,
        sanitize=sanitize,
        workers=workers,
        is_subagent=False,
        timestamp_filename=timestamp_filename,
    )

    for session, export_root, export_error in top_level_exports:
        session_row = as_dict(session)
        sid = as_text(session_row.get("id"))
        if sid:
            exported_ids.add(sid)
            exported_ids_top.add(sid)
        if export_error is None and sid:
            export_paths[sid] = str(
                output_dir
                / export_filename(
                    session, sid, is_subagent=False,
                    timestamp_filename=timestamp_filename,
                )
            )
        else:
            critical_exceptions.append(
                export_error
                or {
                    "file": f"kilo export {sid}",
                    "error": "export_root_missing",
                }
            )

    # --- Phase 2: Top-level analysis + subagent discovery ---------------
    for session, export_root, export_error in top_level_exports:
        if export_error is not None or export_root is None:
            continue
        session_row = as_dict(session)
        session_id = as_text(session_row.get("id"))
        session_title = as_text(session_row.get("title"))
        if session_title:
            discovered_titles[session_id] = session_title

        _analyze_one_session_export(
            session=session,
            export_root=export_root,
            accum=accum,
            min_input_tokens=min_input_tokens,
            min_total_tokens=min_total_tokens,
            min_bytes=min_bytes,
        )

        # Discover subagents by walking task tool parts.
        for _parent_msg_id, sub_id in find_subagent_session_ids_in_export(
            export_root
        ):
            if not sub_id:
                continue
            if sub_id in exported_ids:
                # Already covered (top-level or queued subagent).
                subagent_sessions_skipped_duplicate += 1
                continue
            # Defer to the export phase to avoid mutating `exported_ids`
            # before we finish analyzing the current export.
            pending_subagents.append((session_id, sub_id))

    # --- Phase 3: Subagent export + iterative analysis ------------------
    # Track subagent -> parent mapping (first-seen parent wins).
    subagent_parent_map: dict[str, str] = {}
    for parent_id, sub_id in pending_subagents:
        subagent_parent_map.setdefault(sub_id, parent_id)
    pending: list[tuple[str, str]] = [
        (subagent_parent_map[sub_id], sub_id) for sub_id in subagent_parent_map
    ]

    while pending:
        batch_sessions: list[dict[str, Any]] = []
        batch_seen: set[str] = set()
        for _parent_id, sub_id in pending:
            if sub_id in batch_seen:
                subagent_sessions_skipped_duplicate += 1
                continue
            batch_seen.add(sub_id)
            batch_sessions.append({"id": sub_id, "title": discovered_titles.get(sub_id, "")})

        pending = []
        if not batch_sessions:
            break
        files_total_subagent += len(batch_sessions)

        batch_exports = _export_sessions_parallel(
            sessions=batch_sessions,
            output_dir=output_dir,
            sanitize=sanitize,
            workers=workers,
            is_subagent=True,
            timestamp_filename=timestamp_filename,
        )

        for session, export_root, export_error in batch_exports:
            session_row = as_dict(session)
            sid = as_text(session_row.get("id"))
            if sid:
                exported_ids.add(sid)
            parent_id = subagent_parent_map.get(sid, "")
            if export_error is not None or export_root is None:
                critical_exceptions.append(
                    export_error
                    or {
                        "file": f"kilo export {sid}",
                        "error": "export_root_missing",
                    }
                )
                # Still record the discovery so the report explains why
                # this subagent couldn't be parsed.
                subagent_records.append(
                    {
                        "session_id": sid,
                        "parent_session_id": parent_id,
                        "title": discovered_titles.get(sid, ""),
                        "path": str(
                            output_dir
                            / export_filename(
                                session,
                                sid,
                                is_subagent=True,
                                timestamp_filename=timestamp_filename,
                            )
                        ),
                    }
                )
                continue

            export_paths[sid] = str(
                output_dir
                / export_filename(
                    session, sid, is_subagent=True,
                    timestamp_filename=timestamp_filename,
                )
            )

            # Pull the real title from the freshly exported session.
            real_title = as_text(as_dict(export_root.get("info")).get("title"))
            if real_title:
                session_row["title"] = real_title
                discovered_titles[sid] = real_title

            _analyze_one_session_export(
                session=session,
                export_root=export_root,
                accum=accum,
                min_input_tokens=min_input_tokens,
                min_total_tokens=min_total_tokens,
                min_bytes=min_bytes,
            )

            subagent_records.append(
                {
                    "session_id": sid,
                    "parent_session_id": parent_id,
                    "title": discovered_titles.get(sid, ""),
                    "path": export_paths[sid],
                }
            )

            # Discover recursive subagents spawned from this subagent.
            for next_parent_id, next_sub_id in find_subagent_session_ids_in_export(
                export_root
            ):
                if not next_sub_id:
                    continue
                if next_sub_id in exported_ids:
                    subagent_sessions_skipped_duplicate += 1
                    continue
                subagent_parent_map.setdefault(next_sub_id, next_parent_id or sid)
                pending.append((subagent_parent_map[next_sub_id], next_sub_id))

    # --- Final assembly -------------------------------------------------
    all_high_cost_turns = accum["all_high_cost_turns"]
    all_tool_failures = accum["all_tool_failures"]
    source_totals = accum["source_totals"]
    tool_call_counts = accum["tool_call_counts"]
    tool_failure_counts = accum["tool_failure_counts"]
    tool_output_bytes_acc = accum["tool_output_bytes_acc"]
    invalid_tool_attempts = accum["invalid_tool_attempts"]
    session_summaries = accum["session_summaries"]
    session_diffs = accum["session_diffs"]
    truncated_rows = accum["truncated_rows"]
    messages_total = accum["messages_total"]
    assistant_messages_total = accum["assistant_messages_total"]
    files_parsed = accum["files_parsed"]

    files_total = files_total_top_level + files_total_subagent

    all_high_cost_turns.sort(
        key=lambda row: (
            -(as_int(as_dict(row.get("tokens")).get("total")) or 0),
            -(as_int(as_dict(row.get("tokens")).get("input")) or 0),
            as_text(row.get("file")),
            as_int(row.get("_offset")) or 0,
            as_text(row.get("message_id")),
        )
    )
    all_tool_failures.sort(
        key=lambda row: (
            as_text(row.get("file")),
            as_int(row.get("_offset")) or 0,
            as_text(row.get("message_id")),
            as_text(row.get("call_id")),
            as_text(row.get("tool")),
        )
    )
    session_summaries.sort(key=lambda row: -(row.get("total_cost") or 0))
    subagent_records.sort(
        key=lambda row: (
            as_text(row.get("parent_session_id")),
            as_text(row.get("session_id")),
        )
    )

    for row in all_high_cost_turns:
        row.pop("_offset", None)
    for row in all_tool_failures:
        row.pop("_offset", None)

    source_total_rows = [
        {"source": source, "count": values["count"], "bytes": values["bytes"]}
        for source, values in source_totals.items()
    ]
    source_total_rows.sort(
        key=lambda row: (
            -(as_int(row.get("bytes")) or 0),
            -(as_int(row.get("count")) or 0),
            as_text(row.get("source")),
        )
    )

    tool_stats: list[dict[str, Any]] = []
    for tool_name in tool_call_counts:
        call_count = tool_call_counts[tool_name]
        failure_count = tool_failure_counts[tool_name]
        failure_rate = failure_count / call_count if call_count > 0 else 0.0
        tool_stats.append(
            {
                "tool": tool_name,
                "calls": call_count,
                "failures": failure_count,
                "failure_rate": f"{failure_rate * 100:.1f}%",
                "total_output_bytes": tool_output_bytes_acc[tool_name],
            }
        )
    tool_stats.sort(
        key=lambda row: (
            -(row["failures"] / row["calls"]) if row["calls"] > 0 else 0.0,
            -row["failures"],
            row["tool"],
        )
    )

    invalid_tool_summary: list[dict[str, Any]] = []
    for bucket in invalid_tool_attempts.values():
        invalid_tool_summary.append(
            {
                "requested_tool": bucket["requested_tool"],
                "count": bucket["count"],
                "session_count": len(bucket["session_ids"]),
                "example_error": bucket["example_error"],
                "example_session_id": bucket["example_session_id"],
            }
        )
    invalid_tool_summary.sort(
        key=lambda row: (
            -as_int(row.get("count")) or 0,
            -as_int(row.get("session_count")) or 0,
            as_text(row.get("requested_tool")),
        )
    )

    invalid_tool_total = sum(row["count"] for row in invalid_tool_summary)

    return {
        "report_meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "files_total": files_total,
            "files_parsed": files_parsed,
            "files_failed": files_total - files_parsed,
            "top_level_sessions": files_total_top_level,
            "subagent_sessions": files_total_subagent,
            "subagent_sessions_skipped_duplicate": subagent_sessions_skipped_duplicate,
            "min_input_tokens": min_input_tokens,
            "min_total_tokens": min_total_tokens,
            "min_bytes": min_bytes,
            "sanitize": sanitize,
            "workers": workers,
            "output_dir": str(output_dir),
        },
        "summary": {
            "messages_total": messages_total,
            "assistant_messages_total": assistant_messages_total,
            "high_cost_turns_total": len(all_high_cost_turns),
            "tool_failures_total": len(all_tool_failures),
            "source_totals_total": len(source_total_rows),
            "invalid_tool_calls_total": invalid_tool_total,
            "truncated_outputs_total": len(truncated_rows),
            "session_diffs_total": len(session_diffs),
        },
        "session_summary": session_summaries,
        "subagent_sessions": subagent_records,
        "context_bloat": all_high_cost_turns,
        "tool_failures": all_tool_failures,
        "tool_stats": tool_stats,
        "source_totals": source_total_rows,
        "critical_exceptions": critical_exceptions,
        "export_paths": export_paths,
        "invalid_tool_summary": invalid_tool_summary,
        "session_diffs": session_diffs,
        "truncated_outputs": truncated_rows,
    }


def format_semikv(row: dict[str, Any], keys: list[str]) -> str:
    """Format selected row fields as semicolon-separated key/value pairs."""
    chunks: list[str] = []
    for key in keys:
        value = row.get(key)
        if isinstance(value, list):
            rendered = ",".join(as_text(item) for item in value)
        elif isinstance(value, dict):
            rendered = json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        else:
            rendered = as_text(value)
        rendered = rendered.replace("\n", " ").replace("\r", " ")
        chunks.append(f"{key}={rendered}")
    return "; ".join(chunks)


def compact_output(report: dict[str, Any], args: argparse.Namespace) -> str:
    """Render compact output sections for LLM-friendly ingestion."""
    lines: list[str] = []
    start, end = resolve_window(args)

    top_bloat = as_list(report.get("context_bloat"))[: args.top_turns]
    top_failures = as_list(report.get("tool_failures"))[: args.top_tool_failures]
    top_sessions = as_list(report.get("session_summary"))[: args.top_sessions]
    top_diffs = as_list(report.get("session_diffs"))[: args.top_diffs]
    top_truncated = as_list(report.get("truncated_outputs"))[: args.top_truncated]

    lines.append("<report_meta>")
    lines.append(
        format_semikv(
            {
                **as_dict(report.get("report_meta")),
                "format": "compact",
                "top_turns": args.top_turns,
                "top_tool_failures": args.top_tool_failures,
                "top_sessions": args.top_sessions,
                "top_diffs": args.top_diffs,
                "top_truncated": args.top_truncated,
                "last": args.last,
                "days": args.days,
                "start_date": args.start_date or start.date().isoformat(),
                "end_date": args.end_date or end.date().isoformat(),
                "session_search": args.session_search,
                "session_limit": args.session_limit,
                "all_projects": args.all_projects,
            },
            [
                "generated_at",
                "format",
                "files_total",
                "files_parsed",
                "files_failed",
                "top_turns",
                "top_tool_failures",
                "top_sessions",
                "top_diffs",
                "top_truncated",
                "last",
                "days",
                "start_date",
                "end_date",
                "session_search",
                "session_limit",
                "all_projects",
                "min_input_tokens",
                "min_total_tokens",
                "min_bytes",
                "sanitize",
                "workers",
                "output_dir",
                "top_level_sessions",
                "subagent_sessions",
                "subagent_sessions_skipped_duplicate",
            ],
        )
    )
    lines.append("</report_meta>")

    lines.append("<exports>")
    export_paths = as_dict(report.get("export_paths"))
    if not export_paths:
        lines.append("none")
    for sid, path in sorted(export_paths.items()):
        lines.append(format_semikv({"session_id": sid, "path": path}, ["session_id", "path"]))
    lines.append("</exports>")

    lines.append("<summary>")
    lines.append(
        format_semikv(
            as_dict(report.get("summary")),
            [
                "messages_total",
                "assistant_messages_total",
                "high_cost_turns_total",
                "tool_failures_total",
                "source_totals_total",
                "invalid_tool_calls_total",
                "truncated_outputs_total",
                "session_diffs_total",
            ],
        )
    )
    lines.append("</summary>")

    lines.append("<session_summary>")
    if not top_sessions:
        lines.append("none")
    for row in top_sessions:
        cost_val = row.get("total_cost", 0.0)
        display_row = {
            **row,
            "total_cost": f"${cost_val:.4f}",
        }
        lines.append(
            format_semikv(
                display_row,
                [
                    "session_id",
                    "title",
                    "total_cost",
                    "total_tokens",
                    "assistant_turns",
                    "duration_ms",
                    "agents",
                    "primary_model",
                    "model_ids",
                    "variants",
                    "failure_count",
                    "high_cost_turns",
                    "invalid_tool_calls",
                    "truncated_outputs",
                ],
            )
        )
    lines.append("</session_summary>")

    lines.append("<subagent_sessions>")
    subagent_records = as_list(report.get("subagent_sessions"))
    if not subagent_records:
        lines.append("none")
    for row in subagent_records:
        lines.append(
            format_semikv(
                row,
                [
                    "session_id",
                    "parent_session_id",
                    "title",
                    "path",
                ],
            )
        )
    lines.append("</subagent_sessions>")

    lines.append("<context_bloat>")
    if not top_bloat:
        lines.append("none")
    for row in top_bloat:
        tokens = as_dict(row.get("tokens"))
        lines.append(
            format_semikv(
                {
                    "file": row.get("file"),
                    "session_title": row.get("session_title"),
                    "message_id": row.get("message_id"),
                    "time": row.get("time"),
                    "role": row.get("role"),
                    "agent": row.get("agent", ""),
                    "cost": row.get("cost", 0.0),
                    "parent_id": row.get("parent_id"),
                    "input_tokens": tokens.get("input", 0),
                    "output_tokens": tokens.get("output", 0),
                    "total_tokens": tokens.get("total", 0),
                    "reasoning_tokens": tokens.get("reasoning", 0),
                    "cache_read": tokens.get("cache_read", 0),
                    "cache_write": tokens.get("cache_write", 0),
                    "synthetic_content_count": row.get("synthetic_content_count", 0),
                    "tool_part_count": row.get("tool_part_count", 0),
                    "tool_names": row.get("tool_names", []),
                    "large_tool_outputs": [
                        f"{as_dict(item).get('tool')}:{as_dict(item).get('bytes')}"
                        for item in as_list(row.get("large_tool_outputs"))
                    ],
                    "large_apply_patch_input_sizes": row.get(
                        "large_apply_patch_input_sizes",
                        [],
                    ),
                    "large_diff_patch_sizes": row.get("large_diff_patch_sizes", []),
                    "file_part_count": row.get("file_part_count", 0),
                    "probable_sources": row.get("probable_sources", []),
                },
                [
                    "file",
                    "session_title",
                    "message_id",
                    "time",
                    "role",
                    "agent",
                    "cost",
                    "parent_id",
                    "input_tokens",
                    "output_tokens",
                    "total_tokens",
                    "reasoning_tokens",
                    "cache_read",
                    "cache_write",
                    "synthetic_content_count",
                    "tool_part_count",
                    "tool_names",
                    "large_tool_outputs",
                    "large_apply_patch_input_sizes",
                    "large_diff_patch_sizes",
                    "file_part_count",
                    "probable_sources",
                ],
            )
        )
    lines.append("</context_bloat>")

    lines.append("<tool_failures>")
    if not top_failures:
        lines.append("none")
    for row in top_failures:
        lines.append(
            format_semikv(
                row,
                [
                    "file",
                    "session_title",
                    "message_id",
                    "call_id",
                    "tool",
                    "agent",
                    "status",
                    "exit_code",
                    "title",
                    "truncated",
                    "classification",
                    "cause_excerpt",
                ],
            )
        )
    lines.append("</tool_failures>")

    lines.append("<tool_stats>")
    tool_stats = as_list(report.get("tool_stats"))
    if not tool_stats:
        lines.append("none")
    for row in tool_stats:
        lines.append(
            format_semikv(
                row,
                ["tool", "calls", "failures", "failure_rate", "total_output_bytes"],
            )
        )
    lines.append("</tool_stats>")

    lines.append("<invalid_tool_calls>")
    invalid_tool_summary = as_list(report.get("invalid_tool_summary"))
    if not invalid_tool_summary:
        lines.append("none")
    for row in invalid_tool_summary:
        lines.append(
            format_semikv(
                row,
                [
                    "requested_tool",
                    "count",
                    "session_count",
                    "example_error",
                    "example_session_id",
                ],
            )
        )
    lines.append("</invalid_tool_calls>")

    lines.append("<source_totals>")
    source_totals = as_list(report.get("source_totals"))
    if not source_totals:
        lines.append("none")
    for row in source_totals:
        lines.append(format_semikv(row, ["source", "count", "bytes"]))
    lines.append("</source_totals>")

    lines.append("<session_diffs>")
    if not top_diffs:
        lines.append("none")
    for row in top_diffs:
        lines.append(
            format_semikv(
                row,
                [
                    "session_id",
                    "session_title",
                    "file",
                    "additions",
                    "deletions",
                    "status",
                ],
            )
        )
    lines.append("</session_diffs>")

    lines.append("<truncated_outputs>")
    if not top_truncated:
        lines.append("none")
    for row in top_truncated:
        lines.append(
            format_semikv(
                row,
                [
                    "file",
                    "session_title",
                    "message_id",
                    "tool",
                    "title",
                    "output_bytes",
                    "agent",
                    "preview",
                    "loaded",
                ],
            )
        )
    lines.append("</truncated_outputs>")

    lines.append("<critical_exceptions>")
    critical_exceptions = as_list(report.get("critical_exceptions"))
    if not critical_exceptions:
        lines.append("none")
    for row in critical_exceptions:
        lines.append(format_semikv(as_dict(row), ["file", "error"]))
    lines.append("</critical_exceptions>")

    return "\n".join(lines)


def main() -> int:
    """Run CLI entry point."""
    args = parse_args()
    output_dir = resolve_output_dir(args)
    sessions, list_errors = load_sessions(args)
    report = analyze_sessions(
        sessions=sessions,
        output_dir=output_dir,
        min_input_tokens=args.min_input_tokens,
        min_total_tokens=args.min_total_tokens,
        min_bytes=args.min_bytes,
        sanitize=args.sanitize,
        workers=args.workers,
        timestamp_filename=args.timestamp_filename,
        initial_exceptions=list_errors,
    )

    if args.format == "json":
        start, end = resolve_window(args)
        payload = {
            **report,
            "report_meta": {
                **as_dict(report.get("report_meta")),
                "format": "json",
                "top_turns": args.top_turns,
                "top_tool_failures": args.top_tool_failures,
                "top_sessions": args.top_sessions,
                "top_diffs": args.top_diffs,
                "top_truncated": args.top_truncated,
                "last": args.last,
                "days": args.days,
                "start_date": args.start_date or start.date().isoformat(),
                "end_date": args.end_date or end.date().isoformat(),
                "session_search": args.session_search,
                "session_limit": args.session_limit,
                "all_projects": args.all_projects,
            },
            "context_bloat": as_list(report.get("context_bloat"))[: args.top_turns],
            "tool_failures": as_list(report.get("tool_failures"))[
                : args.top_tool_failures
            ],
            "session_summary": as_list(report.get("session_summary")),
            "tool_stats": as_list(report.get("tool_stats")),
            "session_diffs": as_list(report.get("session_diffs"))[: args.top_diffs],
            "truncated_outputs": as_list(report.get("truncated_outputs"))[
                : args.top_truncated
            ],
        }
        rendered = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
        print(rendered)
    else:
        rendered = compact_output(report, args)
        print(rendered)

    report_file = report_path(output_dir, args)
    report_file.write_text(rendered, encoding="utf-8")

    if args.no_keep_exports:
        shutil.rmtree(output_dir, ignore_errors=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
