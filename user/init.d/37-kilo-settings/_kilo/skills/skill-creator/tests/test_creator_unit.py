"""Dependency-free unit regressions for creator input screening and limits."""

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).absolute().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import package_skill  # noqa: E402
import quick_validate  # noqa: E402


class CreatorLimitTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="creator-limits-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.root = self.work / "sample-skill"
        self.root.mkdir()
        self.inventory = self.work / "review.json"

    def review(self, *names: str) -> None:
        entries = [
            {
                "path": name,
                "sha256": hashlib.sha256((self.root / name).read_bytes()).hexdigest(),
            }
            for name in names
        ]
        self.inventory.write_bytes(
            json.dumps({"files": entries}).encode("utf-8")
        )

    def test_reviewed_file_over_per_file_limit_is_refused(self) -> None:
        (self.root / "SKILL.md").write_bytes(b"S" * 65)
        self.review("SKILL.md")
        with (
            patch.object(package_skill, "MAX_FILE_BYTES", 64),
            self.assertRaisesRegex(ValueError, "per-file size limit"),
        ):
            package_skill.reviewed_files(self.root, self.inventory)

    def test_credential_assignments_are_refused(self) -> None:
        (self.root / "SKILL.md").write_bytes(b"Synthetic public instructions")
        for key in ("password", "passwd", "token", "secret", "api_key", "api-key"):
            for content in (
                f'{key}=synthetic123',
                json.dumps({key: "synthetic123"}),
                f"'{key}' : 'synthetic123'",
            ):
                with self.subTest(key=key, content=content):
                    (self.root / "data.txt").write_text(content, encoding="utf-8")
                    self.review("SKILL.md", "data.txt")
                    with self.assertRaisesRegex(
                        ValueError, "sensitive content refused"
                    ):
                        package_skill.reviewed_files(self.root, self.inventory)

    def test_quoted_key_placeholders_remain_admitted(self) -> None:
        (self.root / "SKILL.md").write_bytes(b"Synthetic public instructions")
        for value in (
            "${PASSWORD}",
            "<password>",
            "TODO-value",
            "placeholder",
            "example-value",
            "changeme",
        ):
            with self.subTest(value=value):
                content = json.dumps({"password": value}).encode("utf-8")
                (self.root / "data.txt").write_bytes(content)
                self.review("SKILL.md", "data.txt")
                payload = package_skill.reviewed_files(self.root, self.inventory)
                self.assertEqual(payload["data.txt"], content)

    def test_inventory_json_over_limit_is_refused(self) -> None:
        self.inventory.write_bytes(b"{}" + b" " * 63)
        with (
            patch.object(package_skill, "MAX_INVENTORY_BYTES", 64),
            self.assertRaisesRegex(ValueError, "per-file size limit"),
        ):
            package_skill.reviewed_files(self.root, self.inventory)

    def test_aggregate_limit_includes_inventory_and_reviewed_files(self) -> None:
        (self.root / "SKILL.md").write_bytes(b"S" * 32)
        (self.root / "extra.txt").write_bytes(b"E" * 32)
        self.review("SKILL.md", "extra.txt")
        aggregate_limit = self.inventory.stat().st_size + 63
        with (
            patch.multiple(
                package_skill,
                MAX_FILE_BYTES=64,
                MAX_INVENTORY_BYTES=4096,
                MAX_TOTAL_BYTES=aggregate_limit,
            ),
            self.assertRaisesRegex(ValueError, "aggregate size limit"),
        ):
            package_skill.reviewed_files(self.root, self.inventory)

    def test_growth_after_stat_is_caught_by_bounded_read(self) -> None:
        path = self.work / "growing.txt"
        path.write_bytes(b"12345678")
        original_fstat = quick_validate.os.fstat
        original_fdopen = quick_validate.os.fdopen
        read_sizes = []

        class ReadSpy:
            def __init__(self, stream):
                self.stream = stream

            def __enter__(self):
                self.stream.__enter__()
                return self

            def __exit__(self, *args):
                return self.stream.__exit__(*args)

            def fileno(self):
                return self.stream.fileno()

            def read(self, size=-1):
                read_sizes.append(size)
                return self.stream.read(size)

        def tracking_fdopen(*args):
            return ReadSpy(original_fdopen(*args))

        def grow_after_stat(fd: int):
            info = original_fstat(fd)
            with path.open("ab") as stream:
                stream.write(b"9")
            return info

        with (
            patch.object(quick_validate.os, "fdopen", side_effect=tracking_fdopen),
            patch.object(quick_validate.os, "fstat", side_effect=grow_after_stat),
            self.assertRaisesRegex(ValueError, "per-file size limit"),
        ):
            quick_validate.read_regular(path, max_bytes=8)
        self.assertEqual(read_sizes, [9])


if __name__ == "__main__":
    unittest.main()
