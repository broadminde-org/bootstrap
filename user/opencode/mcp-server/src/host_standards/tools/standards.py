"""Standards index and MCP tools: search, get, list."""

from __future__ import annotations

import json
import re
from pathlib import Path

from mcp.server.fastmcp import FastMCP


class StandardsIndex:
    """In-memory index of all standards markdown files."""

    def __init__(self, standards_dir: str) -> None:
        self._standards_dir = Path(standards_dir)
        self._index: dict[str, dict] = {}
        self._content_cache: dict[str, str] = {}
        self._reload()

    def _reload(self) -> None:
        """(Re)index all .md files in the standards directory."""
        self._index.clear()
        self._content_cache.clear()

        if not self._standards_dir.is_dir():
            return

        for md_file in sorted(self._standards_dir.rglob("*.md")):
            rel_path = md_file.relative_to(self._standards_dir)
            file_id = str(rel_path.with_suffix("")).replace("/", "-")

            try:
                content = md_file.read_text()
            except Exception:
                continue

            self._content_cache[file_id] = content

            title = self._extract_title(content)
            lines = content.strip().split("\n")
            summary = self._extract_summary(content, title)

            self._index[file_id] = {
                "id": file_id,
                "title": title,
                "summary": summary,
                "line_count": len(lines),
                "path": str(rel_path),
            }

    def _extract_title(self, content: str) -> str:
        for line in content.split("\n"):
            m = re.match(r"^#\s+(.+)", line)
            if m:
                return m.group(1).strip()
        return "Untitled"

    def _extract_summary(self, content: str, title: str) -> str:
        scope_match = re.search(r"##\s+Scope\s*\n+\s*(.+)", content)
        if scope_match:
            scope_line = scope_match.group(1).strip()
            return scope_line

        paragraphs = [p.strip() for p in content.split("\n\n") if p.strip()]
        for p in paragraphs:
            if not p.startswith("#") and not p.startswith("-") and len(p) > 20:
                return p[:150] + ("..." if len(p) > 150 else "")
            if p.startswith("- "):
                return p[:150] + ("..." if len(p) > 150 else "")
        return title

    def reload(self) -> None:
        """Public reload — reindex from disk."""
        self._reload()

    def search(self, query: str) -> list[dict]:
        """Keyword search across titles and content. Returns ranked results."""
        terms = query.lower().split()
        scored: list[tuple[int, dict]] = []

        for file_id, entry in self._index.items():
            title_lower = entry["title"].lower()
            content = self._content_cache.get(file_id, "")
            content_lower = content.lower()

            score = 0
            for term in terms:
                if term in title_lower:
                    score += 30
                if term in content_lower:
                    score += 1

            if score > 0:
                snippet = self._snippet(content, terms)
                scored.append((score, {
                    "id": entry["id"],
                    "title": entry["title"],
                    "summary": entry["summary"],
                    "snippet": snippet,
                    "score": score,
                    "line_count": entry["line_count"],
                    "path": entry["path"],
                }))

        scored.sort(key=lambda x: (-x[0], x[1]["title"]))
        return [item for _, item in scored[:12]]

    def get(self, file_id: str) -> str | None:
        """Return full content of a standard by ID."""
        return self._content_cache.get(file_id)

    def list_all(self) -> list[dict]:
        """Return compact index of all standards."""
        return sorted(self._index.values(), key=lambda x: x["id"])

    def _snippet(self, content: str, terms: list[str]) -> str:
        for term in terms:
            idx = content.lower().find(term)
            if idx >= 0:
                start = max(0, idx - 60)
                end = min(len(content), idx + len(term) + 100)
                snippet = content[start:end].strip()
                if start > 0:
                    snippet = "..." + snippet
                if end < len(content):
                    snippet = snippet + "..."
                return snippet.replace("\n", " ")
        return ""


def register(mcp: FastMCP, standards_dir: str) -> None:
    idx = StandardsIndex(standards_dir)

    @mcp.tool(
        name="search",
        description=(
            "Search coding standards, guidelines, and reference material "
            "by keyword. Returns matching standards ranked by relevance "
            "with compact snippets. Use standards_get to read full "
            "content of a specific match."
        ),
    )
    async def search(query: str) -> str:
        """Search standards by keyword.

        Args:
            query: Search query. Multi-word queries use AND matching
                   against document titles and content.
        """
        idx.reload()
        results = idx.search(query)
        return json.dumps(results)

    @mcp.tool(
        name="get",
        description=(
            "Retrieve the full content of a coding standard by ID. "
            "Use after standards_search to read a specific match. "
            "IDs are derived from the file path (e.g. 'shell-environment', "
            "'python-style')."
        ),
    )
    async def get(id: str) -> str:
        """Get full content of a standard.

        Args:
            id: Standard ID, e.g. 'shell-environment', 'python-style'.
        """
        idx.reload()
        content = idx.get(id)
        if content is None:
            return json.dumps({"error": f"Standard '{id}' not found"})
        return content

    @mcp.tool(
        name="list",
        description=(
            "List all available coding standards. Returns an index "
            "of IDs, titles, summaries, and line counts. Use "
            "standards_get to read full content of any standard."
        ),
    )
    async def list() -> str:
        """List all available standards with summaries."""
        idx.reload()
        entries = [
            {
                "id": s["id"],
                "title": s["title"],
                "summary": s["summary"],
                "line_count": s["line_count"],
            }
            for s in idx.list_all()
        ]
        return json.dumps(entries)
