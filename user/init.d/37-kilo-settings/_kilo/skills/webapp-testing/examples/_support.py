"""Bootstrap local example support (2026-11-23); original licenses retained.

No app text, URLs, console payloads, or screenshots are persisted. Only fixed
metadata/counts are admitted. This is deliberately fail-closed suppression,
not a promise that pattern-based redaction can identify every secret.
"""

import argparse
import json
import os
import sys
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urlsplit

if TYPE_CHECKING:
    from playwright.sync_api import Page


class ScreenedParser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        self.exit(2, "Invalid invocation; inspect documented arguments.\n")


def arguments(description: str, *, local: bool = False) -> argparse.Namespace:
    parser = ScreenedParser(description=description)
    parser.add_argument("--html" if local else "--url", required=True)
    parser.add_argument("--ready-selector", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--action-selector")
    parser.add_argument("--result-selector")
    args = parser.parse_args()
    if bool(args.action_selector) != bool(args.result_selector):
        parser.error("action and result selectors must be supplied together")
    if local:
        html = Path(args.html).resolve(strict=True)
        if not html.is_file():
            raise ValueError("HTML input must be a file")
        args.url = html.as_uri()
    else:
        url = urlsplit(args.url)
        if (
            url.scheme not in {"http", "https"}
            or not url.hostname
            or url.username is not None
            or url.password is not None
            or url.query
            or url.fragment
        ):
            raise ValueError("credential-free HTTP(S) URL required")
        _ = url.port
    directory, name = output_parent(args.output)
    try:
        try:
            os.stat(name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            pass  # Only an absent leaf is admitted; save rechecks exclusively.
        else:
            raise ValueError("output already exists")
    finally:
        os.close(directory)
    return args


def output_parent(path: Path) -> tuple[int, str]:
    absolute = path.absolute()
    if not absolute.name or any(part in {".", ".."} for part in absolute.parts):
        raise ValueError("invalid output path")
    directory = os.open(absolute.anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in absolute.parts[1:-1]:
            child = os.open(
                part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory
            )
            os.close(directory)
            directory = child
        return directory, absolute.name
    except BaseException:
        os.close(directory)
        raise


def save_counts(path: Path, counts: dict[str, int]) -> None:
    """Write a new private file through nonredirected existing directories."""
    directory, name = output_parent(path)
    try:
        descriptor = os.open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(counts, output, sort_keys=True)
            output.write("\n")
    finally:
        os.close(directory)


def exercise(page: "Page", args: argparse.Namespace) -> None:
    from playwright.sync_api import expect

    page.goto(args.url, wait_until="domcontentloaded", timeout=30000)
    expect(page.locator(args.ready_selector)).to_be_visible(timeout=30000)
    if args.action_selector:
        result = page.locator(args.result_selector)
        expect(result).to_be_hidden(timeout=10000)
        page.locator(args.action_selector).click(timeout=10000)
        expect(result).to_be_visible(timeout=10000)


def run(main: Callable[[], None]) -> None:
    try:
        main()
    except Exception:  # noqa: BLE001 - deliberate screened top-level CLI boundary
        # Top-level CLI reporting boundary: Playwright errors can contain URLs,
        # selectors and page content. Do not emit their traceback or message.
        print(
            "Example failed; diagnostics suppressed. Check reviewed inputs/tooling.",
            file=sys.stderr,
        )
        sys.exit(1)
