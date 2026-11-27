"""Unexecuted runtime regressions for the production standalone helper.

Bootstrap local addition, 2026-11-23; original skill licenses retained.
Linux/POSIX, stdlib only. Execution requires separate authorization: this
suite creates private temporary state and launches synthetic servers/processes.
It loads helper definitions only for deterministic sentinels, and otherwise
executes the production CLI. It never launches browsers or prepares dependencies.
"""

import ctypes
import hashlib
import json
import os
import runpy
import selectors
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "with_server.py"
BODY = b"synthetic-webapp-identity-v1"
DIGEST = hashlib.sha256(BODY).hexdigest()
SECRET = "SYNTHETIC_ONLY_TOKEN_do_not_emit_47"
RESTORED = b"SUPERVISION_SIGNAL_STATE_RESTORED\n"

# Written only when this suite is separately authorized and executed.
FIXTURE = r"""
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

root, family, role, mode, port = sys.argv[1:]
root = Path(root)
child = None
prefix = root / (family + "-" + role)

def stop(signum, frame):
    prefix.with_suffix(".term").write_text(str(signum))
    if child is not None:
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
if role == "grandchild" and mode == "resistant":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)

stat = Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()
pending = prefix.with_suffix(".pending")
pending.write_text(json.dumps({
    "pid": os.getpid(), "start": stat[19],
    "mask": sorted(int(s) for s in signal.pthread_sigmask(signal.SIG_BLOCK, set()))
}))
pending.replace(prefix.with_suffix(".json"))

if role != "grandchild":
    next_role = "child" if role == "root" else "grandchild"
    child = subprocess.Popen([
        sys.executable, "-B", __file__, str(root), family, next_role, mode, port
    ], stdin=subprocess.DEVNULL)

if role != "root":
    while True:
        signal.pause()

deadline = time.monotonic() + 3
while not (root / (family + "-grandchild.json")).exists():
    if time.monotonic() >= deadline:
        raise SystemExit(8)
    time.sleep(0.01)

if mode == "early":
    raise SystemExit(7)
if mode == "partial":
    deadline = time.monotonic() + 3
    while not (root / "s0.listening").exists():
        if time.monotonic() >= deadline:
            raise SystemExit(9)
        time.sleep(0.01)
    raise SystemExit(7)
if mode == "command":
    (root / (family + ".started")).write_text("started")
    while True:
        signal.pause()

def noise():
    while True:
        os.write(1, b"SYNTHETIC_ONLY_TOKEN_")
        os.write(1, b"do_not_emit_47\n" + b"x" * 8192)
        os.write(2, b"SYNTHETIC_ONLY_TOKEN_do_not_emit_47\n" + b"y" * 8192)

if mode == "noisy":
    threading.Thread(target=noise, daemon=True).start()
if mode == "exit-during-command":
    def exit_after_command():
        deadline = time.monotonic() + 5
        while not (root / "test.started").exists():
            if time.monotonic() >= deadline:
                os._exit(8)
            time.sleep(0.01)
        os._exit(7)
    threading.Thread(target=exit_after_command, daemon=True).start()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (b"wrong-synthetic-app" if mode == "wrong"
                else b"synthetic-webapp-identity-v1")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        return

with http.server.HTTPServer(("127.0.0.1", int(port)), Handler) as server:
    (root / (family + ".listening")).write_text("listening")
    server.serve_forever(poll_interval=0.05)
"""


def identity(path: Path) -> tuple[int, str]:
    record = json.loads(path.read_text())
    return record["pid"], record["start"]


def living(record: tuple[int, str]) -> bool:
    pid, started = record
    try:
        stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    except FileNotFoundError:
        return False
    return stat[19] == started and stat[0] not in {"Z", "X"}


def require_platform() -> dict:
    """Mandatory absence is BLOCKED (a suite error), never a passing skip."""
    if (
        sys.platform != "linux"
        or not hasattr(os, "pidfd_open")
        or not hasattr(signal, "pidfd_send_signal")
    ):
        raise RuntimeError("BLOCKED: Linux /proc and pidfd safeguards required")
    try:
        descriptor = os.pidfd_open(os.getpid())
        os.close(descriptor)
        helper = runpy.run_path(str(HELPER))
        helper["preflight"]()
    except (OSError, RuntimeError, AttributeError, ValueError) as error:
        raise RuntimeError(
            "BLOCKED: mandatory supervision platform unavailable"
        ) from error
    return helper


class CallOrderTests(unittest.TestCase):
    """UNRUN deterministic reuse sentinels; no real group signals or PID churn."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = require_platform()

    def test_exit_observation_pins_all_leaders_through_last_signal(self) -> None:
        events = []
        reaped = set()
        after_kill_drains = 0
        selector = SimpleNamespace(
            get_map=lambda: {1: "pipe"} if after_kill_drains < 3 else {}
        )
        processes = [
            SimpleNamespace(pid=pid, returncode=None, stdout=None) for pid in (41, 42)
        ]

        def waitid(kind, pid, options):
            self.assertEqual(kind, os.P_PID)
            self.assertEqual(options, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            self.assertNotIn(pid, reaped, "observation after final reap")
            events.append(("observe", pid))
            return SimpleNamespace(si_pid=pid, si_code=os.CLD_EXITED, si_status=7)

        def killpg(pid, sig):
            self.assertFalse(reaped, "signal reached reused/unpinned group sentinel")
            self.assertEqual(events[-1], ("observe", pid))
            events.append(("signal", pid, sig))

        def waitpid(pid, options):
            self.assertEqual(options, 0)
            self.assertNotIn(pid, reaped, "duplicate reap")
            self.assertEqual(sum(event[0] == "signal" for event in events), 4)
            self.assertEqual(
                after_kill_drains, 3, "reaped before delayed KILL output EOF"
            )
            reaped.add(pid)  # Identity now belongs to the unrelated reuse sentinel.
            events.append(("reap", pid))
            return pid, 7 << 8

        def delayed_drain(*_):
            nonlocal after_kill_drains
            if sum(event[0] == "signal" for event in events) == 4:
                after_kill_drains += 1

        clock = iter(range(100))
        with (
            patch.object(os, "waitid", side_effect=waitid),
            patch.object(os, "waitpid", side_effect=waitpid),
            patch.object(os, "killpg", side_effect=killpg),
            patch.dict(self.helper["cleanup"].__globals__, {"drain": delayed_drain}),
            patch.object(time, "monotonic", side_effect=lambda: next(clock)),
        ):
            self.assertEqual(self.helper["observe"](processes[0]), 7)
            self.assertIsNone(processes[0].returncode)
            self.helper["cleanup"](processes, selector)
        self.assertEqual(reaped, {41, 42})
        self.assertEqual([process.returncode for process in processes], [7, 7])

    def test_external_reaping_or_unknown_identity_never_signals_reuse(self) -> None:
        for state in ("external", "returncode", "wrong-pid", "unavailable"):
            with self.subTest(state=state):
                pipe = SimpleNamespace(closed=False)
                pipe.close = lambda pipe=pipe: setattr(pipe, "closed", True)
                process = SimpleNamespace(
                    pid=41, returncode=0 if state == "returncode" else None, stdout=pipe
                )
                clock = iter(range(100))
                status = SimpleNamespace(si_pid=42, si_code=os.CLD_EXITED, si_status=0)
                failure = (
                    ChildProcessError()
                    if state == "external"
                    else ProcessLookupError()
                    if state == "unavailable"
                    else None
                )
                with (
                    patch.object(
                        os,
                        "waitid",
                        return_value=status,
                        side_effect=failure,
                    ),
                    patch.object(os, "waitpid") as reap,
                    patch.object(os, "killpg") as unrelated_signal,
                    patch.dict(
                        self.helper["cleanup"].__globals__, {"drain": lambda *_: None}
                    ),
                    patch.object(
                        time, "monotonic", side_effect=lambda clock=clock: next(clock)
                    ),
                    self.assertRaises(RuntimeError),
                ):
                    self.helper["cleanup"]([process], SimpleNamespace(get_map=dict))
                unrelated_signal.assert_not_called()
                reap.assert_not_called()
                self.assertTrue(pipe.closed)

    def test_waitid_signal_exit_conversion_and_live_observation(self) -> None:
        process = SimpleNamespace(pid=41, returncode=None)
        for code in (os.CLD_KILLED, os.CLD_DUMPED):
            with patch.object(
                os,
                "waitid",
                return_value=SimpleNamespace(
                    si_pid=41, si_code=code, si_status=signal.SIGTERM
                ),
            ):
                self.assertEqual(self.helper["observe"](process), -signal.SIGTERM)
                self.assertIsNone(process.returncode)
        with patch.object(os, "waitid", return_value=None):
            self.assertIsNone(self.helper["observe"](process))

    def test_postkill_eof_deadline_fails_without_resignalling(self) -> None:
        process = SimpleNamespace(pid=41, returncode=None, stdout=None)
        selector = SimpleNamespace(get_map=lambda: {1: "persistent-writer"})
        clock = iter(range(100))
        status = SimpleNamespace(si_pid=41, si_code=os.CLD_EXITED, si_status=0)
        with (
            patch.object(os, "waitid", return_value=status),
            patch.object(os, "waitpid", return_value=(41, 0)) as reap,
            patch.object(os, "killpg") as group_signal,
            patch.dict(self.helper["cleanup"].__globals__, {"drain": lambda *_: None}),
            patch.object(time, "monotonic", side_effect=lambda: next(clock)),
            self.assertRaises(RuntimeError),
        ):
            self.helper["cleanup"]([process], selector)
        reap.assert_called_once_with(41, 0)
        self.assertEqual(
            group_signal.call_args_list,
            [
                unittest.mock.call(41, signal.SIGTERM),
                unittest.mock.call(41, signal.SIGKILL),
            ],
        )

    def test_preflight_rejects_missing_primitive_and_sigchld_reaper(self) -> None:
        with patch.object(os, "WNOWAIT"):
            del os.WNOWAIT
            with self.assertRaises(RuntimeError):
                self.helper["preflight"]()
        with (
            patch.object(signal, "getsignal", return_value=signal.SIG_IGN),
            self.assertRaises(RuntimeError),
        ):
            self.helper["preflight"]()

    def test_preflight_rejects_lp64_layout_and_native_query_failure(self) -> None:
        real_sizeof = ctypes.sizeof
        for state in ("lp64", "layout"):
            with self.subTest(state=state):

                def size_of(kind, state=state):
                    if state == "lp64" or issubclass(kind, ctypes.Structure):
                        return 4
                    return real_sizeof(kind)

                with (
                    patch.object(ctypes, "sizeof", side_effect=size_of),
                    patch.object(ctypes, "CDLL") as native,
                    self.assertRaises(RuntimeError),
                ):
                    self.helper["preflight"]()
                native.assert_not_called()

        class FailedQuery:
            def __call__(self, *_):
                return -1

        with (
            patch.object(
                ctypes, "CDLL", return_value=SimpleNamespace(sigaction=FailedQuery())
            ),
            self.assertRaises(RuntimeError),
        ):
            self.helper["preflight"]()

        # Native auto-reap can be set while Python still reports SIG_DFL.
        class Query:
            def __call__(self, signum, new, old):
                if signum != signal.SIGCHLD or new is not None:
                    raise AssertionError("preflight mutated native signal state")
                old._obj.flags = 2  # Linux SA_NOCLDWAIT, synthetic queried state.
                return 0

        with (
            patch.object(
                ctypes, "CDLL", return_value=SimpleNamespace(sigaction=Query())
            ),
            self.assertRaises(RuntimeError),
        ):
            self.helper["preflight"]()


class SupervisionTests(unittest.TestCase):
    def setUp(self) -> None:
        require_platform()
        self.temporary = tempfile.TemporaryDirectory(prefix="web-supervision-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cwd = self.root / "unrelated-cwd"
        self.cwd.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.fixture = self.root / "fixture.py"
        self.fixture.write_text(FIXTURE)
        self.env = {
            "HOME": str(self.home),
            "PATH": os.defpath,
            "TMPDIR": str(self.root),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        self.helpers: list[subprocess.Popen] = []
        self.addCleanup(self.cleanup_owned)

    def cleanup_owned(self) -> None:
        # Signal only Popen-owned helpers and private fixture identities whose
        # Linux start time still matches. Never discover/kill by port or name.
        failed = False
        for process in self.helpers:
            if process.poll() is None:
                process.terminate()
        for process in self.helpers:
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    failed = True
            if process.stdout:
                process.stdout.close()
        for path in self.root.glob("*-*.json"):
            record = identity(path)
            try:
                descriptor = os.pidfd_open(record[0])
            except ProcessLookupError:
                continue
            except OSError:
                failed = True
                continue
            try:
                if living(record):
                    signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                    with selectors.DefaultSelector() as selector:
                        selector.register(descriptor, selectors.EVENT_READ)
                        if not selector.select(5):
                            failed = True
            except ProcessLookupError:
                continue
            except OSError:
                failed = True
            finally:
                os.close(descriptor)
        self.assertFalse(failed, "owned fixture cleanup failed or exceeded deadline")

    def port(self) -> int:
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            return reservation.getsockname()[1]

    def argv(self, family: str, mode: str, port: int) -> list[str]:
        return [
            sys.executable,
            "-B",
            str(self.fixture),
            str(self.root),
            family,
            "root",
            mode,
            str(port),
        ]

    def start(
        self,
        modes: list[str],
        *,
        command: list[str] | None = None,
        startup: float = 5,
        command_timeout: float = 5,
        ports: list[int] | None = None,
        prefix: str = "s",
        blocked_parent: bool = False,
        project_cwd: bool = False,
        fault: str | None = None,
    ) -> subprocess.Popen:
        ports = ports if ports is not None else [self.port() for _ in modes]
        self.assertEqual(len(set(ports)), len(ports), "fixture port collision")
        args = [
            sys.executable,
            "-B",
            str(HELPER),
            "--timeout",
            str(startup),
            "--command-timeout",
            str(command_timeout),
        ]
        for index, (mode, port) in enumerate(zip(modes, ports, strict=True)):
            args += [
                "--server",
                "exec " + shlex.join(self.argv(f"{prefix}{index}", mode, port)),
                "--ready-url",
                f"http://127.0.0.1:{port}/identity",
                "--ready-sha256",
                DIGEST,
            ]
        if command is None:
            command = [
                sys.executable,
                "-B",
                "-c",
                (
                    "from pathlib import Path; import sys; "
                    "Path(sys.argv[1]).write_text('started')"
                ),
                str(self.root / "command.started"),
            ]
        invocation = [*args, "--", *command]
        if blocked_parent:
            # Set the mask inside the launched interpreter, never in the test
            # runner or a threaded preexec callback. Execute the real __main__.
            wrapper = (
                "import runpy,signal,sys; "
                "signal.pthread_sigmask(signal.SIG_BLOCK, "
                "{signal.SIGINT,signal.SIGTERM,signal.SIGUSR1}); "
                "before=signal.pthread_sigmask(signal.SIG_BLOCK,set()); "
                "sys.argv=sys.argv[1:]; "
                'exec(\'try:\\n runpy.run_path(sys.argv[0],run_name="__main__")'
                "\\nexcept SystemExit as error:\\n "
                "assert signal.pthread_sigmask(signal.SIG_BLOCK,set()) == before"
                "\\n raise SystemExit(error.code)')"
            )
            invocation = [sys.executable, "-B", "-c", wrapper, *invocation[2:]]
        if fault is not None:
            self.assertFalse(blocked_parent)
            # Fault only the private launcher. Wait for fixture ownership records
            # before raising so cleanup is exercised with real living descendants.
            wrapper = r"""
import os, runpy, selectors, signal, subprocess, sys, time
from pathlib import Path
fault, root, *args = sys.argv[1:]
root = Path(root)
before_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
before_handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
def marker(family):
    deadline = time.monotonic() + 5
    while not (root / (family + "-grandchild.json")).exists():
        if time.monotonic() >= deadline:
            raise RuntimeError("fixture marker deadline")
        time.sleep(0.01)
if "register" in fault:
    original = selectors.DefaultSelector
    class FaultSelector(original):
        count = 0
        def register(self, *args, **kwargs):
            self.count += 1
            if self.count == (1 if fault == "register-first" or fault.startswith("signal-") else 2):
                marker("s0" if self.count == 1 else
                       "s1" if fault == "register-second-server" else "test")
                if fault.startswith("signal-"):
                    os.kill(os.getpid(), signal.SIGINT if fault.endswith("int") else signal.SIGTERM)
                else:
                    raise OSError("synthetic registration failure")
            return super().register(*args, **kwargs)
    selectors.DefaultSelector = FaultSelector
elif fault == "spawn-second" or fault.startswith("signal-create"):
    original = subprocess.Popen
    count = 0
    def popen(*args, **kwargs):
        global count
        count += 1
        if fault.startswith("signal-create"):
            created = original(*args, **kwargs)
            marker("s0")
            os.kill(os.getpid(), signal.SIGINT if fault.endswith("int") else signal.SIGTERM)
            return created
        if count == 2:
            marker("s0")
            raise OSError("synthetic partial spawn failure")
        return original(*args, **kwargs)
    subprocess.Popen = popen
else:
    raise RuntimeError("unknown fixture fault")
sys.argv = args
try:
    runpy.run_path(args[0], run_name="__main__")
except SystemExit:
    assert signal.pthread_sigmask(signal.SIG_BLOCK, set()) == before_mask
    assert {sig: signal.getsignal(sig) for sig in before_handlers} == before_handlers
    # Fixed receipt distinguishes restored expected faults from assertion exit1.
    os.write(1, b"SUPERVISION_SIGNAL_STATE_RESTORED\n")
    raise
"""
            invocation = [
                sys.executable,
                "-B",
                "-c",
                wrapper,
                fault,
                str(self.root),
                *invocation[2:],
            ]
        process = subprocess.Popen(
            invocation,
            cwd=HELPER.parents[1] if project_cwd else self.cwd,
            env=self.env,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.helpers.append(process)
        return process

    def wait_file(self, path: Path, timeout: float = 8) -> None:
        deadline = time.monotonic() + timeout
        while not path.exists():
            if time.monotonic() >= deadline:
                self.fail("fixture state deadline exceeded")
            time.sleep(0.01)

    def finish(
        self, process: subprocess.Popen, timeout: float = 12
    ) -> tuple[int, bytes]:
        # Drain continuously but retain at most 64 KiB of synthetic-only output.
        output = bytearray()
        total = 0
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            os.set_blocking(process.stdout.fileno(), False)
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                if time.monotonic() >= deadline:
                    self.fail("production helper completion deadline exceeded")
                for key, _ in selector.select(0.05):
                    chunk = os.read(key.fileobj.fileno(), 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        total += len(chunk)
                        output.extend(chunk[: max(0, 65536 - len(output))])
        code = process.wait(timeout=2)
        self.assertLessEqual(total, 65536, "helper emitted unbounded output")
        self.assertNotIn(SECRET.encode(), output)
        self.assertNotIn(b"SYNTHETIC_ONLY_TOKEN_", output)
        self.assertNotIn(b"do_not_emit_47", output)
        self.assertEqual(
            list(self.home.iterdir()), [], "fixture modified isolated HOME"
        )
        return code, bytes(output)

    def assert_clean(self, family: str, *, graceful: bool = True) -> None:
        records = [
            self.root / f"{family}-{role}.json"
            for role in ("root", "child", "grandchild")
        ]
        for path in records:
            self.assertTrue(path.exists(), "fixture descendant did not start")
            record = json.loads(path.read_text())
            self.assertNotIn(int(signal.SIGINT), record["mask"])
            self.assertNotIn(int(signal.SIGTERM), record["mask"])
            self.assertFalse(
                living(identity(path)), "owned descendant survived cleanup"
            )
            if graceful:
                self.assertEqual(
                    path.with_suffix(".term").read_text(), str(signal.SIGTERM.value)
                )

    def test_occupied_port_starts_nothing_and_preserves_owned_listener(self) -> None:
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            code, _ = self.finish(
                self.start(["normal"], ports=[listener.getsockname()[1]])
            )
            self.assertNotEqual(code, 0)
            self.assertFalse((self.root / "command.started").exists())
            self.assertEqual(list(self.root.glob("s*-*.json")), [])
            with socket.create_connection(listener.getsockname(), timeout=1):
                accepted, _ = listener.accept()
                accepted.close()

    def test_wrong_app_and_startup_timeout(self) -> None:
        code, _ = self.finish(self.start(["wrong"], startup=2))
        self.assertNotEqual(code, 0)
        self.assertFalse((self.root / "command.started").exists())
        self.assert_clean("s0")

    def test_early_exit_cleans_exited_leader_descendants(self) -> None:
        code, _ = self.finish(self.start(["early"]))
        self.assertNotEqual(code, 0)
        self.assertFalse((self.root / "command.started").exists())
        self.assert_clean("s0", graceful=False)

    def test_noisy_output_success_and_synthetic_secret_suppression(self) -> None:
        command = [
            sys.executable,
            "-B",
            "-c",
            (
                "import os; os.write(1, b'SYNTHETIC_ONLY_TOKEN_'); "
                "os.write(2, b'do_not_emit_47')"
            ),
        ]
        code, _ = self.finish(self.start(["noisy"], command=command))
        self.assertEqual(code, 0)
        self.assert_clean("s0")

    def test_partial_multi_server_startup_cleans_all_started_groups(self) -> None:
        code, _ = self.finish(self.start(["normal", "partial"]))
        self.assertNotEqual(code, 0)
        self.assertFalse((self.root / "command.started").exists())
        self.assert_clean("s0")
        self.assert_clean("s1", graceful=False)

    def test_command_failure_cleans_server_and_test_descendants(self) -> None:
        code, _ = self.finish(
            self.start(["normal"], command=self.argv("test", "early", 0))
        )
        self.assertEqual(code, 7)
        self.assert_clean("s0")
        self.assert_clean("test", graceful=False)

    def test_project_cwd_exited_command_leader_descendants(self) -> None:
        code, _ = self.finish(
            self.start(
                ["normal"], command=self.argv("test", "early", 0), project_cwd=True
            )
        )
        self.assertEqual(code, 7)
        self.assert_clean("s0")
        self.assert_clean("test", graceful=False)

    def test_registration_and_partial_spawn_exceptions(self) -> None:
        for fault in (
            "register-first",
            "register-second",
            "register-second-server",
            "spawn-second",
        ):
            with self.subTest(fault=fault):
                modes = ["normal"] * (
                    2 if fault in {"register-second-server", "spawn-second"} else 1
                )
                code, output = self.finish(
                    self.start(
                        modes, command=self.argv("test", "command", 0), fault=fault
                    )
                )
                self.assertEqual(code, 1)
                self.assertIn(RESTORED, output, "launcher restoration was not verified")
                self.assert_clean("s0")
                if fault == "register-second":
                    self.assert_clean("test")
                if fault == "register-second-server":
                    self.assert_clean("s1")
                # Keep each fault's evidence distinct; no stale marker admission.
                for path in self.root.glob("s[01]*"):
                    path.unlink()
                for path in self.root.glob("test*"):
                    path.unlink()

    def test_server_exit_during_command_cleans_all_descendants(self) -> None:
        code, _ = self.finish(
            self.start(["exit-during-command"], command=self.argv("test", "command", 0))
        )
        self.assertNotEqual(code, 0)
        self.assert_clean("s0", graceful=False)
        self.assert_clean("test")

    def test_pending_creation_and_registration_signals_restore_state(self) -> None:
        for stage in ("create", "register"):
            for label, sig in (("int", signal.SIGINT), ("term", signal.SIGTERM)):
                with self.subTest(stage=stage, signal=sig):
                    code, output = self.finish(
                        self.start(["normal"], fault=f"signal-{stage}-{label}")
                    )
                    self.assertEqual(code, 128 + sig)
                    self.assertIn(
                        RESTORED, output, "launcher restoration was not verified"
                    )
                    self.assert_clean("s0")
                    for path in self.root.glob("s0*"):
                        path.unlink()

    def test_signalled_command_exit_is_converted_without_early_reap(self) -> None:
        command = [
            sys.executable,
            "-B",
            "-c",
            "import os,signal; os.kill(os.getpid(), signal.SIGTERM)",
        ]
        code, _ = self.finish(self.start(["normal"], command=command))
        self.assertEqual(code, 128 + signal.SIGTERM)
        self.assert_clean("s0")

    def test_command_timeout_cleans_server_and_test_descendants(self) -> None:
        code, _ = self.finish(
            self.start(
                ["normal"], command=self.argv("test", "command", 0), command_timeout=2
            )
        )
        self.assertNotEqual(code, 0)
        self.assert_clean("s0")
        self.assert_clean("test")

    def test_sigterm_resistant_grandchild_is_killed(self) -> None:
        code, _ = self.finish(self.start(["resistant"]))
        self.assertEqual(code, 0)
        self.assert_clean("s0", graceful=False)
        self.assertTrue((self.root / "s0-root.term").exists())
        self.assertTrue((self.root / "s0-child.term").exists())
        self.assertFalse((self.root / "s0-grandchild.term").exists())

    def test_inherited_parent_mask_restored_and_child_term_unblocked(self) -> None:
        code, _ = self.finish(self.start(["normal"], blocked_parent=True))
        self.assertEqual(code, 0)
        self.assert_clean("s0")
        for path in self.root.glob("s0-*.json"):
            self.assertIn(int(signal.SIGUSR1), json.loads(path.read_text())["mask"])

    def test_success_cleans_live_test_descendants(self) -> None:
        command = [
            sys.executable,
            "-B",
            "-c",
            (
                "import subprocess,sys; p=subprocess.Popen(sys.argv[1:]); "
                "from pathlib import Path; import time; "
                "path=Path(sys.argv[4])/'test-grandchild.json'; "
                "exec('while not path.exists(): time.sleep(0.01)')"
            ),
            *self.argv("test", "command", 0),
        ]
        code, _ = self.finish(self.start(["normal"], command=command))
        self.assertEqual(code, 0)
        self.assert_clean("s0")
        self.assert_clean("test")

    def test_interruptions_during_startup_and_command(self) -> None:
        case = 0
        for stage in ("startup", "command"):
            for sig in (signal.SIGINT, signal.SIGTERM):
                with self.subTest(stage=stage, signal=sig):
                    case += 1
                    server_family = f"interrupt{case}-server0"
                    test_family = f"interrupt{case}-test"
                    marker = self.root / f"{test_family}.started"
                    process = self.start(
                        ["wrong" if stage == "startup" else "normal"],
                        command=self.argv(test_family, "command", 0),
                        startup=10,
                        prefix=f"interrupt{case}-server",
                    )
                    self.wait_file(self.root / f"{server_family}-grandchild.json")
                    if stage == "command":
                        self.wait_file(marker)
                    process.send_signal(sig)
                    code, _ = self.finish(process)
                    self.assertEqual(code, 128 + sig)
                    self.assert_clean(server_family)
                    if stage == "command":
                        self.assert_clean(test_family)
                    else:
                        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
