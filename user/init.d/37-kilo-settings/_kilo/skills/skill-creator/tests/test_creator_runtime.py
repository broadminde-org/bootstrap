"""UNRUN runtime cases: execute only after separate runtime authorization.

Require CREATOR_PYTHON (absolute prepared Python with PyYAML==6.0.3) and
CREATOR_TEST_SCRATCH (existing nonredirected scratch parent outside real HOME).
Never prepare environments/dependencies or invoke provisioning/escalation.
All child HOME/XDG/temp paths and writes are inside owned TemporaryDirectories.
"""

import hashlib
import json
import os
import signal
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).absolute().parents[1]
ZIP_FAILURE_DRIVER = """
import runpy
import sys
from pathlib import Path
from unittest.mock import patch
script = sys.argv[1]
sys.path.insert(0, str(Path(script).parent))
sys.argv = sys.argv[1:]
with patch('zipfile.ZipFile.writestr', side_effect=OSError('synthetic write failure')):
    runpy.run_path(script, run_name='__main__')
"""
INIT_FAILURE_DRIVER = """
import os
import runpy
import signal
import sys
from pathlib import Path
from unittest.mock import patch

script, scenario, selected = sys.argv[1:4]
selected = int(selected)
sys.path.insert(0, str(Path(script).parent))
sys.argv = [script, *sys.argv[4:]]
parent = Path(sys.argv[sys.argv.index('--path') + 1])
destination = parent / sys.argv[1]
source = destination / 'SKILL.md'
original_open, original_mkdir = os.open, os.mkdir
original_write, original_signal = os.write, signal.signal
sent, delivered = [], []
file_descriptors = []
parent_descriptors = []
parent_releases = []
restoration_callback = []
write_calls = []

def prior_handler(signum, frame):
    raise AssertionError('Previous handler invoked during initialization')

for signum in (signal.SIGINT, signal.SIGTERM):
    initial = signal.SIG_DFL if scenario == 'native-restore-dfl' else prior_handler
    if 'ignored-refusal' in scenario and signum == selected:
        initial = signal.SIG_IGN
    signal.signal(signum, initial)
signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1})
if 'blocked' in scenario and scenario.endswith('refusal'):
    signal.pthread_sigmask(signal.SIG_BLOCK, {selected})
    if 'pending' in scenario:
        os.kill(os.getpid(), selected)
previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
previous_pending = signal.sigpending()
previous_handlers = {
    signum: signal.getsignal(signum) for signum in (signal.SIGINT, signal.SIGTERM)
}

def send(protected):
    sent.append(scenario)
    signals = (signal.SIGINT, signal.SIGTERM) if scenario.endswith('-both') else (selected,)
    for number in signals:
        os.kill(os.getpid(), number)
    if protected:
        assert not delivered, 'Signal delivered before ownership bookkeeping'
        assert set(signals) <= signal.sigpending(), 'Signal was not pending'

def install(signum, handler):
    if callable(handler) and handler.__name__ == 'record':
        def guarded(number, frame):
            delivered.append(number)
            handler(number, frame)
        return original_signal(signum, guarded)
    if scenario in ('native-restore-dfl', 'native-restore-custom') and handler is previous_handlers.get(signum) and signum == selected and not restoration_callback:
        restoration_callback.append(True)
        sent.append(scenario)
        os.kill(os.getpid(), selected)
        assert selected in signal.sigpending(), 'Restoration signal was not pending'
    if handler is prior_handler and scenario in ('restoration-first', 'restoration-second') and not restoration_callback:
        restoration_callback.append(True)
        # Model an already queued Python callback, not a fresh kernel signal.
        if scenario == 'restoration-first':
            sent.append(scenario)
            signal.getsignal(selected)(selected, None)
        else:
            other = signal.SIGTERM if selected == signal.SIGINT else signal.SIGINT
            signal.getsignal(other)(other, None)
    return original_signal(signum, handler)

def mkdir(path, *args, **kwargs):
    result = original_mkdir(path, *args, **kwargs)
    if path == destination.name and scenario in ('directory', 'directory-both'):
        send(True)
    return result

def open_file(path, *args, **kwargs):
    if path == parent and scenario == 'parent-open-failure':
        raise OSError('synthetic private path/content must not be emitted')
    if path == 'SKILL.md' and scenario == 'open-failure':
        raise OSError('synthetic private path/content must not be emitted')
    if path == destination.name and scenario == 'directory-open-failure':
        raise OSError('synthetic private path/content must not be emitted')
    result = original_open(path, *args, **kwargs)
    if path == parent:
        parent_descriptors.append(result)
        if scenario == 'parent':
            send(True)
    if path == 'SKILL.md':
        file_descriptors.append(result)
        if scenario in ('file', 'file-both'):
            send(True)
    return result

def write(fd, content):
    write_calls.append(True)
    result = original_write(fd, content[:max(1, len(content) // 2)]
                            if scenario == 'write' else content)
    fault = scenario.removesuffix('-signal')
    if scenario in ('write', 'cleanup-second', 'queued-cleanup', 'restoration-second'):
        send(False)
    elif fault == 'replacement-file':
        source.unlink()
        source.write_text('Preserve replacement', encoding='utf-8')
    elif fault == 'replacement-directory':
        destination.rename(parent / 'moved-owned')
        destination.mkdir()
        (destination / 'extra.txt').write_text('Preserve extra', encoding='utf-8')
    elif fault == 'extra':
        (destination / 'extra.txt').write_text('Preserve extra', encoding='utf-8')
    if scenario.endswith('-signal'):
        send(False)
    if fault in ('replacement-file', 'replacement-directory', 'extra'):
        raise OSError('synthetic private path/content must not be emitted')
    if scenario in ('write-failure', 'cleanup-failure'):
        raise OSError('synthetic private path/content must not be emitted')
    return result

original_unlink = os.unlink
def unlink(path, *args, **kwargs):
    if path == 'SKILL.md' and scenario == 'cleanup-failure':
        raise OSError('synthetic private path/content must not be emitted')
    if path == 'SKILL.md' and scenario in ('cleanup-second', 'queued-cleanup'):
        other = signal.SIGTERM if selected == signal.SIGINT else signal.SIGINT
        if scenario == 'cleanup-second':
            os.kill(os.getpid(), other)
        else:
            signal.getsignal(other)(other, None)
    return original_unlink(path, *args, **kwargs)

original_close = os.close
def close(fd):
    result = original_close(fd)
    if fd in parent_descriptors:
        parent_releases.append(fd)
    if scenario == 'close-failure' and fd in file_descriptors:
        raise OSError('synthetic private path/content must not be emitted')
    return result

original_timedwait = signal.sigtimedwait
def timedwait(*args):
    if scenario == 'wait-unavailable':
        raise NotImplementedError('synthetic private path/content must not be emitted')
    if scenario == 'wait-restore-failure' and write_calls:
        raise OSError('synthetic private path/content must not be emitted')
    return original_timedwait(*args)

try:
    with (
        patch('os.mkdir', mkdir),
        patch('os.open', open_file),
        patch('os.write', write),
        patch('os.unlink', unlink),
        patch('os.close', close),
        patch('signal.signal', install),
        patch('signal.sigtimedwait', timedwait),
    ):
        # The wrappers are still valid dir_fd primitives for platform admission.
        supported = {open_file, mkdir, os.stat, unlink, os.rmdir}
        with patch('os.supports_dir_fd', set() if scenario == 'unsupported' else supported):
            runpy.run_path(script, run_name='__main__')
except KeyboardInterrupt:
    raise SystemExit(130) from None
finally:
    assert signal.pthread_sigmask(signal.SIG_BLOCK, set()) == previous_mask
    assert signal.sigpending() == previous_pending
    assert all(signal.getsignal(s) is h for s, h in previous_handlers.items())
    assert parent_descriptors == parent_releases
    if scenario.endswith('-both') or scenario in (
        'cleanup-second', 'queued-cleanup', 'restoration-second'
    ):
        assert sent == [scenario] and set(delivered) == {signal.SIGINT, signal.SIGTERM}
        assert len(delivered) == 2
    elif scenario in ('parent', 'directory', 'file', 'write', 'restoration-first') or scenario.endswith('-signal'):
        assert sent == [scenario] and delivered == [selected]
    elif scenario in ('native-restore-dfl', 'native-restore-custom'):
        assert sent == [scenario] and restoration_callback == [True]
    print('Previous signal state restored')
"""


def isolated_environment(work: Path) -> dict[str, str]:
    environment = {
        "HOME": str(work / "home"),
        "XDG_CONFIG_HOME": str(work / "config"),
        "XDG_CACHE_HOME": str(work / "cache"),
        "XDG_DATA_HOME": str(work / "data"),
        "XDG_STATE_HOME": str(work / "state"),
        "TMPDIR": str(work / "tmp"),
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    for name in ("home", "config", "cache", "data", "state", "tmp"):
        (work / name).mkdir(mode=0o700)
    return environment


def snapshot(root: Path) -> dict[str, tuple[int, str]]:
    result = {}
    for path in root.rglob("*"):
        mode = path.lstat().st_mode
        value = "directory"
        if stat.S_ISLNK(mode):
            value = os.readlink(path)
        elif stat.S_ISREG(mode):
            value = hashlib.sha256(path.read_bytes()).hexdigest()
        result[path.relative_to(root).as_posix()] = (mode, value)
    return result


class CreatorRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        interpreter = os.environ.get("CREATOR_PYTHON")
        scratch = os.environ.get("CREATOR_TEST_SCRATCH")
        if not interpreter or not scratch:
            raise RuntimeError(
                "Runtime qualification blocked: explicitly set CREATOR_PYTHON and "
                "CREATOR_TEST_SCRATCH; prepare prerequisites separately, never here"
            )
        cls.python = Path(interpreter)
        cls.scratch = Path(scratch)
        real_home = Path.home().resolve()
        if (
            os.geteuid() == 0
            or not cls.python.is_absolute()
            or not cls.python.is_file()
            or not os.access(cls.python, os.X_OK)
            or not cls.scratch.is_absolute()
            or not cls.scratch.is_dir()
            or cls.scratch != cls.scratch.resolve()
            or cls.scratch.is_relative_to(real_home)
            or cls.scratch.is_relative_to(ROOT.resolve())
        ):
            raise RuntimeError(
                "Runtime qualification blocked: unsafe/missing prerequisites"
            )
        with tempfile.TemporaryDirectory(
            dir=cls.scratch, prefix="creator-probe-"
        ) as tmp:
            work = Path(tmp)
            result = subprocess.run(
                [
                    str(cls.python),
                    "-B",
                    "-s",
                    "-c",
                    (
                        "import sys, yaml; "
                        "sys.exit(0 if yaml.__version__ == '6.0.3' else 1)"
                    ),
                ],
                cwd=work,
                env=isolated_environment(work),
                capture_output=True,
                timeout=15,
                check=False,
            )
            if result.returncode:
                raise RuntimeError(
                    "Qualification blocked: prepared PyYAML==6.0.3 is required; "
                    "no installation or silent skip attempted"
                )

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(
            dir=self.scratch, prefix="creator-runtime-"
        )
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.environment = isolated_environment(self.work)
        self.cwd = self.work / "unrelated-cwd"
        self.cwd.mkdir()
        self.skill = self.work / "sample-skill"
        self.skill.mkdir()
        self.output = self.work / "packages"
        self.output.mkdir()
        self.inventory = self.work / "review.json"
        self.write_skill()

    def write_skill(
        self,
        metadata: str = 'name: sample-skill\ndescription: "Fixture skill"',
        body: str = "# Fixture\nUse only synthetic fixture data.\n",
    ) -> None:
        (self.skill / "SKILL.md").write_text(
            f"---\n{metadata}\n---\n{body}", encoding="utf-8"
        )

    def run_cli(
        self,
        script: str,
        *arguments: str | Path,
        no_site: bool = False,
        fail_zip: bool = False,
        init_fault: tuple[str, int] | None = None,
    ) -> subprocess.CompletedProcess:
        command = [str(self.python), "-B", "-s"]
        if no_site:
            command.append("-S")  # No site-packages: deterministic unprepared parser.
        if fail_zip:
            command.extend(["-c", ZIP_FAILURE_DRIVER])
        if init_fault is not None:
            scenario, selected = init_fault
            command.extend(
                [
                    "-c",
                    INIT_FAILURE_DRIVER,
                    str(ROOT / "scripts" / script),
                    scenario,
                    str(selected),
                    *map(str, arguments),
                ]
            )
        else:
            command.extend([str(ROOT / "scripts" / script), *map(str, arguments)])
        return subprocess.run(
            command,
            cwd=self.cwd,
            env=self.environment,
            capture_output=True,
            timeout=15,
            check=False,
        )

    def review(self, *names: str) -> None:
        entries = [
            {
                "path": name,
                "sha256": hashlib.sha256((self.skill / name).read_bytes()).hexdigest(),
            }
            for name in ("SKILL.md", *names)
        ]
        self.inventory.write_text(
            json.dumps({"files": entries}),
            encoding="utf-8",
        )

    def package(self, **options: bool) -> subprocess.CompletedProcess:
        return self.run_cli(
            "package_skill.py",
            self.skill,
            "--output-dir",
            self.output,
            "--inventory",
            self.inventory,
            **options,
        )

    def assert_refused_unchanged(self, script: str, *arguments: str | Path) -> None:
        before = snapshot(self.work)
        self.assertNotEqual(self.run_cli(script, *arguments).returncode, 0)
        self.assertEqual(snapshot(self.work), before)

    def test_folded_literal_quoted_yaml(self) -> None:
        for description in (
            '"Quoted: fixture"',
            ">-\n  Folded\n  fixture",
            "|\n  Literal\n  fixture",
        ):
            with self.subTest(description=description):
                self.write_skill(f"name: sample-skill\ndescription: {description}")
                before = snapshot(self.work)
                self.assertEqual(
                    self.run_cli("quick_validate.py", self.skill).returncode, 0
                )
                self.assertEqual(snapshot(self.work), before)

    def test_structural_yaml_rejections(self) -> None:
        valid = 'name: sample-skill\ndescription: "Fixture"'
        cases = {
            "duplicate": valid + "\nname: sample-skill",
            "nested-duplicate": valid + "\nmetadata: {category: one, category: two}",
            "description-type": "name: sample-skill\ndescription: [fixture]",
            "name-type": 'name: 123\ndescription: "Fixture"',
            "metadata-type": valid + "\nmetadata: []",
            "references-type": valid + "\nreferences: missing.md",
            "missing-reference": valid + "\nreferences: [missing.md]",
            "escaping-reference": valid + "\nreferences: [../review.json]",
            "wrong-name": 'name: another-skill\ndescription: "Fixture"',
        }
        for name, metadata in cases.items():
            with self.subTest(case=name):
                self.write_skill(metadata)
                self.assert_refused_unchanged("quick_validate.py", self.skill)

    def test_local_markdown_reference(self) -> None:
        resource = self.skill / "references" / "guide.md"
        resource.parent.mkdir()
        resource.write_text("# Synthetic guide\n", encoding="utf-8")
        self.write_skill(body="[Guide](references/guide.md)\n")
        self.assertEqual(self.run_cli("quick_validate.py", self.skill).returncode, 0)
        resource.unlink()
        self.assert_refused_unchanged("quick_validate.py", self.skill)

    def test_malformed_resource_url_diagnostics_hide_synthetic_credentials(
        self,
    ) -> None:
        secret = "ghp_" + "A" * 36
        target = f"https://{secret}@example.invalid\uff0f/resource"
        self.write_skill(body=f"[Malformed]({target})\n")
        before = snapshot(self.work)
        result = self.run_cli("quick_validate.py", self.skill)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret.encode(), result.stdout + result.stderr)
        self.assertEqual(snapshot(self.work), before)
        self.review()
        before = snapshot(self.work)
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret.encode(), result.stdout + result.stderr)
        self.assertEqual(snapshot(self.work), before)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_unprepared_parser_fails_without_preparation(self) -> None:
        before = snapshot(self.work)
        result = self.run_cli("quick_validate.py", self.skill, no_site=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Parser unprepared", result.stdout)
        self.assertEqual(snapshot(self.work), before)

    def test_instruction_only_init_and_existing_untouched(self) -> None:
        parent = self.work / "skills"
        parent.mkdir()
        args = ("new-skill", "--path", parent)
        self.assertEqual(self.run_cli("init_skill.py", *args).returncode, 0)
        destination = parent / "new-skill"
        self.assertEqual(list(parent.iterdir()), [destination])
        self.assertEqual([p.name for p in destination.iterdir()], ["SKILL.md"])
        self.assertEqual(self.run_cli("quick_validate.py", destination).returncode, 0)
        (destination / "user-extra.txt").write_text("Keep me", encoding="utf-8")
        self.assert_refused_unchanged("init_skill.py", *args)
        empty = parent / "empty-skill"
        empty.mkdir()
        self.assert_refused_unchanged("init_skill.py", "empty-skill", "--path", parent)

    def test_yaml_ambiguous_names_remain_strings(self) -> None:
        parent = self.work / "skills"
        parent.mkdir()
        for name in ("123", "yes", "no", "null", "on", "off"):
            with self.subTest(name=name):
                self.assertEqual(
                    self.run_cli("init_skill.py", name, "--path", parent).returncode,
                    0,
                )
                self.assertEqual(
                    self.run_cli("quick_validate.py", parent / name).returncode, 0
                )

    def test_init_pending_signals_and_retry_from_both_cwds(self) -> None:
        project = self.work / "project-cwd"
        project.mkdir()
        (project / "pyproject.toml").write_text("[project]\nname = 'fixture'\n")
        for cwd in (self.cwd, project):
            self.cwd = cwd
            for selected in (signal.SIGINT, signal.SIGTERM):
                for scenario in (
                    "directory",
                    "parent",
                    "file",
                    "write",
                    "directory-both",
                    "file-both",
                    "cleanup-second",
                    "queued-cleanup",
                    "restoration-second",
                    "restoration-first",
                    "native-restore-dfl",
                    "native-restore-custom",
                    "replacement-file-signal",
                    "replacement-directory-signal",
                    "extra-signal",
                ):
                    with self.subTest(cwd=cwd.name, signal=selected, fault=scenario):
                        parent = self.work / f"{cwd.name}-{selected}-{scenario}"
                        parent.mkdir()
                        before = snapshot(parent)
                        result = self.run_cli(
                            "init_skill.py",
                            "new-skill",
                            "--path",
                            parent,
                            init_fault=(scenario, selected),
                        )
                        if scenario.endswith("-both"):
                            self.assertIn(
                                result.returncode,
                                (128 + signal.SIGINT, 128 + signal.SIGTERM),
                            )
                        else:
                            self.assertEqual(result.returncode, 128 + selected)
                        self.assertIn(b"Previous signal state restored", result.stdout)
                        self.assertNotIn(b"Created instruction-only", result.stdout)
                        if scenario.endswith("-signal"):
                            self.assertIn(b"cleanup incomplete", result.stdout)
                            destination = parent / "new-skill"
                            if scenario == "replacement-file-signal":
                                self.assertEqual(
                                    (destination / "SKILL.md").read_text(),
                                    "Preserve replacement",
                                )
                            else:
                                self.assertEqual(
                                    (destination / "extra.txt").read_text(),
                                    "Preserve extra",
                                )
                                self.assertFalse((destination / "SKILL.md").exists())
                                if scenario == "replacement-directory-signal":
                                    self.assertEqual(
                                        list((parent / "moved-owned").iterdir()), []
                                    )
                            self.assertNotIn(
                                str(parent).encode(), result.stdout + result.stderr
                            )
                            continue
                        self.assertEqual(snapshot(parent), before)
                        self.assertEqual(
                            self.run_cli(
                                "init_skill.py", "new-skill", "--path", parent
                            ).returncode,
                            0,
                        )
                        self.assert_refused_unchanged(
                            "init_skill.py", "new-skill", "--path", parent
                        )

    def test_init_failures_ownership_and_signal_state_from_both_cwds(self) -> None:
        project = self.work / "project-cwd"
        project.mkdir()
        (project / "pyproject.toml").write_text("[project]\nname = 'fixture'\n")
        for cwd in (self.cwd, project):
            self.cwd = cwd
            for scenario in (
                "normal",
                "blocked-refusal",
                "term-blocked-refusal",
                "blocked-pending-refusal",
                "term-blocked-pending-refusal",
                "ignored-refusal",
                "term-ignored-refusal",
                "existing",
                "unsupported",
                "open-failure",
                "parent-open-failure",
                "write-failure",
                "directory-open-failure",
                "replacement-file",
                "replacement-directory",
                "extra",
                "cleanup-failure",
                "close-failure",
                "wait-unavailable",
                "wait-restore-failure",
            ):
                with self.subTest(cwd=cwd.name, fault=scenario):
                    parent = self.work / f"{cwd.name}-{scenario}"
                    parent.mkdir()
                    if scenario == "existing":
                        (parent / "new-skill").mkdir()
                        (parent / "new-skill" / "extra.txt").write_text("Keep existing")
                    before = snapshot(parent)
                    result = self.run_cli(
                        "init_skill.py",
                        "new-skill",
                        "--path",
                        parent,
                        init_fault=(
                            scenario,
                            signal.SIGTERM
                            if scenario.startswith("term-")
                            else signal.SIGINT,
                        ),
                    )
                    self.assertEqual(
                        result.returncode,
                        0 if scenario == "normal" else 1,
                    )
                    self.assertIn(b"Previous signal state restored", result.stdout)
                    self.assertNotIn(
                        b"synthetic private path/content", result.stdout + result.stderr
                    )
                    destination = parent / "new-skill"
                    if scenario == "normal":
                        self.assertEqual(
                            [p.name for p in destination.iterdir()], ["SKILL.md"]
                        )
                    elif scenario == "existing":
                        self.assertEqual(snapshot(parent), before)
                    elif scenario in (
                        "unsupported",
                        "blocked-refusal",
                        "term-blocked-refusal",
                        "blocked-pending-refusal",
                        "term-blocked-pending-refusal",
                        "ignored-refusal",
                        "term-ignored-refusal",
                        "open-failure",
                        "parent-open-failure",
                        "write-failure",
                        "wait-unavailable",
                        "wait-restore-failure",
                    ):
                        self.assertEqual(list(parent.iterdir()), [])
                        if scenario in (
                            "open-failure",
                            "write-failure",
                            "wait-restore-failure",
                        ):
                            self.assertEqual(
                                self.run_cli(
                                    "init_skill.py", "new-skill", "--path", parent
                                ).returncode,
                                0,
                            )
                    else:
                        self.assertIn(b"cleanup incomplete", result.stdout)
                        self.assertNotIn(
                            str(parent).encode(), result.stdout + result.stderr
                        )
                        if scenario == "replacement-file":
                            self.assertEqual(
                                (destination / "SKILL.md").read_text(),
                                "Preserve replacement",
                            )
                        elif scenario in ("replacement-directory", "extra"):
                            self.assertEqual(
                                (destination / "extra.txt").read_text(),
                                "Preserve extra",
                            )
                            self.assertFalse((destination / "SKILL.md").exists())
                            if scenario == "replacement-directory":
                                self.assertEqual(
                                    list((parent / "moved-owned").iterdir()), []
                                )
                        elif scenario == "directory-open-failure":
                            self.assertEqual(list(destination.iterdir()), [])
                        else:
                            self.assertTrue((destination / "SKILL.md").is_file())

    def test_invalid_names_before_writes(self) -> None:
        parent = self.work / "skills"
        parent.mkdir()
        for name in (
            "Bad",
            "bad--name",
            "a" * 41,
            "../escape",
            "bad/name",
            str(self.work / "absolute"),
        ):
            with self.subTest(name=name):
                self.assert_refused_unchanged("init_skill.py", name, "--path", parent)

    def test_package_exact_reviewed_inventory(self) -> None:
        for name in ("LICENSE", "local.patch", "included.txt", "excluded.txt"):
            (self.skill / name).write_text(
                "Synthetic public fixture\n", encoding="utf-8"
            )
        self.review("LICENSE", "local.patch", "included.txt")
        before = snapshot(self.skill)
        self.assertEqual(self.package().returncode, 0)
        archive = self.output / "sample-skill.zip"
        self.assertEqual(list(self.output.iterdir()), [archive])
        with zipfile.ZipFile(archive) as package:
            self.assertEqual(
                set(package.namelist()),
                {
                    f"sample-skill/{name}"
                    for name in ("SKILL.md", "LICENSE", "local.patch", "included.txt")
                },
            )
            for name in package.namelist():
                self.assertEqual(
                    package.read(name), (self.skill / Path(name).name).read_bytes()
                )
        self.assertEqual(snapshot(self.skill), before)

    def test_uppercase_markdown_references_require_inventory_membership(self) -> None:
        guide = self.skill / "references/GUIDE.MD"
        guide.parent.mkdir()
        guide.write_text("[Details](details.txt)\n", encoding="utf-8")
        self.write_skill(body="[Guide](references/GUIDE.MD)\n")
        self.review("references/GUIDE.MD")
        before = snapshot(self.work)
        self.assertNotEqual(self.package().returncode, 0)
        self.assertEqual(snapshot(self.work), before)
        details = guide.with_name("details.txt")
        details.write_text("Synthetic details\n", encoding="utf-8")
        before = snapshot(self.work)
        self.assertNotEqual(self.package().returncode, 0)
        self.assertEqual(snapshot(self.work), before)
        self.review("references/GUIDE.MD", "references/details.txt")
        self.assertEqual(self.package().returncode, 0)
        with zipfile.ZipFile(self.output / "sample-skill.zip") as package:
            self.assertIn("sample-skill/references/details.txt", package.namelist())

    def test_package_source_links_refused_without_archive(self) -> None:
        self.review()
        for name, target in (
            ("file-link", self.skill / "SKILL.md"),
            ("dir-link", self.cwd),
            ("dangling-link", self.work / "absent"),
        ):
            with self.subTest(link=name):
                link = self.skill / name
                link.symlink_to(target)
                before = snapshot(self.work)
                self.assertNotEqual(self.package().returncode, 0)
                self.assertEqual(snapshot(self.work), before)
                self.assertEqual(list(self.output.iterdir()), [])
                link.unlink()

    def test_package_secrets_and_local_generated_inputs_refused(self) -> None:
        secret = "ghp_" + "A" * 36  # Synthetic signature, never a real credential.
        for name, content in (
            ("data.txt", secret),
            (secret + ".txt", "public"),
            ("secrets.txt", "public"),
            ("credentials.txt", "public"),
            ("tokens.txt", "public"),
            ("passwords.txt", "public"),
            ("dist/result.txt", "public"),
            ("local/data.txt", "public"),
            (".env", "public"),
        ):
            with self.subTest(input=name):
                path = self.skill / name
                path.parent.mkdir(exist_ok=True)
                path.write_text(content, encoding="utf-8")
                self.review(name)
                before = snapshot(self.work)
                result = self.package()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(secret.encode(), result.stdout + result.stderr)
                self.assertEqual(snapshot(self.work), before)
                self.assertEqual(list(self.output.iterdir()), [])
                path.unlink()

    def test_existing_archive_unchanged(self) -> None:
        self.review()
        archive = self.output / "sample-skill.zip"
        archive.write_bytes(b"synthetic existing output")
        before = snapshot(self.work)
        self.assertNotEqual(self.package().returncode, 0)
        self.assertEqual(snapshot(self.work), before)

    def test_changed_reviewed_input_leaves_no_archive(self) -> None:
        self.review()
        self.write_skill(body="# Changed after review\n")
        before = snapshot(self.work)
        self.assertNotEqual(self.package().returncode, 0)
        self.assertEqual(snapshot(self.work), before)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_staged_write_failure_leaves_no_archive(self) -> None:
        self.review()
        before = snapshot(self.work)
        result = self.package(fail_zip=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Packaging failed", result.stdout)
        self.assertEqual(snapshot(self.work), before)
        self.assertEqual(list(self.output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
