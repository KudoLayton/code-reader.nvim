#!/usr/bin/env python
"""Resolve AST target-definition labels for a Source or reconstructed Diff side."""

from __future__ import annotations

import argparse
import json
import re
import sys

import bootstrap_static_analysis
import static_metrics


def parse_range(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"L?(\d+)(?:-L?(\d+))?", value)
    if not match:
        raise argparse.ArgumentTypeError("range must look like L12-L34")
    start_line = int(match.group(1))
    end_line = int(match.group(2) or match.group(1))
    if end_line < start_line:
        raise argparse.ArgumentTypeError("range end must not precede range start")
    return start_line, end_line


def resolve(text: str, path: str, start_line: int, end_line: int) -> dict:
    language = static_metrics.language_for_path(path)
    try:
        bootstrap = bootstrap_static_analysis.ensure(language)
    except OSError as error:
        return {
            "schema": "code-reader-target-definitions/v1",
            "path": path,
            "language": language,
            "status": static_metrics.NOT_AVAILABLE,
            "definitions": [],
            "reason": f"registered target-definition parser is unavailable: {error}",
        }
    if bootstrap.get("status") != "READY":
        return {
            "schema": "code-reader-target-definitions/v1",
            "path": path,
            "language": language,
            "status": bootstrap.get("status", static_metrics.NOT_AVAILABLE),
            "definitions": [],
            "reason": bootstrap.get("reason", "registered target-definition parser is unavailable"),
        }
    site_packages = bootstrap.get("site_packages")
    if site_packages and site_packages not in sys.path:
        sys.path.insert(0, site_packages)
    analysis = static_metrics.analyze_target_definitions(text, language, path)
    return {
        "schema": "code-reader-target-definitions/v1",
        "path": path,
        "language": language,
        "status": analysis["status"],
        "definitions": static_metrics.select_target_definitions_for_range(
            analysis, start_line, end_line
        ),
        **({"reason": analysis["reason"]} if analysis.get("reason") else {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", required=True, help="virtual source path used for language selection")
    parser.add_argument("--range", dest="source_range", required=True, type=parse_range, help="inclusive target range")
    args = parser.parse_args()
    start_line, end_line = args.source_range
    result = resolve(sys.stdin.read(), args.path, start_line, end_line)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
