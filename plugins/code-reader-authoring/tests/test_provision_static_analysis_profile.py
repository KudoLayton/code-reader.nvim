"""Regression tests for approved user static-analysis profile provisioning."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import provision_static_analysis_profile  # noqa: E402
import static_metrics  # noqa: E402


KOTLIN_CANDIDATE = {
    "schema": "code-reader-static-analysis-profile-candidate/v1",
    "language": "kotlin",
    "expected_abi": 15,
    "profile": {
        "extensions": [".kt", ".kts"],
        "backend": "tree-sitter-v1",
        "runtime_family": "tree-sitter-abi-13-15",
        "grammar_module": "tree_sitter_kotlin",
        "definition_nodes": ["function_declaration"],
        "target_definition_nodes": {
            "function": ["function_declaration"],
            "type": ["class_declaration"],
        },
        "decision_nodes": ["if_expression"],
        "binding_nodes": ["variable_declaration"],
        "region_nodes": ["block"],
        "required_dependencies": [{"name": "tree-sitter-kotlin", "version": "1.1.0"}],
    },
}


class ProvisionStaticAnalysisProfileTest(unittest.TestCase):
    def test_candidate_is_not_installed_or_saved_without_approval(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.object(
            provision_static_analysis_profile.bootstrap_static_analysis, "ensure_profile"
        ) as ensure:
            result = provision_static_analysis_profile.provision_candidate(
                KOTLIN_CANDIDATE, approve=False, cache_root=Path(directory)
            )

        self.assertEqual(result["status"], "NOT_APPROVED")
        ensure.assert_not_called()

    def test_approved_candidate_is_verified_then_saved_in_user_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.object(
            provision_static_analysis_profile.bootstrap_static_analysis,
            "ensure_profile",
            return_value={"status": "READY", "grammar_abi": 15},
        ):
            result = provision_static_analysis_profile.provision_candidate(
                KOTLIN_CANDIDATE, approve=True, cache_root=Path(directory)
            )

            self.assertEqual(result["status"], "READY")
            profile_path = Path(directory) / "profiles.json"
            stored = json.loads(profile_path.read_text(encoding="utf-8"))
            self.assertEqual(stored["profiles"]["kotlin"]["grammar_abi"], 15)
            with patch.dict(os.environ, {"CODE_READER_STATIC_ANALYSIS_CACHE": directory}):
                self.assertEqual(static_metrics.language_for_path("example.kt"), "kotlin")

    def test_approved_candidate_with_a_different_observed_abi_is_not_saved(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.object(
            provision_static_analysis_profile.bootstrap_static_analysis,
            "ensure_profile",
            return_value={"status": "READY", "grammar_abi": 14},
        ):
            result = provision_static_analysis_profile.provision_candidate(
                KOTLIN_CANDIDATE, approve=True, cache_root=Path(directory)
            )

            self.assertEqual(result["status"], "NOT_AVAILABLE")
            self.assertFalse((Path(directory) / "profiles.json").exists())

    def test_candidate_rejects_a_dependency_version_with_a_url(self) -> None:
        candidate = deepcopy(KOTLIN_CANDIDATE)
        candidate["profile"]["required_dependencies"][0]["version"] = "1.1.0 @ https://example.invalid/parser.whl"

        result = provision_static_analysis_profile.validate_candidate(candidate)

        self.assertEqual(result["status"], "INVALID_CANDIDATE")
