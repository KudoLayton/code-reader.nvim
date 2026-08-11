#!/usr/bin/env python
"""Prepare the pinned Code Reader static-analysis dependencies for one language.

The helper installs only packages declared in the checked-in profile and lock.
It uses a user cache outside the explained project, so walkthrough generation never
adds dependency files to the user's repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import static_metrics


SCRIPT_DIR = Path(__file__).resolve().parent
LOCK_PATH = SCRIPT_DIR / "static_analysis_requirements.lock.json"


def default_cache_root() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        return Path(local_app_data) / "CodeReaderAuthoring" / "static-analysis"
    return Path.home() / ".cache" / "code-reader-authoring" / "static-analysis"


def dependency_specs(language: str | None) -> list[str]:
    profiles = static_metrics.load_profiles()
    profile = profiles.get(language or "")
    if not profile:
        return []
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    locked = {**lock.get("runtime_dependencies", {}), **lock.get("pinned_dependencies", {})}
    names = [item["name"] for item in profile.get("required_dependencies", [])]
    if names:
        names = [*locked.keys(), *names]
    specs: list[str] = []
    for name in names:
        version = locked.get(name)
        profile_version = next(
            (item["version"] for item in profile.get("required_dependencies", []) if item["name"] == name),
            None,
        )
        if version is None:
            version = profile_version
        elif profile_version is not None and profile_version != version:
            raise ValueError(f"profile dependency `{name}` does not match the pinned lock")
        if not version:
            raise ValueError(f"profile dependency `{name}` is missing from the pinned lock")
        specs.append(f"{name}=={version}")
    return specs


def cache_site_packages(cache_root: Path, specs: list[str]) -> Path:
    fingerprint = hashlib.sha256("\n".join(specs).encode("utf-8")).hexdigest()[:16]
    return cache_root / fingerprint / "site-packages"


def ensure(language: str | None, cache_root: Path | None = None) -> dict[str, Any]:
    """Install the registered pinned dependencies and return their import path."""
    profiles = static_metrics.load_profiles()
    profile = profiles.get(language or "")
    if not profile:
        return {"status": "NOT_AVAILABLE", "reason": "no registered static-analysis profile", "site_packages": None}
    specs = dependency_specs(language)
    if not specs:
        return {"status": "READY", "language": language, "site_packages": None, "installed": False}

    root = cache_root or default_cache_root()
    site_packages = cache_site_packages(root, specs)
    marker = site_packages.parent / "installed.json"
    expected = {"language": language, "specs": specs}
    if marker.is_file():
        try:
            if json.loads(marker.read_text(encoding="utf-8")) == expected:
                return {
                    "status": "READY",
                    "language": language,
                    "site_packages": str(site_packages),
                    "installed": False,
                }
        except json.JSONDecodeError:
            pass

    site_packages.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--no-input",
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
        return {
            "status": "UNAVAILABLE",
            "language": language,
            "site_packages": str(site_packages),
            "reason": completed.stderr.strip() or "pinned dependency installation failed",
        }
    marker.write_text(json.dumps(expected, sort_keys=True) + "\n", encoding="utf-8")
    return {"status": "READY", "language": language, "site_packages": str(site_packages), "installed": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", help="Source path used to infer the registered profile")
    parser.add_argument("--language", help="Registered profile language")
    parser.add_argument("--cache-root", help="Override the user cache directory")
    args = parser.parse_args()
    language = args.language or (static_metrics.language_for_path(args.path) if args.path else None)
    result = ensure(language, Path(args.cache_root).resolve() if args.cache_root else None)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "READY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
