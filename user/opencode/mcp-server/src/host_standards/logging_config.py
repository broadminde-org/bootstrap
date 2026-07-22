"""Rotating file handler — nothing to stderr.

The MCP transport owns stdout/stderr for JSON-RPC frames.
A stray print() or log line corrupts the wire.
"""

from __future__ import annotations

import logging
import os
from logging.handlers import RotatingFileHandler


def configure_logging() -> None:
    level = os.environ.get("MCP_LOG_LEVEL", "WARNING").upper()
    log_file = os.environ.get("MCP_LOG_FILE", "")

    root = logging.getLogger()
    root.setLevel(getattr(logging, level, logging.WARNING))

    root.handlers.clear()

    if log_file:
        handler = RotatingFileHandler(
            log_file,
            maxBytes=10 * 1024 * 1024,
            backupCount=5,
        )
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)s %(name)s %(message)s"
            )
        )
        root.addHandler(handler)
    else:
        root.addHandler(logging.NullHandler())
