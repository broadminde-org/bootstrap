"""Browser-free regressions for the examples' observable result transition."""

import runpy
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch


class ResultTransitionTests(unittest.TestCase):
    def test_result_requires_hidden_to_visible_transition(self) -> None:
        support = runpy.run_path(
            str(Path(__file__).resolve().parents[1] / "examples" / "_support.py")
        )
        for initial, changes, passes in (
            (False, True, True),
            (True, False, False),
            (False, False, False),
        ):
            with self.subTest(initial=initial, changes=changes):
                state = {"visible": initial, "clicks": 0}

                def click(**_kwargs):
                    state["clicks"] += 1
                    if changes:
                        state["visible"] = True

                def expect(locator):
                    def hidden(**_kwargs):
                        self.assertFalse(state["visible"])

                    def visible(**_kwargs):
                        if locator == "result":
                            self.assertTrue(state["visible"])

                    return SimpleNamespace(to_be_hidden=hidden, to_be_visible=visible)

                api = ModuleType("playwright.sync_api")
                api.expect = expect
                page = SimpleNamespace(
                    goto=lambda *_args, **_kwargs: None,
                    locator=lambda selector: SimpleNamespace(click=click)
                    if selector == "action"
                    else selector,
                )
                args = SimpleNamespace(
                    url="http://127.0.0.1",
                    ready_selector="ready",
                    action_selector="action",
                    result_selector="result",
                )
                with patch.dict(sys.modules, {"playwright.sync_api": api}):
                    if passes:
                        support["exercise"](page, args)
                    else:
                        with self.assertRaises(AssertionError):
                            support["exercise"](page, args)
                self.assertEqual(state["clicks"], 0 if initial else 1)


if __name__ == "__main__":
    unittest.main()
