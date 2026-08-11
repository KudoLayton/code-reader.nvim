"""Regression tests for the pinned static-analysis dependency bootstrap."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import bootstrap_static_analysis  # noqa: E402


class BootstrapStaticAnalysisTest(unittest.TestCase):
    def test_stdlib_profile_needs_no_install(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = bootstrap_static_analysis.ensure("lua", Path(directory))
        self.assertEqual(result["status"], "READY")
        self.assertFalse(result["installed"])
        self.assertIsNone(result["site_packages"])

    def test_unknown_profile_cannot_select_an_unregistered_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = bootstrap_static_analysis.ensure("unknown", Path(directory))
        self.assertEqual(result["status"], "NOT_AVAILABLE")
        self.assertIsNone(result["site_packages"])


if __name__ == "__main__":
    unittest.main()
