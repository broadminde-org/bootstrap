#!/usr/bin/env python3
"""Conditional single-thread Linux supervision; prefer tracked/project tooling.

Bootstrap local repair, 2026-11-23, of ComposioHQ/awesome-claude-skills
webapp-testing. Original licensing is retained in ../LICENSE and ../LICENSE.txt.
Commands are trusted operator input, not sandboxed. Child output is drained
and suppressed entirely: no raw command, HTTP body, or child diagnostic is
emitted or stored. Read SKILL.md before authorizing an invocation.
"""

import argparse
import ctypes
import hashlib
import http.client
import math
import os
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit


TERMINATION_SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


class SignalInterruption(Exception):
    """Escape selector EINTR retries and retain the received signal number."""


class ScreenedParser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        self.exit(2, "Invalid invocation; inspect documented arguments.\n")


def preflight() -> None:
    """Reject unsupported wait/signal platforms and SIGCHLD auto-reaping."""
    if (
        sys.platform != "linux"
        or os.uname().machine not in {"x86_64", "aarch64"}
        or ctypes.sizeof(ctypes.c_void_p) != 8
        or ctypes.sizeof(ctypes.c_ulong) != 8
        or not all(
            hasattr(os, name)
            for name in (
                "waitid",
                "waitpid",
                "killpg",
                "P_PID",
                "WEXITED",
                "WNOHANG",
                "WNOWAIT",
                "CLD_EXITED",
                "CLD_KILLED",
                "CLD_DUMPED",
            )
        )
        or not hasattr(os, "waitstatus_to_exitcode")
        or not hasattr(signal, "pthread_sigmask")
        or threading.current_thread() is not threading.main_thread()
        or threading.active_count() != 1
        or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL
    ):
        raise RuntimeError("required standalone Linux process primitives unavailable")
    # Native SA_NOCLDWAIT is invisible to getsignal(). Admit only the known
    # 64-bit glibc sigaction ABI; never guess another platform's structure.
    libc_version = os.confstr("CS_GNU_LIBC_VERSION")
    if not libc_version or not libc_version.startswith("glibc "):
        raise RuntimeError("required sigaction ABI unavailable")

    class Sigaction(ctypes.Structure):
        _fields_ = [
            ("handler", ctypes.c_void_p),
            ("mask", ctypes.c_ulong * 16),
            ("flags", ctypes.c_int),
            ("restorer", ctypes.c_void_p),
        ]

    if (
        ctypes.sizeof(Sigaction) != 152
        or Sigaction.mask.offset != 8
        or Sigaction.flags.offset != 136
        or Sigaction.restorer.offset != 144
    ):
        raise RuntimeError("required sigaction layout unavailable")
    libc = ctypes.CDLL(None, use_errno=True)
    action = Sigaction()
    query = libc.sigaction
    query.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(Sigaction)]
    query.restype = ctypes.c_int
    if query(signal.SIGCHLD, None, ctypes.byref(action)) != 0:
        raise RuntimeError("SIGCHLD state unavailable")
    if action.handler is not None or action.flags & 2:  # Linux SA_NOCLDWAIT
        raise RuntimeError("SIGCHLD reaping is incompatible with owned groups")
    try:
        os.waitid(os.P_PID, os.getpid(), os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except ChildProcessError:
        # Our own PID is not our child; this validates the kernel's option set.
        return
    raise RuntimeError("unexpected wait identity during preflight")


def observe(process: subprocess.Popen) -> int | None:
    """Observe exit without releasing the leader PID that pins its group ID."""
    if process.returncode is not None:
        raise RuntimeError("owned leader was already reaped")
    try:
        status = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except ChildProcessError as error:
        raise RuntimeError("owned leader identity unavailable") from error
    if status is None:
        return None
    if status.si_pid != process.pid:
        raise RuntimeError("unexpected owned leader identity")
    if status.si_code == os.CLD_EXITED:
        return status.si_status
    if status.si_code in {os.CLD_KILLED, os.CLD_DUMPED}:
        return -status.si_status
    raise RuntimeError("unexpected owned leader wait state")


def endpoint(value: str) -> tuple[str, int, str]:
    """Accept only credential-free, local plain HTTP readiness endpoints."""
    parsed = urlsplit(value)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"localhost", "127.0.0.1", "::1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("readiness requires local HTTP without credentials/query")
    port = 80 if parsed.port is None else parsed.port
    if not 1 <= port <= 65535:
        raise ValueError("invalid readiness port")
    return parsed.hostname, port, parsed.path or "/"


def admit_port(host: str, port: int) -> None:
    """Reject existing listeners without terminating or attaching to them."""
    addresses = ("127.0.0.1", "::1") if host == "localhost" else (host,)
    for address in addresses:
        family = socket.AF_INET6 if ":" in address else socket.AF_INET
        with socket.socket(family, socket.SOCK_STREAM) as probe:
            if family == socket.AF_INET6:
                probe.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            probe.bind((address, port))


def http_ready(target: tuple[str, int, str], digest: str, budget: float) -> bool:
    """Require a bounded HTTP 200 body matching the reviewed app identity."""
    if budget <= 0:
        return False
    host, port, path = target
    connection = http.client.HTTPConnection(host, port, timeout=0.5)
    previous = signal.signal(signal.SIGALRM, probe_timeout)
    signal.setitimer(signal.ITIMER_REAL, min(0.5, budget))
    try:
        connection.request("GET", path, headers={"Connection": "close"})
        response = connection.getresponse()
        body = response.read(65537)
        return (
            response.status == 200
            and len(body) <= 65536
            and hashlib.sha256(body).hexdigest() == digest
        )
    except InterruptedError:
        raise
    except (OSError, http.client.HTTPException, TimeoutError):
        return False
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
        connection.close()


def probe_timeout(_signum: int, _frame: object) -> None:
    raise TimeoutError("HTTP probe wall deadline")


def drain(selector: selectors.BaseSelector, timeout: float = 0.05) -> None:
    """Bound each read and discard before any emission or persistent storage."""
    for key, _ in selector.select(timeout):
        chunk = os.read(key.fileobj.fileno(), 65536)
        if not chunk:
            selector.unregister(key.fileobj)
            key.fileobj.close()


def spawn(
    command: str | list[str],
    owned: list[subprocess.Popen],
    selector: selectors.BaseSelector,
) -> subprocess.Popen:
    preflight()
    # Close the signal-delivery gap between creating and recording ownership.
    blocked = signal.pthread_sigmask(signal.SIG_BLOCK, TERMINATION_SIGNALS)

    def child_signals() -> None:
        # preexec_fn is only safe under the standalone single-thread contract.
        # Reset inherited Python handlers before unblocking graceful termination.
        for sig in TERMINATION_SIGNALS:
            signal.signal(sig, signal.SIG_DFL)
        signal.pthread_sigmask(
            signal.SIG_SETMASK, blocked.difference(TERMINATION_SIGNALS)
        )

    try:
        process = subprocess.Popen(
            command,
            shell=isinstance(command, str),
            start_new_session=True,
            preexec_fn=child_signals,  # noqa: PLW1509 - single-thread contract above
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        owned.append(process)
        os.set_blocking(process.stdout.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ)
        return process
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, blocked)


def cleanup(owned: list[subprocess.Popen], selector: selectors.BaseSelector) -> None:
    # An unreaped, waitable leader pins its numeric group identity, even after
    # exit. Revalidate before EVERY signal; no external reaper is supported.
    failed = False
    for process in owned:
        try:
            observe(process)
            if process.stdout and not process.stdout.closed:
                try:
                    selector.get_key(process.stdout)
                except KeyError:
                    # Recover a pipe whose startup registration failed, without
                    # losing descendant output/EOF observation during cleanup.
                    os.set_blocking(process.stdout.fileno(), False)
                    selector.register(process.stdout, selectors.EVENT_READ)
        except (OSError, RuntimeError, ValueError, KeyError):
            failed = True
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for process in reversed(owned):
            try:
                observe(process)
            except (OSError, RuntimeError):
                failed = True
                continue
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                continue
            except OSError:
                failed = True
        if sig == signal.SIGTERM:
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if not selector.get_map():
                    try:
                        if all(observe(process) is not None for process in owned):
                            break
                    except (OSError, RuntimeError):
                        failed = True
                        break
                try:
                    drain(selector)
                except OSError:
                    failed = True
                    break
    # A dead leader does not imply its descendants have finished KILL. Drain
    # registered inherited pipes to EOF, bounded, while ALL leaders stay pinned.
    deadline = time.monotonic() + 5
    while selector.get_map() and time.monotonic() < deadline:
        try:
            drain(selector)
        except OSError:
            failed = True
            break
    if selector.get_map():
        failed = True
    for process in owned:
        try:
            deadline = time.monotonic() + 5
            while observe(process) is None:
                if time.monotonic() >= deadline:
                    raise TimeoutError("owned leader reap deadline")
                drain(selector)
            # All group signalling is over before the first identity is freed.
            pid, status = os.waitpid(process.pid, 0)
            if pid != process.pid:
                raise RuntimeError("unexpected reaped leader identity")
            process.returncode = os.waitstatus_to_exitcode(status)
        except (OSError, RuntimeError, TimeoutError):
            failed = True
        finally:
            if process.stdout and not process.stdout.closed:
                try:
                    process.stdout.close()
                except OSError:
                    failed = True
    if failed:
        raise RuntimeError("owned process identity or cleanup unavailable")


def interrupted(signum: int, _frame: object) -> None:
    # selectors.select() retries InterruptedError, so use a distinct exception.
    raise SignalInterruption(signum)


def main() -> int:
    parser = ScreenedParser(description=__doc__)
    parser.add_argument("--server", action="append", required=True)
    parser.add_argument("--ready-url", action="append", required=True)
    parser.add_argument("--ready-sha256", action="append", required=True)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--command-timeout", type=float, default=120)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not len(args.server) == len(args.ready_url) == len(
        args.ready_sha256
    ):
        parser.error("command and matching server/readiness pairs required")
    if any(
        not math.isfinite(t) or t <= 0 for t in (args.timeout, args.command_timeout)
    ):
        parser.error("timeouts must be finite and positive")
    if any(
        len(d) != 64 or any(c not in "0123456789abcdef" for c in d)
        for d in args.ready_sha256
    ):
        parser.error("expected lowercase SHA-256 digests required")
    try:
        preflight()
        targets = [endpoint(url) for url in args.ready_url]
        if len({port for _, port, _ in targets}) != len(targets):
            raise ValueError("distinct server ports required")
        for host, port, _ in targets:
            admit_port(host, port)
    except (AttributeError, OSError, RuntimeError, ValueError):
        print(
            "Platform/readiness unavailable or input invalid; nothing started.",
            file=sys.stderr,
        )
        return 1

    owned: list[subprocess.Popen] = []
    selector = selectors.DefaultSelector()
    original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, TERMINATION_SIGNALS)
    handlers = {sig: signal.getsignal(sig) for sig in TERMINATION_SIGNALS}
    result = 1
    try:
        for sig in handlers:
            signal.signal(sig, interrupted)
        # Pending signals may raise here; ownership and cleanup are already ready.
        signal.pthread_sigmask(
            signal.SIG_SETMASK, original_mask.difference(TERMINATION_SIGNALS)
        )
        deadline = time.monotonic() + args.timeout
        servers = [spawn(server, owned, selector) for server in args.server]
        while True:
            if any(observe(process) is not None for process in servers):
                raise RuntimeError("server exited")
            if time.monotonic() >= deadline:
                raise TimeoutError("startup deadline")
            drain(selector)
            ready = True
            for target, digest in zip(targets, args.ready_sha256, strict=True):
                if time.monotonic() >= deadline:
                    raise TimeoutError("startup deadline")
                drain(selector, 0)
                ready = (
                    http_ready(target, digest, deadline - time.monotonic()) and ready
                )
            if time.monotonic() >= deadline:
                raise TimeoutError("startup deadline")
            if ready:
                break
        if any(observe(process) is not None for process in servers):
            raise RuntimeError("server exited after readiness")
        test = spawn(command, owned, selector)
        deadline = time.monotonic() + args.command_timeout
        while (test_status := observe(test)) is None:
            if any(observe(process) is not None for process in servers):
                raise RuntimeError("server exited during command")
            if time.monotonic() >= deadline:
                raise TimeoutError("command deadline")
            drain(selector)
        if any(observe(process) is not None for process in servers):
            raise RuntimeError("server exited at command completion")
        result = test_status if test_status >= 0 else 128 - test_status
    except SignalInterruption as error:
        print("Interrupted; cleaning owned process groups.", file=sys.stderr)
        result = 128 + error.args[0]
    except (
        OSError,
        RuntimeError,
        TimeoutError,
        ValueError,
        subprocess.SubprocessError,
    ):
        print(
            "Run failed; child diagnostics suppressed; cleaning owned groups.",
            file=sys.stderr,
        )
    finally:
        for sig in handlers:
            signal.signal(sig, signal.SIG_IGN)
        try:
            try:
                cleanup(owned, selector)
            except (OSError, RuntimeError):
                print(
                    "Owned group cleanup failed; operator verification required.",
                    file=sys.stderr,
                )
                result = 1
        finally:
            try:
                selector.close()
            finally:
                signal.pthread_sigmask(signal.SIG_BLOCK, TERMINATION_SIGNALS)
                try:
                    for sig, handler in handlers.items():
                        signal.signal(sig, handler)
                finally:
                    signal.pthread_sigmask(signal.SIG_SETMASK, original_mask)
    return result


if __name__ == "__main__":
    sys.exit(main())
