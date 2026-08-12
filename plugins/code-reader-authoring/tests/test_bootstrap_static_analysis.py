"""Regression tests for the pinned static-analysis dependency bootstrap."""

from __future__ import annotations

import sys
import tempfile
import unittest
import json
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch


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
        self.assertEqual(result["status"], "PROVISION_REQUIRED")
        self.assertIsNone(result["site_packages"])

    def test_tree_sitter_profile_installs_only_its_runtime_and_grammar(self) -> None:
        self.assertEqual(
            bootstrap_static_analysis.dependency_specs("cpp"),
            ["tree-sitter==0.25.0", "tree-sitter-cpp==0.23.4"],
        )

    def test_built_in_profile_cannot_drift_from_its_grammar_lock(self) -> None:
        profile = deepcopy(bootstrap_static_analysis.static_analysis_registry.load_builtin_profiles()["cpp"])
        profile["required_dependencies"][0]["version"] = "0.0.0"

        with self.assertRaisesRegex(ValueError, "pinned lock"):
            bootstrap_static_analysis.dependency_specs_for_profile(profile, built_in=True)

    def test_abi_13_through_15_are_accepted_and_12_is_rejected(self) -> None:
        for grammar_abi in (13, 14, 15):
            self.assertTrue(bootstrap_static_analysis.abi_is_compatible(13, 15, grammar_abi))
        self.assertFalse(bootstrap_static_analysis.abi_is_compatible(13, 15, 12))

    def test_cpp_abi_15_is_rejected_by_the_previous_13_through_14_loader(self) -> None:
        probe = {
            "status": "READY",
            "runtime_abi": {"minimum": 13, "maximum": 14},
            "grammar_abi": 15,
        }

        self.assertFalse(bootstrap_static_analysis._probe_is_compatible(probe))
        self.assertIn("grammar ABI 15", bootstrap_static_analysis._probe_reason(probe))

    def test_registered_runtime_must_cover_the_configured_13_through_15_range(self) -> None:
        profile = bootstrap_static_analysis.static_analysis_registry.load_profiles()["cpp"]
        probe = {
            "status": "READY",
            "runtime_abi": {"minimum": 13, "maximum": 14},
            "grammar_abi": 14,
        }

        self.assertFalse(bootstrap_static_analysis._probe_is_compatible(probe, profile))

    def test_parser_catalog_snapshots_the_supported_wiki_abi_range(self) -> None:
        catalog = bootstrap_static_analysis.static_analysis_registry.load_parser_catalog()

        self.assertEqual(catalog["supported_abi_range"], {"minimum": 13, "maximum": 15})

    def test_tree_sitter_cache_marker_records_verified_abi(self) -> None:
        probe = {
            "status": "READY",
            "runtime_abi": {"minimum": 13, "maximum": 15},
            "grammar_abi": 15,
        }
        with tempfile.TemporaryDirectory() as directory, patch.object(
            bootstrap_static_analysis, "_install", return_value=None
        ) as install, patch.object(
            bootstrap_static_analysis, "_probe_tree_sitter", return_value=probe
        ):
            result = bootstrap_static_analysis.ensure("cpp", Path(directory))

            self.assertEqual(result["status"], "READY")
            self.assertTrue(result["installed"])
            self.assertEqual(result["grammar_abi"], 15)
            install.assert_called_once()
            marker = Path(result["site_packages"]).parent / "installed.json"
            stored = json.loads(marker.read_text(encoding="utf-8"))
            self.assertEqual(stored["abi"], probe)


if __name__ == "__main__":
    unittest.main()
