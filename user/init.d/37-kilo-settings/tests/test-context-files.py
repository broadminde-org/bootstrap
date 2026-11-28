"""Isolated production file-helper cases. Runtime authorization required.

Run from any CWD: python3 /path/to/37-kilo-settings/tests/test-context-files.py
No dependencies, clients, server startup, or real HOME modifications.
"""

import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "context_files", Path(__file__).absolute().parents[1] / "context-files.py"
)
assert SPEC is not None and SPEC.loader is not None
FILES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FILES)


class ContextFilesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.step = self.root / "repo/user/init.d/37-kilo-settings"
        self.home = self.root / "home"
        self.home.mkdir()
        self.step.mkdir(parents=True)
        (self.step / ".kilocodeignore").write_text("local\n")
        for directory in ("agents", "commands", "rules"):
            (self.step / "_config/kilo" / directory).mkdir(parents=True)
        for name in ("kilo.json", "kilo.jsonc"):
            (self.step / "_config/kilo" / name).write_text("{}\n")
        self.source = self.step / "_config/kilo/rules/example.md"
        self.source.write_text("source\n")
        (self.step / "default-skills.txt").write_text("example\n")
        (self.step / "optional-skills.txt").write_text("optional\n")
        for name in ("example", "optional"):
            skill = self.step / "_kilo/skills" / name
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(f"---\nname: {name}\n---\n")
        self.files = FILES.inventory(self.step)
        self.state = FILES.preflight(self.step, self.home, self.files)
        self.key = "config/rules/example.md"
        self.live = FILES.destination(self.home, self.key)

    def deploy(self, phase: str = "config", optional: str = "") -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            FILES.deploy(self.step, self.home, self.files, self.state, phase, optional)

    def test_deploy_and_convergence(self) -> None:
        self.deploy()
        first = FILES.receipt(self.state, self.key)
        self.deploy()
        self.assertEqual(first, FILES.receipt(self.state, self.key))
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(
            FILES.receipt_path(self.state, self.key).stat().st_mode & 0o777, 0o600
        )

    def test_import_receipts_and_stale_second_import(self) -> None:
        self.deploy()
        identity = FILES.receipt(self.state, self.key)
        self.live.write_text("reviewed\n")
        FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.assertEqual(self.source.read_text(), "reviewed\n")
        self.assertEqual(FILES.receipt(self.state, self.key), identity)
        FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.live.write_text("another\n")
        with self.assertRaises(ValueError):
            FILES.reverse(self.files, self.home, self.state, [self.key], True)

    def test_selection_validated_completely_before_write(self) -> None:
        self.deploy()
        self.live.write_text("reviewed\n")
        for invalid in (
            [],
            [self.key, "config/kilo.json"],
            [self.key, self.key],
            ["config/rules/../../outside"],
            ["skills/unknown/SKILL.md"],
        ):
            with self.subTest(selection=invalid), self.assertRaises(ValueError):
                FILES.reverse(self.files, self.home, self.state, invalid, True)
            self.assertEqual(self.source.read_text(), "source\n")

    def test_later_valid_selection_failure_precedes_all_writes(self) -> None:
        key = "config/rules/second.md"
        source = self.step / "_config/kilo/rules/second.md"
        source.write_text("second\n")
        self.files = FILES.inventory(self.step)
        for failure in ("secret", "stale", "missing"):
            with self.subTest(failure=failure):
                source.write_text("second\n")
                self.deploy()
                self.live.write_text("reviewed first\n")
                live = FILES.destination(self.home, key)
                live.write_text("reviewed second\n")
                if failure == "secret":
                    live.write_text("ghp_" + "x" * 36)
                elif failure == "stale":
                    source.write_text("deliberate source change\n")
                else:
                    live.unlink()
                with self.assertRaises(ValueError):
                    FILES.reverse(
                        self.files, self.home, self.state, [self.key, key], True
                    )
                self.assertEqual(self.source.read_text(), "source\n")

    def test_secrets_rejected_without_output_or_source_changes(self) -> None:
        self.deploy()
        secret = "ghp_" + "x" * 36
        self.live.write_text(secret)
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(ValueError):
            FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.assertNotIn(secret, output.getvalue())
        self.assertEqual(self.source.read_text(), "source\n")
        with contextlib.redirect_stdout(output):
            FILES.reverse(self.files, self.home, self.state, [], False)
        self.assertNotIn(secret, output.getvalue())

    def test_missing_baseline_and_absence_are_not_importable(self) -> None:
        self.live.parent.mkdir(parents=True)
        self.live.write_text("local\n")
        with self.assertRaises(ValueError):
            FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.live.unlink()
        with self.assertRaises(ValueError):
            FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.assertEqual(self.source.read_text(), "source\n")

    def test_quoted_credential_keys_rejected(self) -> None:
        self.deploy()
        for quote in ('"', "'"):
            for key in ("api_key", "password", "ACCESS_TOKEN", "client_secret"):
                with self.subTest(quote=quote, key=key):
                    self.live.write_text(
                        f"```json\n{{\n  {quote}{key}{quote}: "
                        f"{quote}synthetic-review-value-12345{quote}\n}}\n```\n"
                    )
                    with self.assertRaises(ValueError):
                        FILES.reverse(
                            self.files, self.home, self.state, [self.key], True
                        )
                    self.assertEqual(self.source.read_text(), "source\n")

    def test_source_conflict_preserved_and_prior_import_rolled_back(self) -> None:
        key = "config/rules/second.md"
        source = self.source.with_name("second.md")
        source.write_text("second\n")
        self.files = FILES.inventory(self.step)
        self.deploy()
        identities = {k: FILES.receipt(self.state, k) for k in (self.key, key)}
        self.live.write_text("incoming first\n")
        FILES.destination(self.home, key).write_text("incoming second\n")
        original_replace = FILES.replace

        def edit_second_after_first(path: Path, data: bytes, mode: int) -> None:
            original_replace(path, data, mode)
            if path == self.source and data == b"incoming first\n":
                source.write_text("independent user edit\n")

        with (
            patch.object(FILES, "replace", edit_second_after_first),
            self.assertRaises(ValueError),
        ):
            FILES.reverse(self.files, self.home, self.state, [self.key, key], True)
        self.assertEqual(self.source.read_text(), "source\n")
        self.assertEqual(source.read_text(), "independent user edit\n")
        self.assertEqual(
            identities, {k: FILES.receipt(self.state, k) for k in identities}
        )

    def test_agent_frontmatter_change_refused(self) -> None:
        key = "config/agents/example.md"
        source = self.step / "_config/kilo/agents/example.md"
        source.write_text("---\npermission:\n  bash: deny\n---\nbody\n")
        self.files = FILES.inventory(self.step)
        self.deploy()
        live = FILES.destination(self.home, key)
        live.write_text(source.read_text().replace("deny", "allow"))
        with self.assertRaises(ValueError):
            FILES.reverse(self.files, self.home, self.state, [key], True)

    def test_import_failure_restores_source_and_paired_receipts(self) -> None:
        key = "config/rules/second.md"
        source = self.step / "_config/kilo/rules/second.md"
        source.write_text("second\n")
        self.files = FILES.inventory(self.step)
        self.deploy()
        identities = {k: FILES.receipt(self.state, k) for k in (self.key, key)}
        self.live.write_text("new\n")
        FILES.destination(self.home, key).write_text("new second\n")
        original_replace = FILES.replace

        def fail_second(path: Path, data: bytes, mode: int) -> None:
            if path == source and data == b"new second\n":
                raise OSError("synthetic failure")
            original_replace(path, data, mode)

        with patch.object(FILES, "replace", fail_second), self.assertRaises(OSError):
            FILES.reverse(self.files, self.home, self.state, [self.key, key], True)
        self.assertEqual(self.source.read_text(), "source\n")
        self.assertEqual(source.read_text(), "second\n")
        self.assertEqual(
            identities, {k: FILES.receipt(self.state, k) for k in identities}
        )

    def test_rollback_continues_after_conflict_or_restore_failure(self) -> None:
        keys = [self.key, "config/rules/second.md", "config/rules/third.md"]
        second = self.source.with_name("second.md")
        third = self.source.with_name("third.md")
        second.write_text("second\n")
        third.write_text("third\n")
        self.files = FILES.inventory(self.step)
        original_replace = FILES.replace
        for failure in ("conflict", "restore failure"):
            with self.subTest(failure=failure):
                second.write_text("second\n")
                self.deploy()
                identities = {k: FILES.receipt(self.state, k) for k in keys}
                for key in keys:
                    FILES.destination(self.home, key).write_text("incoming\n")

                def fail_third(
                    path: Path, data: bytes, mode: int, failure: str = failure
                ) -> None:
                    if path == third and data == b"incoming\n":
                        if failure == "conflict":
                            second.write_text("external edit\n")
                        raise OSError("synthetic import failure")
                    if (
                        failure == "restore failure"
                        and path == second
                        and data == b"second\n"
                    ):
                        raise OSError("synthetic restore failure")
                    original_replace(path, data, mode)

                diagnostics = io.StringIO()
                with (
                    patch.object(FILES, "replace", fail_third),
                    contextlib.redirect_stderr(diagnostics),
                    self.assertRaises(OSError),
                ):
                    FILES.reverse(self.files, self.home, self.state, keys, True)
                self.assertEqual(self.source.read_text(), "source\n")
                self.assertEqual(third.read_text(), "third\n")
                expected = "external edit\n" if failure == "conflict" else "incoming\n"
                self.assertEqual(second.read_text(), expected)
                self.assertIn("rollback incomplete", diagnostics.getvalue())
                self.assertNotIn(expected.strip(), diagnostics.getvalue())
                self.assertEqual(
                    identities, {k: FILES.receipt(self.state, k) for k in keys}
                )

    def test_partial_deployment_keeps_prior_receipt(self) -> None:
        second = self.step / "_config/kilo/rules/second.md"
        second.write_text("second\n")
        self.files = FILES.inventory(self.step)
        original_record = FILES.record

        def fail_record(root: Path, key: str, source: bytes, content: bytes) -> None:
            if key.endswith("second.md"):
                raise OSError("synthetic receipt failure")
            original_record(root, key, source, content)

        with patch.object(FILES, "record", fail_record), self.assertRaises(OSError):
            self.deploy()
        self.assertEqual(self.live.read_text(), "source\n")
        self.assertIsNotNone(FILES.receipt(self.state, self.key))
        self.assertIsNone(FILES.receipt(self.state, "config/rules/second.md"))

    def test_interruption_after_rename_restores_bytes_modes_and_receipts(self) -> None:
        self.source.chmod(0o640)
        self.deploy()
        identity = FILES.receipt(self.state, self.key)
        self.live.write_text("incoming\n")
        original_replace = FILES.replace

        def interrupted_replace(path: Path, data: bytes, mode: int) -> None:
            original_replace(path, data, mode)
            if path == self.source and data == b"incoming\n":
                raise KeyboardInterrupt

        with (
            patch.object(FILES, "replace", interrupted_replace),
            self.assertRaises(KeyboardInterrupt),
        ):
            FILES.reverse(self.files, self.home, self.state, [self.key], True)
        self.assertEqual(self.source.read_text(), "source\n")
        self.assertEqual(self.source.stat().st_mode & 0o777, 0o640)
        self.assertEqual(identity, FILES.receipt(self.state, self.key))

    def test_non_text_and_sensitive_filename_rejected(self) -> None:
        self.deploy()
        for incoming in (b"\xff\xfe", b"text\x01"):
            self.live.write_bytes(incoming)
            with self.assertRaises(ValueError):
                FILES.reverse(self.files, self.home, self.state, [self.key], True)
            self.assertEqual(self.source.read_text(), "source\n")
        secret = "ghp_" + "x" * 36
        (self.source.parent / f"{secret}.md").write_text("text\n")
        with self.assertRaises(ValueError):
            FILES.inventory(self.step)

    def test_ignore_source_admission(self) -> None:
        source = self.step / ".kilocodeignore"
        source.unlink()
        for mode in ("missing", "symlink", "directory"):
            with self.subTest(mode=mode):
                if mode == "symlink":
                    source.symlink_to(self.source)
                elif mode == "directory":
                    source.mkdir()
                with self.assertRaises(ValueError):
                    FILES.preflight(self.step, self.home, self.files)
                if source.is_symlink():
                    source.unlink()
                elif source.is_dir():
                    source.rmdir()

    def test_inventory_roots_and_traversal_errors_fail_closed(self) -> None:
        missing = self.step / "_config/kilo/commands"
        missing.rmdir()
        with self.assertRaises(ValueError):
            FILES.inventory(self.step)
        missing.mkdir()

        def denied_walk(root: Path, **kwargs: object) -> list:
            kwargs["onerror"](PermissionError("synthetic traversal failure"))
            return []

        with (
            patch.object(FILES.os, "walk", denied_walk),
            self.assertRaises(PermissionError),
        ):
            FILES.inventory(self.step)

    def test_canonical_json_syntax_and_root_shape_precede_writes(self) -> None:
        source = self.step / "_config/kilo/kilo.json"
        for content in ("{broken", "[]"):
            source.write_text(content)
            with self.subTest(content=content), self.assertRaises(ValueError):
                FILES.preflight(self.step, self.home, self.files)
            self.assertFalse(self.state.exists())
            self.assertFalse(self.live.exists())

    def test_hardlinked_source_and_state_rejected(self) -> None:
        alias = self.root / "source-alias.md"
        os.link(self.source, alias)
        with self.assertRaises(ValueError):
            FILES.inventory(self.step)
        alias.unlink()
        self.deploy()
        os.link(
            FILES.receipt_path(self.state, self.key), self.root / "state-alias.json"
        )
        with self.assertRaises(ValueError):
            FILES.preflight(self.step, self.home, self.files)

    def test_source_manifest_ignore_and_state_ancestor_redirection(self) -> None:
        self.deploy()
        ignore_destination = self.step.parents[2] / ".kilocodeignore"
        ignore_destination.write_text("local\n")
        targets = [
            self.step / "_config/kilo/rules",
            self.source,
            self.step / "default-skills.txt",
            self.step / ".kilocodeignore",
            ignore_destination,
            self.state.parent,
        ]
        for target in targets:
            with self.subTest(target=target):
                held = target.with_name(target.name + "-held")
                target.rename(held)
                target.symlink_to(held, target_is_directory=held.is_dir())
                try:
                    with self.assertRaises(ValueError):
                        files = FILES.inventory(self.step)
                        FILES.preflight(self.step, self.home, files)
                finally:
                    target.unlink()
                    held.rename(target)
        self.source.unlink()
        self.source.symlink_to(self.root / "absent.md")
        with self.assertRaises(ValueError):
            FILES.inventory(self.step)

    def test_retirement_preserves_unknown_modified_and_nested_extras(self) -> None:
        key = "config/rules/workspace-temp.md"
        target = FILES.destination(self.home, key)
        target.parent.mkdir(parents=True)
        target.write_text("old\n")
        extra = target.parent / "user-extra.md"
        extra.write_text("keep\n")
        FILES.retire(self.home, self.state)
        self.assertTrue(target.exists())
        FILES.record(self.state, key, b"old\n", b"old\n")
        target.write_text("modified\n")
        FILES.retire(self.home, self.state)
        self.assertTrue(target.exists())
        target.write_text("old\n")
        FILES.retire(self.home, self.state)
        self.assertFalse(target.exists())
        self.assertEqual(extra.read_text(), "keep\n")

    def test_deselected_optional_retained_without_refresh(self) -> None:
        self.deploy("skills", "optional")
        live = FILES.destination(self.home, "skills/optional/SKILL.md")
        live.write_text("user modified optional\n")
        nested = live.parent / "extras/local.txt"
        nested.parent.mkdir()
        nested.write_text("keep\n")
        self.deploy("skills")
        self.assertEqual(live.read_text(), "user modified optional\n")
        self.assertEqual(nested.read_text(), "keep\n")

    def test_redirected_root_parent_leaf_and_receipt_rejected(self) -> None:
        self.deploy()
        targets = [
            self.home / ".config/kilo",
            self.live.parent,
            self.live,
            self.state,
            FILES.receipt_path(self.state, self.key),
        ]
        for target in targets:
            with self.subTest(target=target):
                held = target.with_name(target.name + "-held")
                target.rename(held)
                target.symlink_to(held, target_is_directory=held.is_dir())
                try:
                    with self.assertRaises(ValueError):
                        FILES.preflight(self.step, self.home, self.files)
                finally:
                    target.unlink()
                    held.rename(target)

    def test_manifest_duplicates_unknown_and_bad_receipts(self) -> None:
        for content in ("example\nexample\n", "../escape\n", "unknown\n"):
            (self.step / "default-skills.txt").write_text(content)
            with self.assertRaises(ValueError):
                FILES.inventory(self.step)
        (self.step / "default-skills.txt").write_text("example\n")
        self.deploy()
        path = FILES.receipt_path(self.state, self.key)
        path.write_text(json.dumps({"path": self.key, "source": "invalid"}))
        with self.assertRaises(ValueError):
            FILES.preflight(self.step, self.home, self.files)


if __name__ == "__main__":
    if os.getuid() == 0:
        sys_message = "Run these isolated tests as a non-root user."
        raise SystemExit(sys_message)
    unittest.main()
