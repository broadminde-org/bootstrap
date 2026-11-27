#!/usr/bin/env python3
"""Create only SKILL.md in an absent destination under an existing directory.

Bootstrap modification, 2026-11-23. Upstream provenance: ../local.patch.
"""

import os
import signal
import stat
import sys
import threading
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

from quick_validate import SafeArgumentParser, checked_path, validate_name

SKILL_TEMPLATE = """---
name: "{skill_name}"
description: "TODO: Describe this skill and the concrete tasks that select it."
---

# {skill_title}

## Workflow

TODO: Add task-specific instructions, boundaries, and acceptance checks.
Add only resources needed by this workflow and link their exact local paths.
"""


@contextmanager
def protected_signals() -> Iterator[set[signal.Signals]]:
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
    try:
        yield previous
    finally:
        # Pending callbacks record here; the caller checks under its cleanup guard.
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


@contextmanager
def interruption_handlers(cleanup: Callable[[], None]) -> Iterator[Callable[[], None]]:
    previous = {}
    pending = None
    delivered = False

    def record(signum: int, _frame: object) -> None:
        nonlocal pending
        # Kernel remasking cannot suppress already queued CPython callbacks.
        # Callbacks only record; explicit checkpoints raise outside cleanup.
        if pending is None:
            pending = signum

    def check() -> None:
        nonlocal delivered
        if pending is not None and not delivered:
            delivered = True
            if pending == signal.SIGINT:
                raise KeyboardInterrupt
            raise SystemExit(128 + pending)

    def drain(mask: set[signal.Signals]) -> None:
        # Consume only helper-deferred signals, not intentionally blocked caller
        # signals. One bounded wait per standard signal; no polling/flood loop.
        for signum in (signal.SIGINT, signal.SIGTERM):
            if signum not in mask:
                try:
                    received = signal.sigtimedwait({signum}, 0)
                except (OSError, ValueError, NotImplementedError):
                    cleanup()
                    raise
                if received is not None:
                    record(received.si_signo, None)

    try:
        with protected_signals() as previous_mask:
            for signum in (signal.SIGINT, signal.SIGTERM):
                previous[signum] = signal.getsignal(signum)
                signal.signal(signum, record)
            drain(previous_mask)  # Required primitive admission before any writes.
        yield check
    finally:
        try:
            if pending is not None and not delivered:
                cleanup()
                check()
        finally:
            with protected_signals() as previous_mask:
                try:
                    try:
                        try:
                            drain(previous_mask)
                        finally:
                            if signal.SIGINT in previous:
                                signal.signal(signal.SIGINT, previous[signal.SIGINT])
                    finally:
                        try:
                            drain(previous_mask)
                        finally:
                            if signal.SIGTERM in previous:
                                signal.signal(signal.SIGTERM, previous[signal.SIGTERM])
                finally:
                    try:
                        drain(previous_mask)
                    finally:
                        if pending is not None and not delivered:
                            cleanup()
                            check()


def init_skill(skill_name: str, path: str | Path) -> Path | None:
    """Validate before writes; do not create parents, examples, or overwrite skills."""
    try:
        validate_name(skill_name)
        parent = checked_path(path)
        if not parent.is_dir():
            raise ValueError("Output parent must be an existing directory")
        destination = checked_path(parent / skill_name)
        if os.path.lexists(destination):
            raise ValueError("Destination already exists; it was left unchanged")
        content = SKILL_TEMPLATE.format(
            skill_name=skill_name,
            skill_title=" ".join(word.capitalize() for word in skill_name.split("-")),
        )
    except (OSError, ValueError):
        print("Initialization refused: invalid name/path or existing destination")
        return None

    if (
        sys.platform != "linux"
        or os.name != "posix"
        or not hasattr(signal, "pthread_sigmask")
        or not hasattr(signal, "sigtimedwait")
        or not hasattr(os, "O_DIRECTORY")
        or not hasattr(os, "O_NOFOLLOW")
        or not {os.open, os.mkdir, os.stat, os.unlink, os.rmdir} <= os.supports_dir_fd
        or os.stat not in os.supports_follow_symlinks
        or threading.current_thread() is not threading.main_thread()
        or threading.active_count() != 1
    ):
        print("Initialization refused: required Linux/single-thread safety unavailable")
        return None
    handled = {signal.SIGINT, signal.SIGTERM}
    if signal.pthread_sigmask(signal.SIG_BLOCK, set()) & handled or any(
        signal.getsignal(signum) == signal.SIG_IGN for signum in handled
    ):
        print("Initialization refused: incompatible prior signal state; left unchanged")
        return None

    # Keep identities pinned until cleanup finishes; never infer ownership by name.
    parent_fd = directory_fd = file_fd = None
    reserved = False
    cleaned = False

    def cleanup() -> None:
        nonlocal cleaned
        if cleaned:
            return
        with protected_signals():
            incomplete = reserved and directory_fd is None
            if directory_fd is not None:
                if file_fd is not None:
                    try:
                        owned = os.fstat(file_fd)
                        current = os.stat(
                            "SKILL.md", dir_fd=directory_fd, follow_symlinks=False
                        )
                        if stat.S_ISREG(current.st_mode) and (
                            current.st_dev,
                            current.st_ino,
                        ) == (owned.st_dev, owned.st_ino):
                            os.unlink("SKILL.md", dir_fd=directory_fd)
                        else:
                            incomplete = True
                    except FileNotFoundError:
                        pass  # Already absent; no replacement to remove.
                    except OSError:
                        incomplete = True
                try:
                    owned = os.fstat(directory_fd)
                    current = os.stat(
                        skill_name, dir_fd=parent_fd, follow_symlinks=False
                    )
                    if stat.S_ISDIR(current.st_mode) and (
                        current.st_dev,
                        current.st_ino,
                    ) == (owned.st_dev, owned.st_ino):
                        os.rmdir(skill_name, dir_fd=parent_fd)
                    else:
                        incomplete = True
                except FileNotFoundError:
                    pass
                except OSError:
                    incomplete = True
            cleaned = True
        if incomplete:
            print("Initialization cleanup incomplete; preserved unknown state")

    try:
        with interruption_handlers(cleanup) as check_interruption:
            try:
                check_interruption()
                with protected_signals():
                    parent_fd = os.open(
                        parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
                    )
                check_interruption()
                with protected_signals():
                    os.mkdir(skill_name, mode=0o700, dir_fd=parent_fd)
                    reserved = True
                    directory_fd = os.open(
                        skill_name,
                        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                        dir_fd=parent_fd,
                    )
                check_interruption()
                with protected_signals():
                    file_fd = os.open(
                        "SKILL.md",
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                        0o600,
                        dir_fd=directory_fd,
                    )
                check_interruption()
                # Writes are interruptible; retain the same descriptor for cleanup.
                remaining = content.encode("utf-8")
                while remaining:
                    check_interruption()
                    written = os.write(file_fd, remaining)
                    check_interruption()
                    if written == 0:
                        raise OSError("Initialization write made no progress")
                    remaining = remaining[written:]
            except BaseException:
                cleanup()
                raise
    finally:
        try:
            if file_fd is not None:
                os.close(file_fd)
        except OSError:
            print("Initialization cleanup incomplete; descriptor release failed")
            raise
        finally:
            try:
                if directory_fd is not None:
                    os.close(directory_fd)
            except OSError:
                print("Initialization cleanup incomplete; descriptor release failed")
                raise
            finally:
                try:
                    if parent_fd is not None:
                        os.close(parent_fd)
                except OSError:
                    print(
                        "Initialization cleanup incomplete; descriptor release failed"
                    )
                    raise
    print("Created instruction-only skill; complete its TODOs before use")
    return destination


def main() -> None:
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("skill_name")
    parser.add_argument(
        "--path", required=True, help="Existing output parent directory"
    )
    args = parser.parse_args()
    try:
        result = init_skill(args.skill_name, args.path)
    except (OSError, ValueError, NotImplementedError):
        print("Initialization failed; inspect the owned destination before retrying")
        raise SystemExit(1) from None
    raise SystemExit(0 if result else 1)


if __name__ == "__main__":
    main()
