#!/usr/bin/env python
"""Prepare isolated, ABI-verified static-analysis dependencies for one language."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import static_analysis_registry


SCRIPT_DIR = Path(__file__).resolve().parent
LOCK_PATH = SCRIPT_DIR / "static_analysis_requirements.lock.json"
PROBE_PATH = SCRIPT_DIR / "probe_tree_sitter.py"


def default_cache_root() -> Path:
    return static_analysis_registry.default_cache_root()


def _lock() -> dict[str, Any]:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def _runtime_family(profile: dict[str, Any]) -> dict[str, Any]:
    family_name = profile.get("runtime_family")
    family = _lock().get("runtime_families", {}).get(family_name)
    if not isinstance(family, dict):
        raise ValueError("Tree-sitter profile has no supported runtime family")
    return family


def _grammar_dependency(profile: dict[str, Any]) -> dict[str, str]:
    dependencies = profile.get("required_dependencies", [])
    if len(dependencies) != 1:
        raise ValueError("Tree-sitter profile must declare exactly one grammar dependency")
    dependency = dependencies[0]
    if not isinstance(dependency, dict) or not dependency.get("name") or not dependency.get("version"):
        raise ValueError("Tree-sitter grammar dependency is incomplete")
    return {"name": str(dependency["name"]), "version": str(dependency["version"])}


def dependency_specs_for_profile(profile: dict[str, Any], *, built_in: bool = False) -> list[str]:
    if profile.get("backend") != "tree-sitter-v1":
        return []
    runtime = _runtime_family(profile)
    grammar = _grammar_dependency(profile)
    if built_in:
        locked_version = _lock().get("pinned_dependencies", {}).get(grammar["name"])
        if locked_version != grammar["version"]:
            raise ValueError("built-in Tree-sitter grammar dependency does not match the pinned lock")
    return [f"{runtime['package']}=={runtime['version']}", f"{grammar['name']}=={grammar['version']}"]


def dependency_specs(language: str | None) -> list[str]:
    profile = static_analysis_registry.load_profiles().get(language or "")
    if not profile:
        return []
    return dependency_specs_for_profile(
        profile, built_in=(language or "") in static_analysis_registry.load_builtin_profiles()
    )


def cache_site_packages(cache_root: Path, language: str, specs: list[str]) -> Path:
    fingerprint_input = "\n".join([language, *specs])
    fingerprint = hashlib.sha256(fingerprint_input.encode("utf-8")).hexdigest()[:16]
    return cache_root / fingerprint / "site-packages"


def abi_is_compatible(minimum: int, maximum: int, grammar_abi: int) -> bool:
    return minimum <= grammar_abi <= maximum


def _uv_command() -> tuple[str | None, str | None]:
    command = shutil.which("uv")
    if not command:
        return None, "uv is not available on PATH; install uv before running static analysis"
    try:
        completed = subprocess.run(
            [command, "--version"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as error:
        return None, f"uv is not executable: {error}"
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit code {completed.returncode}"
        return None, f"uv --version failed: {detail}"
    return command, None


def _install(site_packages: Path, specs: list[str], uv_command: str) -> str | None:
    completed = subprocess.run(
        [
            uv_command,
            "pip",
            "install",
            "--target",
            str(site_packages),
            *specs,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if completed.returncode != 0:
        return completed.stderr.strip() or "static-analysis dependency installation failed"
    return None


def _probe_tree_sitter(site_packages: Path, profile: dict[str, Any]) -> dict[str, Any]:
    grammar_symbol = profile.get("grammar_symbol", "language")
    completed = subprocess.run(
        [
            sys.executable,
            str(PROBE_PATH),
            "--site-packages",
            str(site_packages),
            "--grammar-module",
            profile["grammar_module"],
            "--grammar-symbol",
            grammar_symbol,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {
            "status": "NOT_AVAILABLE",
            "reason": completed.stderr.strip() or "Tree-sitter ABI probe returned invalid JSON",
        }
    if completed.returncode != 0 and result.get("status") == "READY":
        return {"status": "NOT_AVAILABLE", "reason": completed.stderr.strip() or "Tree-sitter ABI probe failed"}
    return result


def _profile_fingerprint(profile: dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(profile, sort_keys=True).encode("utf-8")).hexdigest()


def _expected_marker(language: str, profile: dict[str, Any], specs: list[str], probe: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema": "code-reader-static-analysis-install/v3",
        "installer": "uv",
        "language": language,
        "profile_fingerprint": _profile_fingerprint(profile),
        "specs": specs,
        "abi": probe,
    }


def _ready_result(language: str, site_packages: Path, installed: bool, probe: dict[str, Any]) -> dict[str, Any]:
    return {
        "status": "READY",
        "language": language,
        "site_packages": str(site_packages),
        "installed": installed,
        "grammar_abi": probe.get("grammar_abi"),
        "runtime_abi": probe.get("runtime_abi"),
    }


def _ensure_profile(
    language: str, profile: dict[str, Any], cache_root: Path | None, *, built_in: bool = False
) -> dict[str, Any]:
    try:
        specs = dependency_specs_for_profile(profile, built_in=built_in)
    except ValueError as error:
        return {"status": "NOT_AVAILABLE", "language": language, "site_packages": None, "reason": str(error)}
    if not specs:
        return {"status": "READY", "language": language, "site_packages": None, "installed": False}

    root = cache_root or default_cache_root()
    site_packages = cache_site_packages(root, language, specs)
    marker = site_packages.parent / "installed.json"
    if marker.is_file():
        try:
            stored = json.loads(marker.read_text(encoding="utf-8"))
            probe = stored.get("abi")
            if stored == _expected_marker(language, profile, specs, probe) and _probe_is_compatible(probe, profile):
                return _ready_result(language, site_packages, False, probe)
        except (OSError, json.JSONDecodeError, TypeError):
            pass

    uv_command, uv_error = _uv_command()
    if uv_command is None:
        return {
            "status": "UV_UNAVAILABLE",
            "language": language,
            "site_packages": str(site_packages),
            "reason": uv_error,
        }

    site_packages.mkdir(parents=True, exist_ok=True)
    install_error = _install(site_packages, specs, uv_command)
    if install_error:
        return {"status": "UNAVAILABLE", "language": language, "site_packages": str(site_packages), "reason": install_error}
    probe = _probe_tree_sitter(site_packages, profile)
    if not _probe_is_compatible(probe, profile):
        return {
            "status": "NOT_AVAILABLE",
            "language": language,
            "site_packages": str(site_packages),
            "reason": _probe_reason(probe),
        }
    marker.write_text(
        json.dumps(_expected_marker(language, profile, specs, probe), ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return _ready_result(language, site_packages, True, probe)


def _probe_is_compatible(probe: Any, profile: dict[str, Any] | None = None) -> bool:
    if not isinstance(probe, dict) or probe.get("status") != "READY":
        return False
    runtime = probe.get("runtime_abi")
    grammar_abi = probe.get("grammar_abi")
    compatible = (
        isinstance(runtime, dict)
        and isinstance(runtime.get("minimum"), int)
        and isinstance(runtime.get("maximum"), int)
        and isinstance(grammar_abi, int)
        and abi_is_compatible(runtime["minimum"], runtime["maximum"], grammar_abi)
    )
    if not compatible or profile is None:
        return compatible
    configured = _runtime_family(profile)
    return (
        runtime["minimum"] <= configured["minimum_abi"]
        and runtime["maximum"] >= configured["maximum_abi"]
        and abi_is_compatible(configured["minimum_abi"], configured["maximum_abi"], grammar_abi)
    )


def _probe_reason(probe: Any) -> str:
    if isinstance(probe, dict) and probe.get("reason"):
        return f"Tree-sitter ABI probe failed: {probe['reason']}"
    if isinstance(probe, dict):
        runtime = probe.get("runtime_abi")
        grammar_abi = probe.get("grammar_abi")
        if isinstance(runtime, dict) and isinstance(grammar_abi, int):
            return (
                f"Tree-sitter ABI incompatibility: grammar ABI {grammar_abi} requires a loader "
                f"supporting it, but this loader supports {runtime.get('minimum')} through {runtime.get('maximum')}"
            )
    return "Tree-sitter ABI probe did not report a compatible runtime and grammar"


def ensure_profile(language: str, profile: dict[str, Any], cache_root: Path | None = None) -> dict[str, Any]:
    """Install and ABI-verify one explicitly approved user profile."""
    return _ensure_profile(language, profile, cache_root)


def ensure(language: str | None, cache_root: Path | None = None) -> dict[str, Any]:
    """Install and ABI-verify dependencies for a built-in or approved user profile."""
    profiles = static_analysis_registry.load_profiles(cache_root)
    profile = profiles.get(language or "")
    if not profile:
        return {
            "status": "PROVISION_REQUIRED",
            "reason": "no static-analysis profile is registered; provision an approved parser profile first",
            "site_packages": None,
        }
    return _ensure_profile(
        language or "unknown",
        profile,
        cache_root,
        built_in=(language or "") in static_analysis_registry.load_builtin_profiles(),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", help="Source path used to infer a profile")
    parser.add_argument("--language", help="Registered profile language")
    parser.add_argument("--cache-root", help="Override the user cache directory")
    args = parser.parse_args()
    cache_root = Path(args.cache_root).resolve() if args.cache_root else None
    language = args.language
    if language is None and args.path:
        suffix = Path(args.path).suffix.lower()
        for candidate, profile in static_analysis_registry.load_profiles(cache_root).items():
            if suffix in profile.get("extensions", []):
                language = candidate
                break
    result = ensure(language, cache_root)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "READY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
