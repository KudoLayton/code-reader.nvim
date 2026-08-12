#!/usr/bin/env python
"""Install an AI-proposed Tree-sitter profile only after explicit user approval."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

import bootstrap_static_analysis
import static_analysis_registry


CANDIDATE_SCHEMA = "code-reader-static-analysis-profile-candidate/v1"
_LANGUAGE_RE = re.compile(r"[a-z][a-z0-9-]*")
_MODULE_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_PACKAGE_RE = re.compile(r"tree-sitter-[a-z0-9-]+")
_VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.!+_-]*")
_REQUIRED_PROFILE_KEYS = {
    "extensions",
    "backend",
    "runtime_family",
    "grammar_module",
    "definition_nodes",
    "target_definition_nodes",
    "decision_nodes",
    "binding_nodes",
    "region_nodes",
    "required_dependencies",
}


def _invalid(reason: str) -> dict[str, Any]:
    return {"status": "INVALID_CANDIDATE", "reason": reason}


def validate_candidate(candidate: dict[str, Any], cache_root: Path | None = None) -> tuple[str, dict[str, Any], int] | dict[str, Any]:
    if candidate.get("schema") != CANDIDATE_SCHEMA:
        return _invalid("candidate schema is not supported")
    language = candidate.get("language")
    expected_abi = candidate.get("expected_abi")
    profile = candidate.get("profile")
    if not isinstance(language, str) or not _LANGUAGE_RE.fullmatch(language):
        return _invalid("candidate language must be lowercase hyphenated text")
    if expected_abi not in (13, 14, 15):
        return _invalid("candidate expected_abi must be 13, 14, or 15")
    if not isinstance(profile, dict) or not _REQUIRED_PROFILE_KEYS.issubset(profile):
        return _invalid("candidate profile is incomplete")
    if profile.get("backend") != "tree-sitter-v1" or profile.get("runtime_family") != "tree-sitter-abi-13-15":
        return _invalid("candidate must use the supported Tree-sitter ABI 13 through 15 runtime family")
    if not isinstance(profile.get("grammar_module"), str) or not _MODULE_RE.fullmatch(profile["grammar_module"]):
        return _invalid("candidate grammar_module is invalid")
    extensions = profile.get("extensions")
    if not isinstance(extensions, list) or not extensions or any(
        not isinstance(extension, str) or not re.fullmatch(r"\.[a-z0-9+_-]+", extension) for extension in extensions
    ):
        return _invalid("candidate extensions must be a non-empty list of lowercase suffixes")
    dependencies = profile.get("required_dependencies")
    if (
        not isinstance(dependencies, list)
        or len(dependencies) != 1
        or not isinstance(dependencies[0], dict)
        or not isinstance(dependencies[0].get("name"), str)
        or not _PACKAGE_RE.fullmatch(dependencies[0]["name"])
        or not isinstance(dependencies[0].get("version"), str)
        or not _VERSION_RE.fullmatch(dependencies[0]["version"])
    ):
        return _invalid("candidate must declare one pinned tree-sitter-* grammar package")
    target_nodes = profile.get("target_definition_nodes")
    if not isinstance(target_nodes, dict) or not target_nodes.get("function") or not target_nodes.get("type"):
        return _invalid("candidate needs function and type target definition nodes")
    for key in ("definition_nodes", "decision_nodes", "binding_nodes", "region_nodes"):
        if not isinstance(profile[key], list):
            return _invalid(f"candidate {key} must be a list")

    existing_profiles = static_analysis_registry.load_profiles(cache_root)
    if language in existing_profiles:
        return _invalid(f"a profile already exists for `{language}`")
    existing_extensions = {
        extension
        for existing in existing_profiles.values()
        for extension in existing.get("extensions", [])
    }
    if existing_extensions.intersection(extensions):
        return _invalid("candidate extensions overlap an existing profile")
    return language, profile, expected_abi


def provision_candidate(
    candidate: dict[str, Any], *, approve: bool, cache_root: Path | None = None
) -> dict[str, Any]:
    if not approve:
        return {
            "status": "NOT_APPROVED",
            "reason": "review the AI-proposed parser candidate and rerun with --approve to install it",
        }
    validated = validate_candidate(candidate, cache_root)
    if isinstance(validated, dict):
        return validated
    language, profile, expected_abi = validated
    result = bootstrap_static_analysis.ensure_profile(language, profile, cache_root)
    if result.get("status") != "READY":
        return result
    if result.get("grammar_abi") != expected_abi:
        return {
            "status": "NOT_AVAILABLE",
            "reason": f"candidate expected grammar ABI {expected_abi}, but the installed grammar reports ABI {result.get('grammar_abi')}",
        }
    stored_profile = {
        **profile,
        "grammar_abi": result["grammar_abi"],
        "provisioned": {"runtime_abi": result.get("runtime_abi"), "approved": True},
    }
    profile_path = static_analysis_registry.save_user_profile(language, stored_profile, cache_root)
    return {**result, "profile_path": str(profile_path)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, help="AI-proposed profile candidate JSON file")
    parser.add_argument("--approve", action="store_true", help="Confirm installation of this candidate")
    parser.add_argument("--cache-root", help="Override the user cache directory")
    args = parser.parse_args()
    try:
        candidate = json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        result = _invalid(f"cannot read candidate JSON: {error}")
    else:
        cache_root = Path(args.cache_root).resolve() if args.cache_root else None
        result = provision_candidate(candidate, approve=args.approve, cache_root=cache_root)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "READY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
