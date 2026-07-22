"""MCP resources — read-only data views for standards."""

from __future__ import annotations

import json

from mcp.server.fastmcp import FastMCP

from host_standards.tools.standards import StandardsIndex


def register(mcp: FastMCP, standards_dir: str) -> None:
    idx = StandardsIndex(standards_dir)
    idx.reload()

    @mcp.resource("standards://list")
    def list_standards() -> str:
        """Return the index of all available standards."""
        idx.reload()
        entries = [
            {
                "id": s["id"],
                "title": s["title"],
                "summary": s["summary"],
                "line_count": s["line_count"],
            }
            for s in idx._index.values()
        ]
        return json.dumps(sorted(entries, key=lambda x: x["id"]))

    @mcp.resource("standards://{id}")
    def get_standard(id: str) -> str:
        """Return the full content of a standard by ID."""
        idx.reload()
        content = idx.get(id)
        if content is None:
            return json.dumps({"error": f"Standard '{id}' not found"})
        return content
