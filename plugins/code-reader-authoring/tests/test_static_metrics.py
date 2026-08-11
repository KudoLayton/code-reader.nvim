"""Regression tests for the dependency-free Code Reader static metrics API."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import static_metrics  # noqa: E402


class StaticMetricsTest(unittest.TestCase):
    def test_python_function_metrics_and_smallest_definition_selection(self) -> None:
        source = """\
class Calculator:
    def choose(self, first, second, fallback):
        if first and second:
            return first + second + fallback
        return fallback
"""
        result = static_metrics.analyze_text(source, "python", "calculator.py")

        self.assertEqual(result["schema"], "code-reader-static-metrics/v1")
        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        definition = result["definitions"][0]
        self.assertEqual(definition["qualified_name"], "Calculator.choose")
        self.assertEqual(definition["start_line"], 2)
        self.assertEqual(definition["end_line"], 5)
        self.assertEqual(definition["metrics"]["cyclomatic_complexity"], 3)
        self.assertEqual(definition["metrics"]["peak_live_bindings"], 3)
        self.assertEqual(static_metrics.select_definition_for_range(result, 3, 4)["id"], definition["id"])
        self.assertIsNone(static_metrics.select_definition_for_range(result, 1, 5))

    def test_nested_python_function_does_not_inflate_outer_complexity(self) -> None:
        source = """\
def outer(value):
    def inner(item):
        if item:
            return item
        return 0
    return inner(value)
"""
        result = static_metrics.analyze_text(source, "py", "nested.py")

        outer, inner = result["definitions"]
        self.assertEqual(outer["metrics"]["cyclomatic_complexity"], 1)
        self.assertEqual(inner["metrics"]["cyclomatic_complexity"], 2)
        self.assertEqual(static_metrics.select_definition_for_range(result, 3, 4)["name"], "inner")

    def test_lua_function_metrics(self) -> None:
        source = """\
local function choose(first, second, fallback)
  local result = fallback
  if first and second then
    result = first
  elseif fallback then
    result = second
  end
  return result
end
"""
        result = static_metrics.analyze_text(source, "lua", "choose.lua")

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        definition = result["definitions"][0]
        self.assertEqual(definition["name"], "choose")
        self.assertEqual(definition["metrics"]["cyclomatic_complexity"], 4)
        self.assertGreaterEqual(definition["metrics"]["peak_live_bindings"], 2)

    def test_registered_language_requires_its_pinned_parser(self) -> None:
        result = static_metrics.analyze_text("function value() {}", "typescript", "value.ts")

        self.assertEqual(result["status"], static_metrics.NOT_AVAILABLE)
        self.assertEqual(result["backend"], "tree-sitter-v1")
        self.assertIn("pinned Tree-sitter dependency", result["reason"])
        self.assertEqual(result["definitions"], [])

    def test_python_parse_failure_is_reported(self) -> None:
        result = static_metrics.analyze_text("def broken(:\n", "python", "broken.py")

        self.assertEqual(result["status"], static_metrics.PARSE_ERROR)
        self.assertEqual(result["definitions"], [])

    def test_cli_returns_selection_in_json(self) -> None:
        script = SCRIPTS / "static_metrics.py"
        completed = subprocess.run(
            [
                sys.executable,
                str(script),
                "--language",
                "python",
                "--text",
                "def add(left, right):\n    return left + right\n",
                "--range",
                "L1-L2",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        self.assertEqual(result["selection"]["definition"]["name"], "add")


if __name__ == "__main__":
    unittest.main()
