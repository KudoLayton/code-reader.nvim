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

    def test_python_complete_partial_region_has_its_own_metrics(self) -> None:
        source = """\
def adjust(value):
    current = value
    if current:
        current += 1
    return current
"""
        result = static_metrics.analyze_range_text(source, "python", "adjust.py", 3, 4)

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        self.assertFalse(result["fallback_required"])
        self.assertEqual(result["analysis_region"]["kind"], "sese_region")
        self.assertEqual(result["analysis_region"]["start_line"], 3)
        self.assertEqual(result["analysis_region"]["end_line"], 4)
        self.assertEqual(result["metrics"]["cyclomatic_complexity"], 2)
        self.assertEqual(result["analysis_region"]["definition"]["name"], "adjust")

    def test_python_cut_control_statement_requires_fallback(self) -> None:
        source = """\
def adjust(value):
    current = value
    if current:
        current += 1
    return current
"""
        result = static_metrics.analyze_range_text(source, "python", "adjust.py", 3, 3)

        self.assertEqual(result["status"], static_metrics.NOT_AVAILABLE)
        self.assertTrue(result["fallback_required"])
        self.assertEqual(result["reason_code"], "NON_SESE_RANGE")

    def test_python_comment_and_blank_padding_do_not_cut_a_region(self) -> None:
        source = """\
def adjust(value):
    current = value

    # Apply the selected branch.
    if current:
        current += 1
    return current
"""
        result = static_metrics.analyze_range_text(source, "python", "adjust.py", 3, 6)

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        self.assertEqual(result["analysis_region"]["start_line"], 5)
        self.assertEqual(result["analysis_region"]["end_line"], 6)

    def test_lua_complete_partial_region_has_its_own_metrics(self) -> None:
        source = """\
local function adjust(value)
  if value then
    return value + 1
  end
  return value
end
"""
        result = static_metrics.analyze_range_text(source, "lua", "adjust.lua", 2, 4)

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        self.assertFalse(result["fallback_required"])
        self.assertEqual(result["analysis_region"]["kind"], "sese_region")
        self.assertEqual(result["metrics"]["cyclomatic_complexity"], 2)

    def test_lua_cut_control_statement_requires_fallback(self) -> None:
        source = """\
local function adjust(value)
  if value then
    return value + 1
  end
  return value
end
"""
        result = static_metrics.analyze_range_text(source, "lua", "adjust.lua", 2, 3)

        self.assertEqual(result["status"], static_metrics.NOT_AVAILABLE)
        self.assertTrue(result["fallback_required"])
        self.assertEqual(result["reason_code"], "NON_SESE_RANGE")

    def test_lua_complete_statement_region_has_metrics(self) -> None:
        source = """\
local function adjust(value)
  if value then
    return value + 1
  end
  return value
end
"""
        result = static_metrics.analyze_range_text(source, "lua", "adjust.lua", 5, 5)

        self.assertEqual(result["status"], static_metrics.SUPPORTED)
        self.assertEqual(result["analysis_region"]["kind"], "sese_region")
        self.assertEqual(result["metrics"]["cyclomatic_complexity"], 1)

    def test_tree_sitter_profiles_define_structural_region_nodes(self) -> None:
        for language, profile in static_metrics.load_profiles().items():
            if profile["backend"] == "tree-sitter-v1":
                self.assertTrue(profile.get("region_nodes"), language)

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
        self.assertEqual(result["range_analysis"]["analysis_region"]["kind"], "definition")


if __name__ == "__main__":
    unittest.main()
