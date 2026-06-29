#!/usr/bin/env python
"""Validate code-reader.nvim explanation markdown."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


FRONT_PAGE_MARKER = "<!-- code-reader: front-page -->"
SOURCE_RE = re.compile(r"([\w._\-/\\]+)#L(\d+)(?:-L?(\d+))?")
DIFF_RE = re.compile(r"([\w._\-/\\]+)#([Hh]\d+)(?:@([A-Za-z]+):([^\s`\]]+))?")
STEP_LINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]")


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


def parse_unified_diff(text: str) -> dict[str, set[str]]:
    files: dict[str, set[str]] = {}
    old_path: str | None = None
    current_path: str | None = None
    hunk_count = 0

    for line in split_lines(text):
        old_match = re.match(r"^---\s+(.+)$", line)
        if old_match:
            old_path = strip_diff_prefix(old_match.group(1))
            current_path = None
            hunk_count = 0
            continue

        new_match = re.match(r"^\+\+\+\s+(.+)$", line)
        if new_match:
            new_path = strip_diff_prefix(new_match.group(1))
            current_path = normalize_path(new_path or old_path or "")
            if current_path:
                files.setdefault(current_path, set())
            continue

        if current_path and re.match(r"^@@ -\d+,?\d* \+\d+,?\d* @@", line):
            hunk_count += 1
            files[current_path].add(f"H{hunk_count}")

    return files


def validate_source_refs(project_root: Path, section_start: int, lines: list[str]) -> list[str]:
    errors: list[str] = []
    for line in lines:
        for match in SOURCE_RE.finditer(line):
            rel_path = normalize_path(match.group(1))
            start_line = int(match.group(2))
            end_line = int(match.group(3) or match.group(2))
            source_path = project_root / rel_path
            if start_line < 1 or end_line < start_line:
                errors.append(f"line {section_start}: invalid source range {rel_path}#L{start_line}-L{end_line}")
                continue
            if not source_path.is_file():
                errors.append(f"line {section_start}: source file does not exist: {rel_path}")
                continue
            line_count = len(source_path.read_text(encoding="utf-8").splitlines())
            if end_line > line_count:
                errors.append(
                    f"line {section_start}: source range exceeds file length: {rel_path}#L{start_line}-L{end_line}"
                )
    return errors


def collect_source_refs(lines: list[str]) -> list[str]:
    return [match.group(0) for line in lines for match in SOURCE_RE.finditer(line)]


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
        for match in DIFF_RE.finditer(line):
            refs.append(
                (
                    normalize_path(match.group(1)),
                    match.group(2).upper(),
                    validate_diff_modifier(match.group(3), match.group(4)),
                )
            )
    return refs


def validate_doc(project_root: Path, markdown_path: Path, allow_partial_diff: bool) -> list[str]:
    errors: list[str] = []
    text = markdown_path.read_text(encoding="utf-8")
    lines = split_lines(text)
    frontmatter, start_index, frontmatter_errors = parse_frontmatter(lines)
    errors.extend(frontmatter_errors)

    doc_type = frontmatter.get("type")
    if doc_type not in {"code-reader", "code-reader-diff"}:
        errors.append("frontmatter field `type` must be `code-reader` or `code-reader-diff`")
    if frontmatter.get("version") != "1":
        errors.append("frontmatter field `version` must be `1`")

    sections = split_sections(lines, start_index)
    if not sections:
        errors.append("document has no sections")
        return errors

    first_start, first_lines = sections[0]
    marker_index = first_non_empty_index(first_lines)
    if marker_index is None or trim(first_lines[marker_index]) != FRONT_PAGE_MARKER:
        errors.append("first section must start with the code-reader front page marker")

    step_ids: set[str] = set()
    non_front_sections: list[tuple[int, list[str]]] = []
    for index, (section_start, section_lines) in enumerate(sections, start=1):
        is_front_page = index == 1
        heading = parse_heading(section_lines)
        if not heading:
            errors.append(f"section starting at line {section_start} is missing a markdown heading")
        step_id = section_step_id(index, section_lines, is_front_page)
        if step_id in step_ids:
            errors.append(f"duplicate step id `{step_id}`")
        step_ids.add(step_id)
        if not is_front_page:
            non_front_sections.append((section_start, section_lines))

    for section_start, section_lines in sections:
        for line in section_lines:
            for match in STEP_LINK_RE.finditer(line):
                target = match.group(1).strip()
                if target not in step_ids:
                    errors.append(f"line {section_start}: unknown step link target `{target}`")

    if doc_type == "code-reader":
        for section_start, section_lines in non_front_sections:
            if not collect_source_refs(section_lines):
                errors.append(f"section starting at line {section_start} has no source reference")
            errors.extend(validate_source_refs(project_root, section_start, section_lines))

    if doc_type == "code-reader-diff":
        diff_value = frontmatter.get("diff")
        if not diff_value:
            errors.append("diff document must include frontmatter field `diff`")
            diff_files: dict[str, set[str]] = {}
        else:
            diff_path = (markdown_path.parent / diff_value).resolve()
            if not diff_path.is_file():
                errors.append(f"diff file does not exist: {diff_value}")
                diff_files = {}
            else:
                diff_files = parse_unified_diff(diff_path.read_text(encoding="utf-8"))

        if collect_diff_refs(first_lines):
            errors.append("front page must not contain diff hunk references")

        explained: set[tuple[str, str]] = set()
        for section_start, section_lines in non_front_sections:
            refs = collect_diff_refs(section_lines)
            if not refs:
                errors.append(f"section starting at line {section_start} has no diff reference")
            for path, hunk_id, valid_modifier in refs:
                if not valid_modifier:
                    errors.append(f"line {section_start}: invalid diff range modifier `{path}#{hunk_id}`")
                if path not in diff_files:
                    errors.append(f"line {section_start}: diff file does not contain path `{path}`")
                elif hunk_id not in diff_files[path]:
                    errors.append(f"line {section_start}: diff file does not contain hunk `{path}#{hunk_id}`")
                explained.add((path, hunk_id))

        if diff_files and not allow_partial_diff:
            for path, hunks in sorted(diff_files.items()):
                for hunk_id in sorted(hunks, key=lambda item: int(item[1:])):
                    if (path, hunk_id) not in explained:
                        errors.append(f"missing explanation for diff hunk `{path}#{hunk_id}`")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_file")
    parser.add_argument("--project-root", default=".", help="Project root used to resolve source paths")
    parser.add_argument("--allow-partial-diff", action="store_true", help="Allow diff docs that do not cover every hunk")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    markdown_path = Path(args.markdown_file).resolve()
    errors = validate_doc(project_root, markdown_path, args.allow_partial_diff)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"ok: {markdown_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
