#!/usr/bin/env python
"""Validate code-reader.nvim explanation markdown."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


FRONT_PAGE_MARKER = "<!-- code-reader: front-page -->"
SOURCE_RE = re.compile(r"([\w._\-/\\]+)#L(\d+)(?:-L?(\d+))?")
CURSOR_RE = re.compile(r"^\s*Cursor:\s*`?([\w._\-/\\]+)#L(\d+)`?\s*$")
DIFF_RE = re.compile(r"([\w._\-/\\]+)#([Hh]\d+)(?:@([A-Za-z]+):([^\s`\]]+))?")
STEP_LINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]")


SOURCE_DIRECTIVE_RE = re.compile(r"^\s*Source:\s*`?([\w._\-/\\]+)#L(\d+)(?:-L?(\d+))?`?\s*$")
DIFF_DIRECTIVE_RE = re.compile(r"^\s*Diff:\s*`?([\w._\-/\\]+)#([Hh]\d+)(?:@([A-Za-z]+):([^\s`\]]+))?`?\s*$")


@dataclass
class DiffHunk:
    path: str
    hunk_id: str
    old_start: int
    old_length: int
    new_start: int
    new_length: int
    old_lines: list[str] = field(default_factory=list)
    new_lines: list[str] = field(default_factory=list)
    old_blob: str | None = None
    new_blob: str | None = None


def split_lines(text: str) -> list[str]:
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def trim(value: str) -> str:
    return value.strip()


def parse_frontmatter(lines: list[str]) -> tuple[dict[str, str], int, list[str]]:
    errors: list[str] = []
    if not lines or trim(lines[0]) != "---":
        return {}, 0, ["missing frontmatter block"]

    frontmatter: dict[str, str] = {}
    index = 1
    while index < len(lines):
        line = lines[index]
        if trim(line) == "---":
            return frontmatter, index + 1, errors
        match = re.match(r"^\s*([\w_.-]+)\s*:\s*(.*?)\s*$", line)
        if match:
            frontmatter[match.group(1)] = parse_scalar(match.group(2))
        elif trim(line):
            errors.append(f"invalid frontmatter line {index + 1}: {line}")
        index += 1

    errors.append("frontmatter block is not closed")
    return frontmatter, index, errors


def parse_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def split_sections(lines: list[str], start_index: int) -> list[tuple[int, list[str]]]:
    sections: list[tuple[int, list[str]]] = []
    current: list[str] = []
    current_start = start_index + 1

    def flush() -> None:
        nonlocal current, current_start
        if any(trim(line) for line in current):
            sections.append((current_start, current))
        current = []

    for index in range(start_index, len(lines)):
        line = lines[index]
        if trim(line) == "---":
            flush()
            current_start = index + 2
        else:
            current.append(line)
    flush()
    return sections


def first_non_empty_index(lines: list[str]) -> int | None:
    for index, line in enumerate(lines):
        if trim(line):
            return index
    return None


def parse_heading(lines: list[str]) -> tuple[str, int] | None:
    for line in lines:
        match = re.match(r"^(#+)\s+(.+?)\s*$", line)
        if not match:
            continue
        text = re.sub(r"\s+#\s*$", "", match.group(2)).strip()
        id_match = re.match(r"^([0-9][0-9.]*)\s+(.+)$", text)
        if id_match:
            return id_match.group(1).rstrip("."), len(match.group(1))
        return "", len(match.group(1))
    return None


def heading_indexes(lines: list[str]) -> list[int]:
    return [index for index, line in enumerate(lines) if re.match(r"^(#+)\s+.+?\s*$", line)]


def is_numeric_heading(line: str) -> bool:
    match = re.match(r"^(#+)\s+(.+?)\s*$", line)
    if not match:
        return False
    text = re.sub(r"\s+#\s*$", "", match.group(2)).strip()
    return re.match(r"^[0-9][0-9.]*\s+", text) is not None


def directive_kind(line: str) -> str | None:
    if re.match(r"^\s*Source\s*:", line):
        return "source"
    if re.match(r"^\s*Diff\s*:", line):
        return "diff"
    if re.match(r"^\s*Cursor\s*:", line):
        return "cursor"
    return None


def metadata_preamble_indexes(lines: list[str]) -> set[int]:
    headings = heading_indexes(lines)
    if not headings:
        return set()
    indexes: set[int] = set()
    for index in range(headings[0] + 1, len(lines)):
        line = lines[index]
        if not trim(line):
            continue
        if directive_kind(line):
            indexes.add(index)
            continue
        break
    return indexes


def collect_directive_indexes(lines: list[str]) -> dict[str, list[int]]:
    indexes = {"source": [], "diff": [], "cursor": []}
    for index, line in enumerate(lines):
        kind = directive_kind(line)
        if kind:
            indexes[kind].append(index)
    return indexes


def validate_page_structure(
    section_start: int,
    lines: list[str],
    doc_type: str | None,
    is_front_page: bool,
) -> list[str]:
    errors: list[str] = []
    directives = collect_directive_indexes(lines)
    preamble = metadata_preamble_indexes(lines)
    headings = heading_indexes(lines)

    if is_front_page:
        if directives["source"] or directives["diff"]:
            errors.append(f"front page starting at line {section_start} must not contain Source or Diff references")
        if directives["cursor"]:
            errors.append(f"front page starting at line {section_start} must not contain Cursor directives")
        return errors

    for index in headings[1:]:
        if is_numeric_heading(lines[index]):
            errors.append(
                f"line {section_start + index}: numeric child headings must start a new --- page"
            )

    for kind, indexes in directives.items():
        for index in indexes:
            if index not in preamble:
                errors.append(f"line {section_start + index}: {kind.title()} directives are only allowed in the metadata preamble")

    if doc_type == "code-reader":
        if directives["diff"]:
            errors.append(f"section starting at line {section_start} has a Diff directive in a source document")
        if len(directives["source"]) != 1:
            errors.append(f"section starting at line {section_start} must contain exactly one Source directive")
        if any(index not in preamble for index in directives["source"]):
            errors.append(f"section starting at line {section_start} must place its Source directive in the metadata preamble")
        if len(directives["cursor"]) > 1:
            errors.append(f"section starting at line {section_start} has multiple Cursor directives")
        if directives["cursor"] and not directives["source"]:
            errors.append(f"section starting at line {section_start} has a Cursor directive but no Source directive")
    elif doc_type == "code-reader-diff":
        if directives["source"]:
            errors.append(f"section starting at line {section_start} has a Source directive in a diff document")
        if directives["cursor"]:
            errors.append(f"section starting at line {section_start}: Cursor is only valid for code-reader documents")
        if not directives["diff"]:
            errors.append(f"section starting at line {section_start} has no Diff directive")
        if any(index not in preamble for index in directives["diff"]):
            errors.append(f"section starting at line {section_start} must place Diff directives in the metadata preamble")

    return errors


def section_step_id(section_index: int, lines: list[str], is_front_page: bool) -> str:
    if is_front_page:
        return "front"
    heading = parse_heading(lines)
    if heading and heading[0]:
        return heading[0]
    return str(section_index)


def normalize_path(value: str) -> str:
    return value.replace("\\", "/")


def strip_diff_prefix(value: str | None) -> str | None:
    if not value or value == "/dev/null":
        return None
    value = value.split()[0]
    if value.startswith("a/") or value.startswith("b/"):
        return value[2:]
    return value


def parse_unified_diff_hunks(text: str) -> dict[str, list[DiffHunk]]:
    files: dict[str, list[DiffHunk]] = {}
    old_path: str | None = None
    new_path: str | None = None
    current_path: str | None = None
    old_blob: str | None = None
    new_blob: str | None = None
    hunk_count = 0
    current_hunk: DiffHunk | None = None

    for line in split_lines(text):
        git_match = re.match(r"^diff --git a/(.+) b/(.+)$", line)
        if git_match:
            old_path = git_match.group(1)
            new_path = git_match.group(2)
            current_path = None
            old_blob = None
            new_blob = None
            hunk_count = 0
            current_hunk = None
            continue

        index_match = re.match(r"^index ([0-9a-f]+)\.\.([0-9a-f]+)(?: \d+)?$", line)
        if index_match:
            old_blob, new_blob = index_match.groups()
            continue

        old_match = re.match(r"^---\s+(.+)$", line)
        if old_match:
            old_path = strip_diff_prefix(old_match.group(1))
            current_path = None
            hunk_count = 0
            current_hunk = None
            continue

        new_match = re.match(r"^\+\+\+\s+(.+)$", line)
        if new_match:
            new_path = strip_diff_prefix(new_match.group(1))
            current_path = normalize_path(new_path or old_path or "")
            if current_path:
                files.setdefault(current_path, [])
            continue

        hunk_match = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if current_path and hunk_match:
            old_start, old_length, new_start, new_length = hunk_match.groups()
            hunk_count += 1
            current_hunk = DiffHunk(
                path=current_path,
                hunk_id=f"H{hunk_count}",
                old_start=int(old_start),
                old_length=int(old_length or 1),
                new_start=int(new_start),
                new_length=int(new_length or 1),
                old_blob=old_blob,
                new_blob=new_blob,
            )
            files[current_path].append(current_hunk)
            continue

        if not current_hunk or line == "\\ No newline at end of file":
            continue
        if line.startswith(" "):
            current_hunk.old_lines.append(line[1:])
            current_hunk.new_lines.append(line[1:])
        elif line.startswith("-"):
            current_hunk.old_lines.append(line[1:])
        elif line.startswith("+"):
            current_hunk.new_lines.append(line[1:])

    return files


def parse_unified_diff(text: str) -> dict[str, set[str]]:
    return {path: {hunk.hunk_id for hunk in hunks} for path, hunks in parse_unified_diff_hunks(text).items()}


def validate_source_refs(project_root: Path, section_start: int, lines: list[str]) -> list[str]:
    errors: list[str] = []
    for line_index, line in enumerate(lines):
        if not re.match(r"^\s*Source\s*:", line):
            continue
        match = SOURCE_DIRECTIVE_RE.match(line)
        if not match:
            errors.append(f"line {section_start + line_index}: invalid Source directive")
            continue
        rel_path = normalize_path(match.group(1))
        start_line = int(match.group(2))
        end_line = int(match.group(3) or match.group(2))
        source_path = project_root / rel_path
        if start_line < 1 or end_line < start_line:
            errors.append(f"line {section_start + line_index}: invalid source range {rel_path}#L{start_line}-L{end_line}")
            continue
        if not source_path.is_file():
            errors.append(f"line {section_start + line_index}: source file does not exist: {rel_path}")
            continue
        line_count = len(source_path.read_text(encoding="utf-8").splitlines())
        if end_line > line_count:
            errors.append(
                f"line {section_start + line_index}: source range exceeds file length: {rel_path}#L{start_line}-L{end_line}"
            )
    return errors


def collect_source_refs(lines: list[str]) -> list[str]:
    refs: list[str] = []
    for line in lines:
        match = SOURCE_DIRECTIVE_RE.match(line)
        if match:
            refs.append(match.group(0))
    return refs


def source_ref_data(lines: list[str]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for line_index, line in enumerate(lines):
        match = SOURCE_DIRECTIVE_RE.match(line)
        if not match:
            continue
        refs.append(
            {
                "line": line_index + 1,
                "path": normalize_path(match.group(1)),
                "start_line": int(match.group(2)),
                "end_line": int(match.group(3) or match.group(2)),
            }
        )
    return refs


def collect_cursor_refs(lines: list[str]) -> list[tuple[str, int] | None]:
    refs: list[tuple[str, int] | None] = []
    for line in lines:
        if re.match(r"^\s*Cursor\s*:", line):
            match = CURSOR_RE.match(line)
            if not match:
                refs.append(None)
            else:
                refs.append((normalize_path(match.group(1)), int(match.group(2))))
    return refs


def validate_cursors(project_root: Path, section_start: int, lines: list[str]) -> list[str]:
    errors: list[str] = []
    cursors = collect_cursor_refs(lines)
    if len(cursors) > 1:
        errors.append(f"section starting at line {section_start} has multiple Cursor directives")
        return errors
    if not cursors:
        return errors
    cursor = cursors[0]
    if cursor is None:
        errors.append(f"section starting at line {section_start} has an invalid Cursor directive")
        return errors

    source_refs = collect_source_refs(lines)
    if not source_refs:
        errors.append(f"section starting at line {section_start} has a Cursor directive but no source reference")
        return errors

    source_match = SOURCE_RE.search(source_refs[0])
    if not source_match:
        return errors
    source_path = normalize_path(source_match.group(1))
    start_line = int(source_match.group(2))
    end_line = int(source_match.group(3) or source_match.group(2))
    cursor_path, cursor_line = cursor
    if cursor_path != source_path:
        errors.append(f"section starting at line {section_start}: Cursor path must match the first Source reference")
    elif cursor_line < start_line or cursor_line > end_line:
        errors.append(f"section starting at line {section_start}: Cursor line must be inside the first Source range")
    return errors


def normalize_diff_side(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.lower()
    if value == "a":
        return "old"
    if value == "b":
        return "new"
    if value in {"old", "new"}:
        return value
    return None


def parse_diff_bound(value: str) -> tuple[str, int] | None:
    if value.startswith("(") and value.endswith(")"):
        value = value[1:-1]
    if not re.match(r"^[+-]?\d+$", value):
        return None
    mode = "relative" if value.startswith(("+", "-")) else "absolute"
    return mode, int(value)


def parse_diff_range(value: str) -> bool:
    if not value.startswith("L"):
        return False
    body = value[1:]
    start_text: str | None = None
    end_text: str | None = None

    if body.startswith("("):
        close = body.find(")")
        if close >= 0 and body[close + 1 : close + 3] == "-L":
            start_text = body[: close + 1]
            end_text = body[close + 3 :]
    if start_text is None:
        match = re.match(r"^([+-]\d+)-L(.+)$", body)
        if match:
            start_text, end_text = match.group(1), match.group(2)
    if start_text is None:
        match = re.match(r"^(\d+)-L(.+)$", body)
        if match:
            start_text, end_text = match.group(1), match.group(2)
    if start_text is None:
        bound = parse_diff_bound(body)
        if not bound:
            return False
        return bound[0] == "relative" or bound[1] >= 1

    start = parse_diff_bound(start_text)
    end = parse_diff_bound(end_text or "")
    if not (start and end):
        return False
    if start[0] == "absolute" and start[1] < 1:
        return False
    if end[0] == "absolute" and end[1] < 1:
        return False
    if start[0] == "absolute" and end[0] == "absolute" and end[1] < start[1]:
        return False
    return True


def validate_diff_modifier(side: str | None, modifier: str | None) -> bool:
    if side is None and modifier is None:
        return True
    if not normalize_diff_side(side):
        return False
    if modifier is None:
        return False
    padding_match = re.match(r"^(?:padding|pad)=(\d+)$", modifier)
    if padding_match:
        return int(padding_match.group(1)) >= 0
    return parse_diff_range(modifier)


def collect_diff_refs(lines: list[str]) -> list[tuple[str, str, bool]]:
    refs: list[tuple[str, str, bool]] = []
    for line in lines:
        match = DIFF_DIRECTIVE_RE.match(line)
        if match:
            refs.append(
                (
                    normalize_path(match.group(1)),
                    match.group(2).upper(),
                    validate_diff_modifier(match.group(3), match.group(4)),
                )
            )
    return refs


def diff_ref_data(lines: list[str]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for line_index, line in enumerate(lines):
        match = DIFF_DIRECTIVE_RE.match(line)
        if not match:
            continue
        refs.append(
            {
                "line": line_index + 1,
                "path": normalize_path(match.group(1)),
                "hunk_id": match.group(2).upper(),
                "side": normalize_diff_side(match.group(3)),
                "modifier": match.group(4),
                "valid_modifier": validate_diff_modifier(match.group(3), match.group(4)),
            }
        )
    return refs


def git_blob_text(project_root: Path, blob: str | None) -> str | None:
    if not blob:
        return None
    result = subprocess.run(
        ["git", "-C", str(project_root), "cat-file", "-p", blob],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout if result.returncode == 0 else None


def hunk_side_range(hunk: DiffHunk, side: str, modifier: str | None) -> tuple[int, int] | None:
    start = hunk.old_start if side == "old" else hunk.new_start
    length = hunk.old_length if side == "old" else hunk.new_length
    if length == 0:
        return None
    end = start + length - 1
    if not modifier:
        return start, end
    padding = re.match(r"^(?:padding|pad)=(\d+)$", modifier)
    if padding:
        value = int(padding.group(1))
        return max(1, start - value), end + value
    if not modifier.startswith("L"):
        return None
    body = modifier[1:]
    split = re.match(r"^(.+)-L(.+)$", body)
    bounds = [body] if not split else [split.group(1), split.group(2)]
    values: list[int] = []
    for bound in bounds:
        parsed = parse_diff_bound(bound)
        if not parsed:
            return None
        mode, value = parsed
        values.append(start + value if mode == "relative" else value)
    if len(values) == 1:
        return values[0], values[0]
    if values[0] < 1 or values[1] < values[0]:
        return None
    return values[0], values[1]


def hunk_lines_match(source_text: str, hunk: DiffHunk, side: str) -> bool:
    expected = hunk.old_lines if side == "old" else hunk.new_lines
    start = hunk.old_start if side == "old" else hunk.new_start
    if not expected:
        return True
    source_lines = split_lines(source_text)
    return source_lines[start - 1 : start - 1 + len(expected)] == expected


def resolve_hunk_side(project_root: Path, hunk: DiffHunk, side: str, modifier: str | None) -> dict[str, Any]:
    blob = hunk.old_blob if side == "old" else hunk.new_blob
    candidates: list[tuple[str, str | None]] = [("git_blob", git_blob_text(project_root, blob))]
    if side == "new":
        worktree_path = project_root / hunk.path
        candidates.append(("worktree", worktree_path.read_text(encoding="utf-8") if worktree_path.is_file() else None))

    requested_range = hunk_side_range(hunk, side, modifier)
    for source_kind, text in candidates:
        if text is None or not hunk_lines_match(text, hunk, side):
            continue
        if not requested_range:
            return {"side": side, "status": "unavailable", "reason": "hunk side has no source lines"}
        start_line, end_line = requested_range
        if start_line < 1 or end_line > len(split_lines(text)):
            return {"side": side, "status": "unavailable", "reason": "focused range is outside resolved source"}
        return {
            "side": side,
            "status": "resolved",
            "path": hunk.path,
            "start_line": start_line,
            "end_line": end_line,
            "source_kind": source_kind,
            "source_text": text,
        }
    return {"side": side, "status": "hunk_fallback", "reason": "matching source revision is unavailable"}


def resolve_diff_reference(
    project_root: Path, hunk: DiffHunk, side: str | None, modifier: str | None
) -> list[dict[str, Any]]:
    sides = [side] if side else ["old", "new"]
    return [resolve_hunk_side(project_root, hunk, value, modifier) for value in sides]


def static_verdict(metrics: dict[str, Any]) -> str:
    if metrics.get("status") != "SUPPORTED":
        return "NOT_AVAILABLE"
    complexity = metrics.get("cyclomatic_complexity")
    bindings = metrics.get("peak_live_bindings")
    if complexity is None or bindings is None:
        return "NOT_AVAILABLE"
    if complexity >= 12 or bindings >= 9:
        return "SPLIT_REQUIRED"
    if complexity >= 11 and bindings >= 8:
        return "SPLIT_REQUIRED"
    return "REVIEW_REQUIRED"


def analyze_source_scope(path: str, text: str, start_line: int, end_line: int) -> dict[str, Any]:
    try:
        import static_metrics
        import bootstrap_static_analysis
    except ImportError as error:
        return {
            "status": "NOT_AVAILABLE",
            "reason": f"static metrics module is unavailable: {error}",
            "analysis_region": None,
            "evidence": [],
        }

    language = static_metrics.language_for_path(path)
    bootstrap = bootstrap_static_analysis.ensure(language)
    if bootstrap.get("status") != "READY":
        return {
            "status": "NOT_AVAILABLE",
            "reason": bootstrap.get("reason", "registered static-analysis dependencies are unavailable"),
            "analysis_region": None,
            "evidence": [],
        }
    site_packages = bootstrap.get("site_packages")
    if site_packages and site_packages not in sys.path:
        sys.path.insert(0, site_packages)
    result = static_metrics.analyze_text(text, language, path)
    if result.get("status") != "SUPPORTED":
        return {
            "status": result.get("status", "NOT_AVAILABLE"),
            "reason": result.get("reason", "language profile is unavailable"),
            "analysis_region": None,
            "evidence": [],
        }
    definition = static_metrics.select_definition_for_range(result, start_line, end_line)
    if not definition:
        return {
            "status": "NOT_AVAILABLE",
            "reason": "source range is not fully contained in a single supported definition",
            "analysis_region": None,
            "evidence": [],
        }
    definition_metrics = definition.get("metrics", {})
    return {
        "status": "SUPPORTED",
        "cyclomatic_complexity": definition_metrics.get("cyclomatic_complexity"),
        "peak_live_bindings": definition_metrics.get("peak_live_bindings"),
        "analysis_region": {
            "kind": definition.get("kind"),
            "name": definition.get("name"),
            "path": path,
            "start_line": definition.get("start_line"),
            "end_line": definition.get("end_line"),
        },
        "evidence": definition_metrics.get("evidence", []),
    }


def inventory_metrics_error(section_start: int, metrics: dict[str, Any]) -> str | None:
    if metrics.get("status") != "SUPPORTED":
        return None
    verdict = static_verdict(metrics)
    if verdict != "SPLIT_REQUIRED":
        return None
    complexity = metrics.get("cyclomatic_complexity")
    bindings = metrics.get("peak_live_bindings")
    return (
        f"section starting at line {section_start}: SPLIT_REQUIRED "
        f"(V(G)={complexity}, peak live bindings={bindings})"
    )


def heading_data(lines: list[str]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index in heading_indexes(lines):
        match = re.match(r"^(#+)\s+(.+?)\s*$", lines[index])
        if not match:
            continue
        text = re.sub(r"\s+#\s*$", "", match.group(2)).strip()
        result.append({"line": index + 1, "depth": len(match.group(1)), "text": text})
    return result


def page_static_metrics_from_diff(resolutions: list[dict[str, Any]]) -> tuple[dict[str, Any], list[str]]:
    analyzed: list[dict[str, Any]] = []
    region_keys: set[tuple[Any, ...]] = set()
    for resolution in resolutions:
        source_text = resolution.pop("source_text", None)
        if resolution.get("status") != "resolved" or source_text is None:
            continue
        metrics = analyze_source_scope(
            resolution["path"], source_text, resolution["start_line"], resolution["end_line"]
        )
        resolution["static_metrics"] = metrics
        if metrics.get("status") == "SUPPORTED":
            analyzed.append(metrics)
            region = metrics.get("analysis_region") or {}
            region_keys.add((region.get("path"), region.get("kind"), region.get("name")))

    if not analyzed:
        reason = "no diff side could be statically analyzed"
        return {"status": "NOT_AVAILABLE", "reason": reason, "analysis_region": None, "evidence": []}, []

    highest_complexity = max(analyzed, key=lambda item: item["cyclomatic_complexity"])
    highest_bindings = max(analyzed, key=lambda item: item["peak_live_bindings"])
    metrics = {
        "status": "SUPPORTED",
        "cyclomatic_complexity": highest_complexity["cyclomatic_complexity"],
        "peak_live_bindings": highest_bindings["peak_live_bindings"],
        "analysis_region": highest_complexity.get("analysis_region"),
        "evidence": highest_complexity.get("evidence", []) + highest_bindings.get("evidence", []),
    }
    errors = []
    if len(region_keys) > 1:
        errors.append("resolved Diff references span multiple definitions and must be split")
    return metrics, errors


def build_inventory(project_root: Path, markdown_path: Path, allow_partial_diff: bool) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    text = markdown_path.read_text(encoding="utf-8")
    lines = split_lines(text)
    frontmatter, start_index, frontmatter_errors = parse_frontmatter(lines)
    errors.extend(frontmatter_errors)
    inventory: dict[str, Any] = {
        "schema": "code-reader-page-inventory/v1",
        "document": str(markdown_path),
        "document_type": frontmatter.get("type"),
        "pages": [],
    }

    doc_type = frontmatter.get("type")
    if doc_type not in {"code-reader", "code-reader-diff"}:
        errors.append("frontmatter field `type` must be `code-reader` or `code-reader-diff`")
    if frontmatter.get("version") != "1":
        errors.append("frontmatter field `version` must be `1`")

    sections = split_sections(lines, start_index)
    if not sections:
        errors.append("document has no sections")
        return errors, inventory

    first_start, first_lines = sections[0]
    marker_index = first_non_empty_index(first_lines)
    if marker_index is None or trim(first_lines[marker_index]) != FRONT_PAGE_MARKER:
        errors.append("first section must start with the code-reader front page marker")

    step_ids: set[str] = set()
    non_front_sections: list[tuple[int, list[str], dict[str, Any]]] = []
    for index, (section_start, section_lines) in enumerate(sections, start=1):
        is_front_page = index == 1
        heading = parse_heading(section_lines)
        if not heading:
            errors.append(f"section starting at line {section_start} is missing a markdown heading")
        step_id = section_step_id(index, section_lines, is_front_page)
        if step_id in step_ids:
            errors.append(f"duplicate step id `{step_id}`")
        step_ids.add(step_id)
        errors.extend(validate_page_structure(section_start, section_lines, doc_type, is_front_page))
        page = {
            "id": step_id,
            "section_start_line": section_start,
            "heading": heading_data(section_lines)[0] if heading_data(section_lines) else None,
            "child_headings": heading_data(section_lines)[1:],
            "source_refs": source_ref_data(section_lines),
            "diff_refs": diff_ref_data(section_lines),
            "static_metrics": {"status": "NOT_AVAILABLE", "analysis_region": None, "evidence": []},
            "static_verdict": "NOT_AVAILABLE",
        }
        if not is_front_page:
            inventory["pages"].append(page)
            non_front_sections.append((section_start, section_lines, page))

    for section_start, section_lines in sections:
        for line in section_lines:
            for match in STEP_LINK_RE.finditer(line):
                target = match.group(1).strip()
                if target not in step_ids:
                    errors.append(f"line {section_start}: unknown step link target `{target}`")

    if doc_type == "code-reader":
        for section_start, section_lines, page in non_front_sections:
            errors.extend(validate_source_refs(project_root, section_start, section_lines))
            errors.extend(validate_cursors(project_root, section_start, section_lines))
            if len(page["source_refs"]) != 1:
                continue
            ref = page["source_refs"][0]
            source_path = project_root / ref["path"]
            if not source_path.is_file():
                continue
            metrics = analyze_source_scope(
                ref["path"], source_path.read_text(encoding="utf-8"), ref["start_line"], ref["end_line"]
            )
            page["static_metrics"] = metrics
            page["static_verdict"] = static_verdict(metrics)
            metric_error = inventory_metrics_error(section_start, metrics)
            if metric_error:
                errors.append(metric_error)

    if doc_type == "code-reader-diff":
        diff_value = frontmatter.get("diff")
        diff_hunks: dict[str, list[DiffHunk]] = {}
        if not diff_value:
            errors.append("diff document must include frontmatter field `diff`")
        else:
            diff_path = (markdown_path.parent / diff_value).resolve()
            if not diff_path.is_file():
                errors.append(f"diff file does not exist: {diff_value}")
            else:
                diff_hunks = parse_unified_diff_hunks(diff_path.read_text(encoding="utf-8"))

        hunk_lookup = {
            (path, hunk.hunk_id): hunk
            for path, hunks in diff_hunks.items()
            for hunk in hunks
        }
        explained: set[tuple[str, str]] = set()
        for section_start, _section_lines, page in non_front_sections:
            resolutions: list[dict[str, Any]] = []
            for ref in page["diff_refs"]:
                if not ref["valid_modifier"]:
                    errors.append(f"line {section_start + ref['line'] - 1}: invalid diff range modifier `{ref['path']}#{ref['hunk_id']}`")
                    continue
                hunk = hunk_lookup.get((ref["path"], ref["hunk_id"]))
                if not hunk:
                    if ref["path"] not in diff_hunks:
                        errors.append(f"line {section_start}: diff file does not contain path `{ref['path']}`")
                    else:
                        errors.append(f"line {section_start}: diff file does not contain hunk `{ref['path']}#{ref['hunk_id']}`")
                    continue
                explained.add((ref["path"], ref["hunk_id"]))
                resolutions.extend(resolve_diff_reference(project_root, hunk, ref["side"], ref["modifier"]))
            page["diff_resolutions"] = resolutions
            metrics, diff_errors = page_static_metrics_from_diff(resolutions)
            page["static_metrics"] = metrics
            page["static_verdict"] = static_verdict(metrics)
            errors.extend(f"section starting at line {section_start}: SPLIT_REQUIRED ({error})" for error in diff_errors)
            metric_error = inventory_metrics_error(section_start, metrics)
            if metric_error:
                errors.append(metric_error)

        if diff_hunks and not allow_partial_diff:
            for path, hunks in sorted(diff_hunks.items()):
                for hunk in hunks:
                    if (path, hunk.hunk_id) not in explained:
                        errors.append(f"missing explanation for diff hunk `{path}#{hunk.hunk_id}`")

    return errors, inventory


def validate_doc(project_root: Path, markdown_path: Path, allow_partial_diff: bool) -> list[str]:
    errors, _inventory = build_inventory(project_root, markdown_path, allow_partial_diff)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_file")
    parser.add_argument("--project-root", default=".", help="Project root used to resolve source paths")
    parser.add_argument("--allow-partial-diff", action="store_true", help="Allow diff docs that do not cover every hunk")
    parser.add_argument("--emit-page-inventory", help="Write the deterministic page inventory JSON to this path")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    markdown_path = Path(args.markdown_file).resolve()
    errors, inventory = build_inventory(project_root, markdown_path, args.allow_partial_diff)
    if args.emit_page_inventory:
        output_path = Path(args.emit_page_inventory).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"ok: {markdown_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
