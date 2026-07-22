"""Entry point for the host-standards MCP server.

Indexes coding standards from the configured standards directory
and serves them via Streamable HTTP transport.
"""

from __future__ import annotations

import os
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from host_standards.logging_config import configure_logging
from host_standards.resources import register as register_resources
from host_standards.tools.standards import register as register_standards_tools


def main() -> None:
    host = os.environ.get("MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("MCP_PORT", "8766"))
    standards_dir = os.environ.get(
        "STANDARDS_DIR",
        str(Path.home() / ".config" / "kilo" / "standards"),
    )

    mcp = FastMCP("standards", host=host, port=port)
    configure_logging()

    register_standards_tools(mcp, standards_dir)
    register_resources(mcp, standards_dir)

    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
