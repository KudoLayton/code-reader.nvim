"""Read and write Code Reader static-analysis profiles outside explained projects."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
BUILTIN_PROFILE_PATH = SCRIPT_DIR / "static_analysis_profiles.json"
PARSER_CATALOG_PATH = SCRIPT_DIR / "static_analysis_parser_catalog.json"
USER_PROFILE_FILE = "profiles.json"
USER_PROFILE_SCHEMA = "code-reader-user-static-analysis-profiles/v1"


def default_cache_root() -> Path:
    override = os.environ.get("CODE_READER_STATIC_ANALYSIS_CACHE")
    if override:
        return Path(override)
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        return Path(local_app_data) / "CodeReaderAuthoring" / "static-analysis"
    return Path.home() / ".cache" / "code-reader-authoring" / "static-analysis"


def user_profile_path(cache_root: Path | None = None) -> Path:
    return (cache_root or default_cache_root()) / USER_PROFILE_FILE


def _read_profile_document(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"schema": USER_PROFILE_SCHEMA, "profiles": {}}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"schema": USER_PROFILE_SCHEMA, "profiles": {}}
    if document.get("schema") != USER_PROFILE_SCHEMA or not isinstance(document.get("profiles"), dict):
        return {"schema": USER_PROFILE_SCHEMA, "profiles": {}}
    return document


def load_builtin_profiles() -> dict[str, dict[str, Any]]:
    return json.loads(BUILTIN_PROFILE_PATH.read_text(encoding="utf-8"))["profiles"]


def load_parser_catalog() -> dict[str, Any]:
    """Return the checked-in Tree-sitter parser and ABI compatibility snapshot."""
    return json.loads(PARSER_CATALOG_PATH.read_text(encoding="utf-8"))


def load_profiles(cache_root: Path | None = None) -> dict[str, dict[str, Any]]:
    """Return built-in profiles plus non-conflicting approved user profiles."""
    profiles = load_builtin_profiles()
    user_profiles = _read_profile_document(user_profile_path(cache_root)).get("profiles", {})
    builtin_extensions = {
        extension
        for profile in profiles.values()
        for extension in profile.get("extensions", [])
    }
    for language, profile in user_profiles.items():
        if (
            not isinstance(language, str)
            or not isinstance(profile, dict)
            or language in profiles
            or builtin_extensions.intersection(profile.get("extensions", []))
        ):
            continue
        profiles[language] = profile
    return profiles


def save_user_profile(
    language: str, profile: dict[str, Any], cache_root: Path | None = None, *, replace: bool = False
) -> Path:
    """Atomically save an explicitly approved profile in the user cache."""
    path = user_profile_path(cache_root)
    document = _read_profile_document(path)
    profiles = document["profiles"]
    if language in profiles and not replace:
        raise ValueError(f"a user static-analysis profile already exists for `{language}`")
    path.parent.mkdir(parents=True, exist_ok=True)
    profiles[language] = profile
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False, suffix=".json"
    ) as temporary:
        json.dump(document, temporary, ensure_ascii=False, indent=2, sort_keys=True)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)
    return path
