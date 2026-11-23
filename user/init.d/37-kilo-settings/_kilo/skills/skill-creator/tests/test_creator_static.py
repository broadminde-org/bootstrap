"""Source-only checks. No helper imports/execution, fixtures, writes, or installs.

These assertions are not runtime/security qualification. Do not run under an
authorization that excludes tests; inspect/compile this source only instead.
"""

import ast
import unittest
from pathlib import Path

ROOT = Path(__file__).absolute().parents[1]


class CreatorSourceTests(unittest.TestCase):
    def test_helpers_parse_without_execution(self) -> None:
        for name in ("init_skill.py", "quick_validate.py", "package_skill.py"):
            with self.subTest(name=name):
                ast.parse((ROOT / "scripts" / name).read_text(encoding="utf-8"))

    def test_no_preparation_or_process_execution_imports(self) -> None:
        for path in (ROOT / "scripts").glob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            imports = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.update(alias.name.split(".")[0] for alias in node.names)
                elif isinstance(node, ast.ImportFrom):
                    imports.add((node.module or "").split(".")[0])
            self.assertFalse(imports & {"subprocess", "pip", "venv", "ensurepip"})

    def test_initializer_template_has_no_example_resources(self) -> None:
        tree = ast.parse(
            (ROOT / "scripts" / "init_skill.py").read_text(encoding="utf-8")
        )
        template = next(
            ast.literal_eval(node.value)
            for node in tree.body
            if isinstance(node, ast.Assign)
            and any(
                isinstance(t, ast.Name) and t.id == "SKILL_TEMPLATE"
                for t in node.targets
            )
        )
        self.assertIn('description: "', template)
        self.assertNotIn("example.py", template)
        self.assertNotIn("api_reference.md", template)

    def test_declared_parser_matches_requirement(self) -> None:
        tree = ast.parse(
            (ROOT / "scripts" / "quick_validate.py").read_text(encoding="utf-8")
        )
        version = next(
            ast.literal_eval(node.value)
            for node in tree.body
            if isinstance(node, ast.Assign)
            and any(
                isinstance(t, ast.Name) and t.id == "PARSER_VERSION"
                for t in node.targets
            )
        )
        requirements = (ROOT / "scripts" / "requirements.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn(f"PyYAML=={version}", requirements.splitlines())


if __name__ == "__main__":
    unittest.main()
