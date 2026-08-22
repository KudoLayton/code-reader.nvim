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
EVIDENCE_LINK_RE = re.compile(r"\[([^\]]+)\]\(code-reader://evidence/(\d+)\)")
SKETCH_PURPOSES = {"execution-map", "handoff-map", "state-map", "structure-map"}


SOURCE_DIRECTIVE_RE = re.compile(r"^\s*Source:\s*`?([\w._\-/\\]+)#L(\d+)(?:-L?(\d+))?`?\s*$")
DIFF_DIRECTIVE_RE = re.compile(r"^\s*Diff:\s*`?([\w._\-/\\]+)#([Hh]\d+)(?:@([A-Za-z]+):([^\s`\]]+))?`?\s*$")
TARGET_DIRECTIVE_RE = re.compile(r"^\s*Target:\s*(function|type)\s+(\S(?:.*\S)?)\s*$", re.IGNORECASE)


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


def parse_yaml_scalar(value: str) -> Any:
    scalar = parse_scalar(value)
    if scalar == "true":
        return True
    if scalar == "false":
        return False
    if re.fullmatch(r"-?\d+(?:\.\d+)?", scalar):
        return int(scalar) if "." not in scalar else float(scalar)
    return scalar


def parse_restricted_yaml(lines: list[tuple[int, str]]) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    tokens: list[tuple[int, int, str]] = []
    for line_number, line in lines:
        if not trim(line):
            continue
        spaces = len(line) - len(line.lstrip(" "))
        if spaces != len(line) - len(line.lstrip()):
            errors.append(f"line {line_number}: YAML indentation must use spaces")
            continue
        if spaces % 2:
            errors.append(f"line {line_number}: YAML indentation must use multiples of two spaces")
            continue
        tokens.append((spaces // 2, line_number, line.strip()))
    if errors or not tokens:
        return {}, errors

    def parse_block(position: int, indent: int) -> tuple[Any, int]:
        is_list = tokens[position][2].startswith("- ")
        result: Any = [] if is_list else {}
        while position < len(tokens):
            token_indent, line_number, text = tokens[position]
            if token_indent != indent or text.startswith("- ") != is_list:
                break
            if is_list:
                value = text[2:].strip()
                position += 1
                match = re.fullmatch(r"([\w-]+):\s*(.*?)\s*", value)
                if not match:
                    result.append(parse_yaml_scalar(value))
                    continue
                item: dict[str, Any] = {}
                key, scalar = match.groups()
                if scalar:
                    item[key] = parse_yaml_scalar(scalar)
                elif position < len(tokens) and tokens[position][0] > indent:
                    item[key], position = parse_block(position, tokens[position][0])
                else:
                    item[key] = {}
                if position < len(tokens) and tokens[position][0] > indent:
                    continuation, position = parse_block(position, tokens[position][0])
                    if not isinstance(continuation, dict):
                        errors.append(f"line {line_number}: list continuation must be a mapping")
                    else:
                        item.update(continuation)
                result.append(item)
                continue
            match = re.fullmatch(r"([\w-]+):\s*(.*?)\s*", text)
            if not match:
                errors.append(f"line {line_number}: invalid YAML mapping")
                position += 1
                continue
            key, scalar = match.groups()
            position += 1
            if scalar:
                result[key] = parse_yaml_scalar(scalar)
            elif position < len(tokens) and tokens[position][0] > indent:
                result[key], position = parse_block(position, tokens[position][0])
            else:
                result[key] = {}
        return result, position

    result, position = parse_block(0, tokens[0][0])
    if position != len(tokens):
        errors.append(f"line {tokens[position][1]}: unexpected YAML token")
    return result if isinstance(result, dict) else {}, errors


def split_v2_metadata(section_start: int, lines: list[str]) -> tuple[dict[str, Any], list[str], list[str]]:
    errors: list[str] = []
    start = next((index for index, line in enumerate(lines) if trim(line) == "```code-reader"), None)
    if start is None:
        return {}, lines, [f"section starting at line {section_start} is missing a code-reader metadata fence"]
    end = next((index for index in range(start + 1, len(lines)) if trim(lines[index]) == "```"), None)
    if end is None:
        return {}, lines, [f"section starting at line {section_start}: code-reader metadata fence is not closed"]
    metadata, yaml_errors = parse_restricted_yaml(
        [(section_start + index, lines[index]) for index in range(start + 1, end)]
    )
    errors.extend(yaml_errors)
    content = [line for index, line in enumerate(lines) if index < start or index > end]
    return metadata, content, errors


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
    if re.match(r"^\s*Target\s*:", line):
        return "target"
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
    indexes = {"source": [], "diff": [], "cursor": [], "target": []}
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
        if directives["target"]:
            errors.append(f"front page starting at line {section_start} must not contain Target directives")
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

    if len(directives["target"]) > 1:
        errors.append(f"section starting at line {section_start} has multiple Target directives")
    for index in directives["target"]:
        if not TARGET_DIRECTIVE_RE.match(lines[index]):
            errors.append(f"line {section_start + index}: Target must be `function <name>` or `type <name>`")

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
        if len(directives["diff"]) != 1:
            errors.append(f"section starting at line {section_start} must contain exactly one Diff directive")
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
            "reason_code": "ANALYZER_UNAVAILABLE",
            "fallback_required": True,
            "fallback_scope": {"path": path, "start_line": start_line, "end_line": end_line},
            "analysis_region": None,
            "evidence": [],
        }

    language = static_metrics.language_for_path(path)
    bootstrap = bootstrap_static_analysis.ensure(language)
    if bootstrap.get("status") != "READY":
        return {
            "status": bootstrap.get("status", "NOT_AVAILABLE"),
            "reason": bootstrap.get("reason", "registered static-analysis dependencies are unavailable"),
            "reason_code": "ANALYZER_UNAVAILABLE",
            "fallback_required": True,
            "fallback_scope": {"path": path, "start_line": start_line, "end_line": end_line},
            "analysis_region": None,
            "evidence": [],
        }
    site_packages = bootstrap.get("site_packages")
    if site_packages and site_packages not in sys.path:
        sys.path.insert(0, site_packages)
    result = static_metrics.analyze_range_text(text, language, path, start_line, end_line)
    if result.get("status") != "SUPPORTED":
        return {
            "status": result.get("status", "NOT_AVAILABLE"),
            "reason": result.get("reason", "language profile is unavailable"),
            "reason_code": result.get("reason_code"),
            "fallback_required": True,
            "fallback_scope": result.get("selection"),
            "analysis_region": None,
            "evidence": [],
        }
    range_metrics = result.get("metrics", {})
    return {
        "status": "SUPPORTED",
        "cyclomatic_complexity": range_metrics.get("cyclomatic_complexity"),
        "peak_live_bindings": range_metrics.get("peak_live_bindings"),
        "fallback_required": False,
        "analysis_region": result.get("analysis_region"),
        "evidence": range_metrics.get("evidence", []),
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
    fallback_reasons: list[dict[str, Any]] = []
    for resolution in resolutions:
        source_text = resolution.pop("source_text", None)
        if resolution.get("status") != "resolved" or source_text is None:
            fallback_reasons.append(
                {
                    "side": resolution.get("side"),
                    "status": resolution.get("status"),
                    "path": resolution.get("path"),
                    "start_line": resolution.get("start_line"),
                    "end_line": resolution.get("end_line"),
                    "reason": resolution.get("reason", "Diff source could not be resolved"),
                }
            )
            continue
        metrics = analyze_source_scope(
            resolution["path"], source_text, resolution["start_line"], resolution["end_line"]
        )
        resolution["static_metrics"] = metrics
        if metrics.get("status") == "SUPPORTED":
            analyzed.append(metrics)
            region = metrics.get("analysis_region") or {}
            owner = region.get("definition") or region
            region_keys.add((owner.get("path", region.get("path")), owner.get("id"), owner.get("name")))
        else:
            fallback_reasons.append(
                {
                    "side": resolution.get("side"),
                    "status": metrics.get("status"),
                    "scope": metrics.get("fallback_scope"),
                    "reason_code": metrics.get("reason_code"),
                    "reason": metrics.get("reason"),
                }
            )

    if not analyzed:
        reason = "no diff side could be statically analyzed"
        return {
            "status": "NOT_AVAILABLE",
            "reason": reason,
            "fallback_required": True,
            "fallback_reasons": fallback_reasons,
            "analysis_region": None,
            "evidence": [],
        }, []

    highest_complexity = max(analyzed, key=lambda item: item["cyclomatic_complexity"])
    highest_bindings = max(analyzed, key=lambda item: item["peak_live_bindings"])
    metrics = {
        "status": "SUPPORTED",
        "cyclomatic_complexity": highest_complexity["cyclomatic_complexity"],
        "peak_live_bindings": highest_bindings["peak_live_bindings"],
        "analysis_region": highest_complexity.get("analysis_region"),
        "evidence": highest_complexity.get("evidence", []) + highest_bindings.get("evidence", []),
        "fallback_required": bool(fallback_reasons),
        "fallback_reasons": fallback_reasons,
    }
    errors = []
    if len(region_keys) > 1:
        errors.append("resolved Diff references span multiple definitions and must be split")
    return metrics, errors


def v2_required_model_errors(section_start: int, metadata: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    kind = metadata.get("kind")
    if kind not in {"overview", "stage", "model"}:
        errors.append(f"section starting at line {section_start} must set kind to overview, stage, or model")
    if not metadata.get("id"):
        errors.append(f"section starting at line {section_start} must set metadata id")
    if kind in {"overview", "stage"} and not metadata.get("question"):
        errors.append(f"section starting at line {section_start} must set question")
    if kind == "stage" and not metadata.get("trigger"):
        errors.append(f"section starting at line {section_start} must set trigger")
    for model_name in ("state", "responsibility"):
        model = metadata.get(model_name)
        if not isinstance(model, dict) or model.get("status") not in {"applicable", "not_applicable"}:
            errors.append(f"section starting at line {section_start} must declare {model_name}.status")
        elif model["status"] == "not_applicable" and not model.get("reason"):
            errors.append(f"section starting at line {section_start} must explain {model_name}.not_applicable")
    if kind == "stage":
        failure = metadata.get("failure")
        if not isinstance(failure, dict) or failure.get("status") not in {"applicable", "not_applicable"}:
            errors.append(f"section starting at line {section_start} must declare failure.status")
        elif failure["status"] == "not_applicable" and not failure.get("reason"):
            errors.append(f"section starting at line {section_start} must explain failure.not_applicable")
    return errors


def v2_evidence_errors(
    project_root: Path,
    markdown_path: Path,
    section_start: int,
    metadata: dict[str, Any],
    content: list[str],
    diff_hunks: dict[str, list[DiffHunk]],
) -> tuple[list[str], list[dict[str, Any]], set[tuple[str, str]]]:
    errors: list[str] = []
    inventory: list[dict[str, Any]] = []
    explained_hunks: set[tuple[str, str]] = set()
    entries = metadata.get("evidence", [])
    if metadata.get("kind") == "stage" and not isinstance(entries, list):
        return [f"section starting at line {section_start} must declare an evidence list"], inventory, explained_hunks
    if not isinstance(entries, list):
        entries = []
    ids: set[int] = set()
    links = {int(match.group(2)) for line in content for match in EVIDENCE_LINK_RE.finditer(line)}
    for item in entries:
        if not isinstance(item, dict):
            errors.append(f"section starting at line {section_start} has a non-mapping evidence entry")
            continue
        identifier = item.get("id")
        if not isinstance(identifier, int) or identifier < 1:
            errors.append(f"section starting at line {section_start} evidence id must be a positive integer")
            continue
        if identifier in ids:
            errors.append(f"section starting at line {section_start} duplicates evidence id {identifier}")
        ids.add(identifier)
        kind = item.get("kind")
        target = item.get("target")
        claim = item.get("claim")
        entry = {"id": identifier, "kind": kind, "target": target, "claim": claim}
        if kind not in {"source", "diff", "sketch"}:
            errors.append(f"section starting at line {section_start} evidence {identifier} has invalid kind")
        if not isinstance(target, str) or not target:
            errors.append(f"section starting at line {section_start} evidence {identifier} must set target")
        if not isinstance(claim, str) or not claim:
            errors.append(f"section starting at line {section_start} evidence {identifier} must set claim")
        if kind == "source" and isinstance(target, str):
            refs = source_ref_data([f"Source: {target}"])
            if len(refs) != 1:
                errors.append(f"section starting at line {section_start} evidence {identifier} has invalid source target")
            else:
                ref = refs[0]
                source_path = project_root / ref["path"]
                entry["source_ref"] = ref
                if not source_path.is_file():
                    errors.append(f"section starting at line {section_start} evidence {identifier}: source file does not exist: {ref['path']}")
                else:
                    line_count = len(split_lines(source_path.read_text(encoding="utf-8")))
                    if ref["start_line"] < 1 or ref["end_line"] > line_count:
                        errors.append(f"section starting at line {section_start} evidence {identifier}: source range is outside {ref['path']}")
                    else:
                        metrics = analyze_source_scope(ref["path"], source_path.read_text(encoding="utf-8"), ref["start_line"], ref["end_line"])
                        entry["static_metrics"] = metrics
                        entry["static_verdict"] = static_verdict(metrics)
                        metric_error = inventory_metrics_error(section_start, metrics)
                        if metric_error:
                            errors.append(metric_error)
        if kind == "diff" and isinstance(target, str):
            refs = diff_ref_data([f"Diff: {target}"])
            if len(refs) != 1:
                errors.append(f"section starting at line {section_start} evidence {identifier} has invalid diff target")
            else:
                ref = refs[0]
                entry["diff_ref"] = ref
                hunk = next((candidate for candidate in diff_hunks.get(ref["path"], []) if candidate.hunk_id == ref["hunk_id"]), None)
                if not hunk:
                    errors.append(f"section starting at line {section_start} evidence {identifier}: diff hunk does not exist: {ref['path']}#{ref['hunk_id']}")
                else:
                    explained_hunks.add((ref["path"], ref["hunk_id"]))
        if kind == "sketch" and isinstance(target, str):
            purpose = item.get("purpose")
            if purpose is not None:
                if not isinstance(purpose, str) or purpose not in SKETCH_PURPOSES:
                    errors.append(f"section starting at line {section_start} evidence {identifier}: sketch purpose must be one of {', '.join(sorted(SKETCH_PURPOSES))}")
                else:
                    entry["purpose"] = purpose
                    if purpose == "execution-map" and metadata.get("kind") != "overview":
                        errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map belongs in the overview")
            coverage = item.get("coverage")
            if coverage is not None:
                if purpose != "execution-map":
                    errors.append(f"section starting at line {section_start} evidence {identifier}: coverage is only valid for an execution-map")
                elif not isinstance(coverage, list) or not coverage or any(not isinstance(stage_id, str) or not stage_id for stage_id in coverage):
                    errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map coverage must list stage ids")
                else:
                    entry["coverage"] = coverage
            if purpose == "execution-map" and "coverage" not in entry:
                errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map must declare coverage")
            asset = (project_root / target).resolve()
            if not asset.is_file():
                errors.append(f"section starting at line {section_start} evidence {identifier}: sketch asset does not exist: {target}")
            elif asset.suffix.lower() != ".svg":
                errors.append(f"section starting at line {section_start} evidence {identifier}: sketch target must be an SVG asset")
            elif "<svg" not in asset.read_text(encoding="utf-8", errors="ignore").lower():
                errors.append(f"section starting at line {section_start} evidence {identifier}: sketch asset is not SVG")
            editable_target = item.get("editable_target")
            entry["editable_target"] = editable_target
            if not isinstance(editable_target, str) or not editable_target:
                errors.append(f"section starting at line {section_start} evidence {identifier}: sketch requires editable_target")
            else:
                editable_asset = (project_root / editable_target).resolve()
                if not editable_asset.is_file():
                    errors.append(f"section starting at line {section_start} evidence {identifier}: editable sketch asset does not exist: {editable_target}")
                elif editable_asset.suffix.lower() != ".excalidraw":
                    errors.append(f"section starting at line {section_start} evidence {identifier}: editable sketch asset must use .excalidraw")
                else:
                    try:
                        scene = json.loads(editable_asset.read_text(encoding="utf-8"))
                    except (OSError, json.JSONDecodeError):
                        scene = None
                    if not isinstance(scene, dict) or scene.get("type") != "excalidraw" or not isinstance(scene.get("elements"), list):
                        errors.append(f"section starting at line {section_start} evidence {identifier}: editable sketch asset is not an Excalidraw scene")
            model = item.get("text_model")
            if not isinstance(model, dict) or not model.get("claim") or not isinstance(model.get("nodes"), list) or not isinstance(model.get("edges"), list):
                errors.append(f"section starting at line {section_start} evidence {identifier}: sketch requires text_model claim, nodes, and edges")
            else:
                entry["text_model"] = model
                node_ids: set[str] = set()
                for node in model["nodes"]:
                    if not isinstance(node, dict) or not node.get("id") or not node.get("owner") or not node.get("state"):
                        errors.append(f"section starting at line {section_start} evidence {identifier}: every sketch node needs id, owner, and state")
                        continue
                    node_id = node["id"]
                    if not isinstance(node_id, str):
                        errors.append(f"section starting at line {section_start} evidence {identifier}: sketch node ids must be strings")
                        continue
                    if node_id in node_ids:
                        errors.append(f"section starting at line {section_start} evidence {identifier}: sketch node ids must be unique")
                    node_ids.add(node_id)
                if purpose == "execution-map":
                    edge_ids: set[str] = set()
                    for edge in model["edges"]:
                        if not isinstance(edge, dict):
                            errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map edges must be mappings")
                            continue
                        edge_id = edge.get("id")
                        if not isinstance(edge_id, str) or not edge_id:
                            errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map edges need stable string ids")
                        elif edge_id in edge_ids:
                            errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map edge ids must be unique")
                        else:
                            edge_ids.add(edge_id)
                        for endpoint_name in ("from", "to"):
                            endpoint = edge.get(endpoint_name)
                            if not isinstance(endpoint, str) or endpoint not in node_ids:
                                errors.append(f"section starting at line {section_start} evidence {identifier}: execution-map edge {endpoint_name} must reference a declared node")
                    entry["node_ids"] = node_ids
                    entry["edge_ids"] = edge_ids
        inventory.append(entry)
    expected_ids = set(range(1, len(entries) + 1))
    if ids and ids != expected_ids:
        errors.append(f"section starting at line {section_start} evidence ids must be consecutive from 1")
    unknown_links = links - ids
    if unknown_links:
        errors.append(f"section starting at line {section_start} links unknown evidence ids: {', '.join(map(str, sorted(unknown_links)))}")
    orphaned = ids - links
    if orphaned:
        errors.append(f"section starting at line {section_start} has unreferenced evidence ids: {', '.join(map(str, sorted(orphaned)))}")
    return errors, inventory, explained_hunks


def build_v2_inventory(project_root: Path, markdown_path: Path, allow_partial_diff: bool, frontmatter: dict[str, str], start_index: int, lines: list[str]) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    inventory: dict[str, Any] = {"schema": "code-reader-page-inventory/v2", "document": str(markdown_path), "document_type": frontmatter.get("type"), "pages": []}
    doc_type = frontmatter.get("type")
    if doc_type not in {"code-reader", "code-reader-diff"}:
        errors.append("frontmatter field `type` must be `code-reader` or `code-reader-diff`")
    if frontmatter.get("version") != "2":
        errors.append("frontmatter field `version` must be `2`")
    if not frontmatter.get("feature"):
        errors.append("frontmatter field `feature` is required")
    sections = split_sections(lines, start_index)
    if not sections:
        return errors + ["document has no sections"], inventory
    diff_hunks: dict[str, list[DiffHunk]] = {}
    if doc_type == "code-reader-diff":
        diff_value = frontmatter.get("diff")
        if not diff_value:
            errors.append("diff document must include frontmatter field `diff`")
        else:
            diff_path = (markdown_path.parent / diff_value).resolve()
            if not diff_path.is_file():
                errors.append(f"diff file does not exist: {diff_value}")
            else:
                diff_hunks = parse_unified_diff_hunks(diff_path.read_text(encoding="utf-8"))
    stage_ids: set[str] = set()
    runtime_stage_ids: set[str] = set()
    execution_maps: list[dict[str, Any]] = []
    stage_records: list[dict[str, Any]] = []
    explained_hunks: set[tuple[str, str]] = set()
    for section_index, (section_start, section_lines) in enumerate(sections):
        metadata, content, metadata_errors = split_v2_metadata(section_start, section_lines)
        errors.extend(metadata_errors)
        heading = parse_heading(content)
        if not heading:
            errors.append(f"section starting at line {section_start} is missing a markdown heading")
        if section_index == 0 and metadata.get("kind") != "overview":
            errors.append("first section must have kind: overview")
        identifier = str(metadata.get("id") or "")
        if identifier and identifier in stage_ids:
            errors.append(f"duplicate stage id `{identifier}`")
        stage_ids.add(identifier)
        if metadata.get("kind") == "stage" and identifier:
            runtime_stage_ids.add(identifier)
            stage_records.append({"id": identifier, "section_start": section_start, "map_anchor": metadata.get("map_anchor")})
        errors.extend(v2_required_model_errors(section_start, metadata))
        evidence_errors, evidence_inventory, hunk_refs = v2_evidence_errors(project_root, markdown_path, section_start, metadata, content, diff_hunks)
        errors.extend(evidence_errors)
        explained_hunks.update(hunk_refs)
        for evidence in evidence_inventory:
            if evidence.get("purpose") == "execution-map" and isinstance(evidence.get("coverage"), list):
                execution_maps.append({
                    "id": evidence["id"],
                    "section_start": section_start,
                    "coverage": evidence["coverage"],
                    "node_ids": evidence.get("node_ids", set()),
                    "edge_ids": evidence.get("edge_ids", set()),
                })
        inventory["pages"].append({"id": identifier, "kind": metadata.get("kind"), "section_start_line": section_start, "heading": heading_data(content)[0] if heading_data(content) else None, "map_anchor": metadata.get("map_anchor"), "evidence": evidence_inventory})
    covered_by_any_map: set[str] = set()
    for execution_map in execution_maps:
        covered = set(execution_map["coverage"])
        unknown = covered - runtime_stage_ids
        if unknown:
            errors.append(f"section starting at line {execution_map['section_start']}: execution-map coverage has unknown stage ids: {', '.join(sorted(unknown))}")
        covered_by_any_map.update(covered)
    if execution_maps:
        missing = runtime_stage_ids - covered_by_any_map
        if missing:
            errors.append(f"execution-map coverage misses stage ids: {', '.join(sorted(missing))}")
    maps_by_id = {execution_map["id"]: execution_map for execution_map in execution_maps}
    for stage in stage_records:
        anchor = stage["map_anchor"]
        if not execution_maps:
            if anchor is not None:
                errors.append(f"section starting at line {stage['section_start']}: map_anchor requires an execution-map")
            continue
        candidate_maps = [execution_map for execution_map in execution_maps if stage["id"] in execution_map["coverage"]]
        if not isinstance(anchor, dict):
            if len(execution_maps) == 1 and stage["id"] in execution_maps[0]["node_ids"]:
                continue
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` needs map_anchor")
            continue
        map_id = anchor.get("map")
        if not isinstance(map_id, int) or map_id not in maps_by_id:
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor has unknown map id")
            continue
        execution_map = maps_by_id[map_id]
        if execution_map not in candidate_maps:
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor references a map that does not cover the stage")
        node_ids = anchor.get("nodes", [])
        edge_ids = anchor.get("edges", [])
        if not isinstance(node_ids, list) or any(not isinstance(node_id, str) or not node_id for node_id in node_ids):
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor nodes must be a list of ids")
            node_ids = []
        if not isinstance(edge_ids, list) or any(not isinstance(edge_id, str) or not edge_id for edge_id in edge_ids):
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor edges must be a list of ids")
            edge_ids = []
        if not node_ids and not edge_ids:
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor must select a node or edge")
        unknown_nodes = set(node_ids) - execution_map["node_ids"]
        unknown_edges = set(edge_ids) - execution_map["edge_ids"]
        if unknown_nodes:
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor has unknown node ids: {', '.join(sorted(unknown_nodes))}")
        if unknown_edges:
            errors.append(f"section starting at line {stage['section_start']}: stage `{stage['id']}` map_anchor has unknown edge ids: {', '.join(sorted(unknown_edges))}")
    if diff_hunks and not allow_partial_diff:
        for diff_path, hunks in sorted(diff_hunks.items()):
            for hunk in hunks:
                if (diff_path, hunk.hunk_id) not in explained_hunks:
                    errors.append(f"missing explanation for diff hunk `{diff_path}#{hunk.hunk_id}`")
    return errors, inventory


def build_inventory(project_root: Path, markdown_path: Path, allow_partial_diff: bool) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    text = markdown_path.read_text(encoding="utf-8")
    lines = split_lines(text)
    frontmatter, start_index, frontmatter_errors = parse_frontmatter(lines)
    if frontmatter.get("version") == "2":
        errors, inventory = build_v2_inventory(project_root, markdown_path, allow_partial_diff, frontmatter, start_index, lines)
        return frontmatter_errors + errors, inventory
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
    if frontmatter.get("version") != "2":
        errors.append("frontmatter field `version` must be `2`")

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
            "static_metrics": {
                "status": "NOT_AVAILABLE",
                "reason_code": "NO_ANALYSIS_TARGET",
                "fallback_required": True,
                "analysis_region": None,
                "evidence": [],
            },
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
