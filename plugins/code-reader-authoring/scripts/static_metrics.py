#!/usr/bin/env python
"""Deterministic, dependency-free metrics for Code Reader page scopes.

Python and Lua use dependency-free adapters. C/C++, Go, JavaScript,
TypeScript, and Rust use profile-specific Tree-sitter adapters after the
registered bootstrap installs their pinned grammar package. No package
installation happens in this module.

``peak_live_bindings`` is a local-binding approximation.  Python uses
backward lexical liveness with branch union; Lua uses backward lexical
liveness over the directly parsed function body.  Fields, globals, aliases,
and inter-procedural values remain semantic-review work.
"""

from __future__ import annotations

import argparse
import ast
import importlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


SCHEMA = "code-reader-static-metrics/v1"
PROFILE_PATH = Path(__file__).with_name("static_analysis_profiles.json")
SUPPORTED = "SUPPORTED"
NOT_AVAILABLE = "NOT_AVAILABLE"
PARSE_ERROR = "PARSE_ERROR"

_LANGUAGE_ALIASES = {
    "py": "python",
    "python3": "python",
    "js": "javascript",
    "node": "javascript",
    "ts": "typescript",
    "tsx": "typescript",
    "c++": "cpp",
}


def load_profiles() -> dict[str, dict[str, Any]]:
    """Return the checked-in analysis profiles without mutating user state."""
    contents = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    return contents["profiles"]


def language_for_path(path: str | Path) -> str | None:
    """Return the registered language for *path*, or ``None`` when unknown."""
    suffix = Path(path).suffix.lower()
    for language, profile in load_profiles().items():
        if suffix in profile.get("extensions", []):
            return language
    return None


def _normalize_language(language: str | None, path: str | Path) -> str | None:
    if language is None or language.lower() == "auto":
        return language_for_path(path)
    return _LANGUAGE_ALIASES.get(language.lower(), language.lower())


def _result(
    *,
    path: str,
    language: str | None,
    status: str,
    backend: str,
    definitions: list[dict[str, Any]] | None = None,
    reason: str | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "schema": SCHEMA,
        "path": path,
        "language": language,
        "status": status,
        "backend": backend,
        "definitions": definitions or [],
    }
    if reason:
        result["reason"] = reason
    return result


def _definition(
    *,
    language: str,
    name: str,
    qualified_name: str,
    kind: str,
    start_line: int,
    end_line: int,
    cyclomatic_complexity: int,
    decision_points: list[dict[str, Any]],
    peak_live_bindings: int,
    peak_line: int | None,
    peak_names: list[str],
    live_method: str,
    live_limitations: list[str],
) -> dict[str, Any]:
    metrics = _metrics(
        cyclomatic_complexity=cyclomatic_complexity,
        decision_points=decision_points,
        peak_live_bindings=peak_live_bindings,
        peak_line=peak_line,
        peak_names=peak_names,
        live_method=live_method,
        live_limitations=live_limitations,
    )
    return {
        "id": f"{language}:{qualified_name}:{start_line}",
        "name": name,
        "qualified_name": qualified_name,
        "kind": kind,
        "start_line": start_line,
        "end_line": end_line,
        "range": {"start_line": start_line, "end_line": end_line},
        "metrics": metrics,
    }


def _metrics(
    *,
    cyclomatic_complexity: int,
    decision_points: list[dict[str, Any]],
    peak_live_bindings: int,
    peak_line: int | None,
    peak_names: list[str],
    live_method: str,
    live_limitations: list[str],
) -> dict[str, Any]:
    evidence: list[dict[str, Any]] = [
        {
            "metric": "cyclomatic_complexity",
            "method": "one_plus_decision_points",
            "value": cyclomatic_complexity,
            "decision_points": decision_points,
        },
        {
            "metric": "peak_live_bindings",
            "method": live_method,
            "value": peak_live_bindings,
            "line": peak_line,
            "bindings": peak_names,
            "limitations": live_limitations,
        },
    ]
    return {
        "cyclomatic_complexity": cyclomatic_complexity,
        "peak_live_bindings": peak_live_bindings,
        "evidence": evidence,
    }


def _definition_identity(definition: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": definition["id"],
        "name": definition["name"],
        "qualified_name": definition["qualified_name"],
        "kind": definition["kind"],
        "start_line": definition["start_line"],
        "end_line": definition["end_line"],
    }


def _trim_non_code_range(text: str, start_line: int, end_line: int) -> tuple[int, int] | None:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if start_line < 1 or end_line < start_line or end_line > len(lines):
        return None
    comment_prefixes = ("#", "--", "//", "/*", "*", "*/")
    selected = [
        number
        for number in range(start_line, end_line + 1)
        if (stripped := lines[number - 1].strip()) and not stripped.startswith(comment_prefixes)
    ]
    if not selected:
        return None
    return selected[0], selected[-1]


def _range_result(
    analysis: dict[str, Any],
    start_line: int,
    end_line: int,
    *,
    status: str,
    definition: dict[str, Any] | None = None,
    metrics: dict[str, Any] | None = None,
    analysis_region: dict[str, Any] | None = None,
    reason_code: str | None = None,
    reason: str | None = None,
) -> dict[str, Any]:
    result = {
        "schema": SCHEMA,
        "path": analysis["path"],
        "language": analysis["language"],
        "backend": analysis["backend"],
        "status": status,
        "selection": {
            "start_line": start_line,
            "end_line": end_line,
            "definition": _definition_identity(definition) if definition else None,
        },
        "analysis_region": analysis_region,
        "fallback_required": status != SUPPORTED,
    }
    if metrics:
        result["metrics"] = metrics
    if reason_code:
        result["reason_code"] = reason_code
    if reason:
        result["reason"] = reason
    return result


class _PythonDecisionVisitor(ast.NodeVisitor):
    """Collect CFG decision nodes while excluding nested executable scopes."""

    def __init__(self) -> None:
        self.points: list[dict[str, Any]] = []

    def _add(self, node: ast.AST, kind: str, count: int = 1) -> None:
        for _ in range(count):
            self.points.append({"kind": kind, "line": getattr(node, "lineno", None)})

    def visit_If(self, node: ast.If) -> None:  # noqa: N802 - AST API name
        self._add(node, "if")
        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:  # noqa: N802
        self._add(node, "for")
        self.generic_visit(node)

    def visit_AsyncFor(self, node: ast.AsyncFor) -> None:  # noqa: N802
        self._add(node, "async_for")
        self.generic_visit(node)

    def visit_While(self, node: ast.While) -> None:  # noqa: N802
        self._add(node, "while")
        self.generic_visit(node)

    def visit_IfExp(self, node: ast.IfExp) -> None:  # noqa: N802
        self._add(node, "conditional_expression")
        self.generic_visit(node)

    def visit_BoolOp(self, node: ast.BoolOp) -> None:  # noqa: N802
        self._add(node, "boolean_short_circuit", max(0, len(node.values) - 1))
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:  # noqa: N802
        self._add(node, "except")
        self.generic_visit(node)

    def visit_Match(self, node: ast.Match) -> None:  # noqa: N802
        for case in node.cases:
            if not _is_irrefutable_match_case(case):
                self._add(case.pattern, "match_case")
        self.generic_visit(node)

    def visit_comprehension(self, node: ast.comprehension) -> None:  # noqa: N802
        self._add(node, "comprehension_for")
        self._add(node, "comprehension_if", len(node.ifs))
        self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        return

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        return

    def visit_Lambda(self, node: ast.Lambda) -> None:  # noqa: N802
        return

    def visit_ClassDef(self, node: ast.ClassDef) -> None:  # noqa: N802
        return


def _is_irrefutable_match_case(case: ast.match_case) -> bool:
    return isinstance(case.pattern, ast.MatchAs) and case.pattern.pattern is None and case.guard is None


class _PythonBindingVisitor(ast.NodeVisitor):
    """Collect local binding names from one function body, not child scopes."""

    def __init__(self, args: ast.arguments) -> None:
        self.bindings: set[str] = set()
        self.globals: set[str] = set()
        self.nonlocals: set[str] = set()
        for argument in [*args.posonlyargs, *args.args, *args.kwonlyargs]:
            self.bindings.add(argument.arg)
        if args.vararg:
            self.bindings.add(args.vararg.arg)
        if args.kwarg:
            self.bindings.add(args.kwarg.arg)

    def visit_Name(self, node: ast.Name) -> None:  # noqa: N802
        if isinstance(node.ctx, (ast.Store, ast.Del)):
            self.bindings.add(node.id)

    def visit_Import(self, node: ast.Import) -> None:  # noqa: N802
        for alias in node.names:
            self.bindings.add(alias.asname or alias.name.split(".", 1)[0])

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:  # noqa: N802
        for alias in node.names:
            if alias.name != "*":
                self.bindings.add(alias.asname or alias.name)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:  # noqa: N802
        if node.name:
            self.bindings.add(node.name)
        self.generic_visit(node)

    def visit_Global(self, node: ast.Global) -> None:  # noqa: N802
        self.globals.update(node.names)

    def visit_Nonlocal(self, node: ast.Nonlocal) -> None:  # noqa: N802
        self.nonlocals.update(node.names)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self.bindings.add(node.name)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self.bindings.add(node.name)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:  # noqa: N802
        self.bindings.add(node.name)

    def visit_Lambda(self, node: ast.Lambda) -> None:  # noqa: N802
        return


class _PythonAccessVisitor(ast.NodeVisitor):
    """Collect direct reads and writes without descending into child scopes."""

    def __init__(self) -> None:
        self.reads: set[str] = set()
        self.writes: set[str] = set()

    def visit_Name(self, node: ast.Name) -> None:  # noqa: N802
        if isinstance(node.ctx, ast.Load):
            self.reads.add(node.id)
        elif isinstance(node.ctx, (ast.Store, ast.Del)):
            self.writes.add(node.id)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self.writes.add(node.name)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self.writes.add(node.name)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:  # noqa: N802
        self.writes.add(node.name)

    def visit_Lambda(self, node: ast.Lambda) -> None:  # noqa: N802
        return


def _python_access(node: ast.AST, local_bindings: set[str]) -> tuple[set[str], set[str]]:
    visitor = _PythonAccessVisitor()
    visitor.visit(node)
    if isinstance(node, ast.AugAssign) and isinstance(node.target, ast.Name):
        visitor.reads.add(node.target.id)
    return visitor.reads & local_bindings, visitor.writes & local_bindings


def _record_live(live_by_line: dict[int, set[str]], node: ast.AST, live: set[str]) -> None:
    line = getattr(node, "lineno", None)
    if line is not None:
        live_by_line.setdefault(line, set()).update(live)


def _python_block_liveness(
    statements: list[ast.stmt],
    live_after: set[str],
    local_bindings: set[str],
    live_by_line: dict[int, set[str]],
) -> set[str]:
    live = set(live_after)
    for statement in reversed(statements):
        live = _python_statement_liveness(statement, live, local_bindings, live_by_line)
    return live


def _python_statement_liveness(
    statement: ast.stmt,
    live_after: set[str],
    local_bindings: set[str],
    live_by_line: dict[int, set[str]],
) -> set[str]:
    if isinstance(statement, ast.If):
        body_live = _python_block_liveness(statement.body, live_after, local_bindings, live_by_line)
        else_live = _python_block_liveness(statement.orelse, live_after, local_bindings, live_by_line) if statement.orelse else set(live_after)
        reads, writes = _python_access(statement.test, local_bindings)
        live = reads | ((body_live | else_live) - writes)
    elif isinstance(statement, (ast.For, ast.AsyncFor)):
        else_live = _python_block_liveness(statement.orelse, live_after, local_bindings, live_by_line) if statement.orelse else set(live_after)
        iterable_reads, _ = _python_access(statement.iter, local_bindings)
        _, target_writes = _python_access(statement.target, local_bindings)
        live = iterable_reads | else_live
        for _ in range(32):
            body_live = _python_block_liveness(statement.body, live, local_bindings, live_by_line)
            next_live = iterable_reads | else_live | (body_live - target_writes)
            if next_live == live:
                break
            live = next_live
    elif isinstance(statement, ast.While):
        else_live = _python_block_liveness(statement.orelse, live_after, local_bindings, live_by_line) if statement.orelse else set(live_after)
        reads, writes = _python_access(statement.test, local_bindings)
        live = reads | else_live
        for _ in range(32):
            body_live = _python_block_liveness(statement.body, live, local_bindings, live_by_line)
            next_live = reads | else_live | (body_live - writes)
            if next_live == live:
                break
            live = next_live
    elif isinstance(statement, (ast.With, ast.AsyncWith)):
        body_live = _python_block_liveness(statement.body, live_after, local_bindings, live_by_line)
        reads: set[str] = set()
        writes: set[str] = set()
        for item in statement.items:
            item_reads, _ = _python_access(item.context_expr, local_bindings)
            reads.update(item_reads)
            if item.optional_vars:
                _, item_writes = _python_access(item.optional_vars, local_bindings)
                writes.update(item_writes)
        live = reads | (body_live - writes)
    elif isinstance(statement, ast.Try):
        finally_live = _python_block_liveness(statement.finalbody, live_after, local_bindings, live_by_line) if statement.finalbody else set(live_after)
        normal_live = _python_block_liveness(statement.orelse, finally_live, local_bindings, live_by_line) if statement.orelse else finally_live
        body_live = _python_block_liveness(statement.body, normal_live, local_bindings, live_by_line)
        handler_lives = [
            _python_block_liveness(handler.body, finally_live, local_bindings, live_by_line)
            for handler in statement.handlers
        ]
        live = body_live
        for handler_live in handler_lives:
            live |= handler_live
    elif hasattr(ast, "Match") and isinstance(statement, ast.Match):
        reads, writes = _python_access(statement.subject, local_bindings)
        live = reads - writes
        for case in statement.cases:
            live |= _python_block_liveness(case.body, live_after, local_bindings, live_by_line)
    else:
        reads, writes = _python_access(statement, local_bindings)
        live = reads | (live_after - writes)

    _record_live(live_by_line, statement, live)
    return live


def _python_peak_liveness(
    node: ast.FunctionDef | ast.AsyncFunctionDef, local_bindings: set[str]
) -> tuple[int, int | None, list[str]]:
    live_by_line: dict[int, set[str]] = {}
    _python_block_liveness(node.body, set(), local_bindings, live_by_line)
    peak_line: int | None = None
    peak_names: list[str] = []
    for line, names in sorted(live_by_line.items()):
        current = sorted(names)
        if len(current) > len(peak_names):
            peak_line = line
            peak_names = current
    return len(peak_names), peak_line, peak_names


def _python_metric_definition(node: ast.FunctionDef | ast.AsyncFunctionDef, qualified_name: str) -> dict[str, Any]:
    decisions = _PythonDecisionVisitor()
    bindings = _PythonBindingVisitor(node.args)
    for statement in node.body:
        decisions.visit(statement)
        bindings.visit(statement)

    local_bindings = bindings.bindings - bindings.globals - bindings.nonlocals
    peak_count, peak_line, peak_names = _python_peak_liveness(node, local_bindings)

    return _definition(
        language="python",
        name=node.name,
        qualified_name=qualified_name,
        kind="async_function" if isinstance(node, ast.AsyncFunctionDef) else "function",
        start_line=min([node.lineno, *(decorator.lineno for decorator in node.decorator_list)]),
        end_line=node.end_lineno or node.lineno,
        cyclomatic_complexity=1 + len(decisions.points),
        decision_points=decisions.points,
        peak_live_bindings=peak_count,
        peak_line=peak_line,
        peak_names=peak_names,
        live_method="backward_lexical_liveness_branch_union",
        live_limitations=[
            "path-insensitive branch union can overapproximate concurrent values",
            "excludes fields",
            "excludes globals and nonlocals",
            "excludes aliases and inter-procedural values",
        ],
    )


class _PythonDefinitionVisitor(ast.NodeVisitor):
    def __init__(self) -> None:
        self.scope: list[str] = []
        self.definitions: list[dict[str, Any]] = []

    def visit_ClassDef(self, node: ast.ClassDef) -> None:  # noqa: N802
        self.scope.append(node.name)
        for statement in node.body:
            self.visit(statement)
        self.scope.pop()

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self._visit_function(node)

    def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        qualified_name = ".".join([*self.scope, node.name])
        self.definitions.append(_python_metric_definition(node, qualified_name))
        self.scope.append(node.name)
        for statement in node.body:
            self.visit(statement)
        self.scope.pop()


def _python_definitions(text: str) -> list[dict[str, Any]]:
    module = ast.parse(text)
    collector = _PythonDefinitionVisitor()
    collector.visit(module)
    return collector.definitions


def _python_function_nodes(text: str) -> dict[str, ast.FunctionDef | ast.AsyncFunctionDef]:
    module = ast.parse(text)
    nodes: dict[str, ast.FunctionDef | ast.AsyncFunctionDef] = {}

    class Collector(ast.NodeVisitor):
        def __init__(self) -> None:
            self.scope: list[str] = []

        def visit_ClassDef(self, node: ast.ClassDef) -> None:  # noqa: N802
            self.scope.append(node.name)
            for statement in node.body:
                self.visit(statement)
            self.scope.pop()

        def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
            self._visit_function(node)

        def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
            self._visit_function(node)

        def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
            qualified_name = ".".join([*self.scope, node.name])
            start_line = min([node.lineno, *(decorator.lineno for decorator in node.decorator_list)])
            nodes[f"python:{qualified_name}:{start_line}"] = node
            self.scope.append(node.name)
            for statement in node.body:
                self.visit(statement)
            self.scope.pop()

    Collector().visit(module)
    return nodes


def _python_statement_suites(node: ast.AST) -> Iterable[list[ast.stmt]]:
    for _, value in ast.iter_fields(node):
        if isinstance(value, list) and value and all(isinstance(item, ast.stmt) for item in value):
            yield value
            for statement in value:
                if not isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    yield from _python_statement_suites(statement)
        elif isinstance(value, ast.AST) and not isinstance(value, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            yield from _python_statement_suites(value)


def _python_region_statements(
    node: ast.FunctionDef | ast.AsyncFunctionDef, start_line: int, end_line: int
) -> list[ast.stmt] | None:
    matches: list[list[ast.stmt]] = []
    for suite in _python_statement_suites(node):
        start_index = next((index for index, statement in enumerate(suite) if statement.lineno == start_line), None)
        if start_index is None:
            continue
        for end_index in range(start_index, len(suite)):
            statement = suite[end_index]
            if (statement.end_lineno or statement.lineno) != end_line:
                continue
            region = suite[start_index : end_index + 1]
            if any(isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) for item in region):
                continue
            matches.append(region)
    if not matches:
        return None
    return min(matches, key=lambda statements: (len(statements), statements[0].lineno))


def _python_region_metrics(
    node: ast.FunctionDef | ast.AsyncFunctionDef, statements: list[ast.stmt]
) -> dict[str, Any]:
    decisions = _PythonDecisionVisitor()
    bindings = _PythonBindingVisitor(node.args)
    for statement in node.body:
        bindings.visit(statement)
    for statement in statements:
        decisions.visit(statement)
    local_bindings = bindings.bindings - bindings.globals - bindings.nonlocals
    live_by_line: dict[int, set[str]] = {}
    _python_block_liveness(statements, set(), local_bindings, live_by_line)
    peak_line: int | None = None
    peak_names: list[str] = []
    for line, names in sorted(live_by_line.items()):
        current = sorted(names)
        if len(current) > len(peak_names):
            peak_line = line
            peak_names = current
    return _metrics(
        cyclomatic_complexity=1 + len(decisions.points),
        decision_points=decisions.points,
        peak_live_bindings=len(peak_names),
        peak_line=peak_line,
        peak_names=peak_names,
        live_method="backward_lexical_liveness_branch_union_region",
        live_limitations=[
            "region analysis excludes values needed only after the selected range",
            "path-insensitive branch union can overapproximate concurrent values",
            "excludes fields, globals, nonlocals, aliases, and inter-procedural values",
        ],
    )


_LUA_FUNCTION_DECL = re.compile(
    r"^\s*(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*(?:[.:][A-Za-z_][A-Za-z0-9_]*)*)\s*\(([^)]*)\)"
)
_LUA_FUNCTION_ASSIGN = re.compile(
    r"^\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*(?:[.:][A-Za-z_][A-Za-z0-9_]*)*)\s*=\s*function\s*\(([^)]*)\)"
)
_LUA_IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
_LUA_END = re.compile(r"\bend\b")
_LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local",
    "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}


def _strip_lua_comment(line: str) -> str:
    quote: str | None = None
    escaped = False
    for index in range(len(line) - 1):
        character = line[index]
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            continue
        if character in {"'", '"'}:
            quote = character
        elif line[index : index + 2] == "--":
            return line[:index]
    return line


def _lua_function_start(code: str) -> tuple[str, list[str]] | None:
    match = _LUA_FUNCTION_DECL.match(code) or _LUA_FUNCTION_ASSIGN.match(code)
    if not match:
        return None
    parameters = [name.strip() for name in match.group(2).split(",") if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name.strip())]
    return match.group(1), parameters


def _lua_block_starts(code: str, starts_function: bool) -> list[str]:
    blocks: list[str] = ["function"] if starts_function else []
    if re.search(r"\bif\b.*\bthen\b", code):
        blocks.append("if")
    if re.search(r"\bfor\b.*\bdo\b", code):
        blocks.append("for")
    if re.search(r"\bwhile\b.*\bdo\b", code):
        blocks.append("while")
    if re.search(r"\brepeat\b", code):
        blocks.append("repeat")
    if re.match(r"^\s*do\b", code):
        blocks.append("do")
    return blocks


def _lua_definitions(text: str) -> tuple[list[dict[str, Any]], str | None]:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    stack: list[dict[str, Any]] = []
    raw_definitions: list[dict[str, Any]] = []

    for number, raw_line in enumerate(lines, start=1):
        code = _strip_lua_comment(raw_line)
        function_start = _lua_function_start(code)
        starts_function = function_start is not None
        if function_start:
            name, parameters = function_start
            function = {"name": name, "parameters": parameters, "start_line": number, "end_line": None}
            raw_definitions.append(function)
            stack.append({"kind": "function", "definition": function})

        for kind in _lua_block_starts(code, starts_function)[1 if starts_function else 0 :]:
            stack.append({"kind": kind})

        if re.search(r"\buntil\b", code):
            for index in range(len(stack) - 1, -1, -1):
                if stack[index]["kind"] == "repeat":
                    stack.pop(index)
                    break

        for _ in _LUA_END.finditer(code):
            if not stack:
                return [], f"unmatched 'end' at line {number}"
            closed = stack.pop()
            if closed["kind"] == "function":
                closed["definition"]["end_line"] = number

    unclosed = [entry for entry in stack if entry["kind"] == "function"]
    if unclosed:
        return [], f"unclosed function starting at line {unclosed[-1]['definition']['start_line']}"
    if stack:
        return [], "unclosed Lua block"

    definitions: list[dict[str, Any]] = []
    for definition in raw_definitions:
        end_line = definition["end_line"]
        if end_line is None:
            return [], f"unclosed function starting at line {definition['start_line']}"
        definitions.append(_lua_metric_definition(lines, definition, raw_definitions))
    return definitions, None


def _lua_direct_line_numbers(definition: dict[str, Any], definitions: list[dict[str, Any]]) -> Iterable[int]:
    children = [
        child for child in definitions
        if child is not definition
        and definition["start_line"] < child["start_line"]
        and child["end_line"] is not None
        and child["end_line"] < definition["end_line"]
    ]
    skipped: set[int] = set()
    for child in children:
        skipped.update(range(child["start_line"], child["end_line"] + 1))
    return (
        number
        for number in range(definition["start_line"] + 1, definition["end_line"])
        if number not in skipped
    )


def _lua_declared_bindings(code: str) -> set[str]:
    bindings: set[str] = set()
    local_match = re.match(r"^\s*local\s+(?!function\b)(.+?)(?:\s*=|$)", code)
    if local_match:
        for name in local_match.group(1).split(","):
            name = name.strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
                bindings.add(name)
    for_match = re.match(r"^\s*for\s+(.+?)\s+(?:in\b|=)", code)
    if for_match:
        for name in for_match.group(1).split(","):
            name = name.strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
                bindings.add(name)
    return bindings


def _lua_line_accesses(code: str, bindings: set[str]) -> tuple[set[str], set[str]]:
    """Return local reads/writes for one direct Lua source line.

    This lexical parser intentionally handles plain declarations, loop targets,
    and assignments only.  Its result is a deterministic approximation, not a
    replacement for a language CFG or alias analysis.
    """
    write_positions: set[tuple[int, int]] = set()
    assignment = re.search(r"(?<![<>=~])=(?!=)", code)
    if assignment:
        for match in _LUA_IDENTIFIER.finditer(code[: assignment.start()]):
            if match.group(0) in bindings:
                write_positions.add((match.start(), match.end()))

    declaration = re.match(r"^\s*local\s+(?!function\b)(.+?)(?:\s*=|$)", code)
    if declaration:
        for match in _LUA_IDENTIFIER.finditer(declaration.group(1)):
            absolute_start = declaration.start(1) + match.start()
            write_positions.add((absolute_start, declaration.start(1) + match.end()))
    loop_target = re.match(r"^\s*for\s+(.+?)\s+(?:in\b|=)", code)
    if loop_target:
        for match in _LUA_IDENTIFIER.finditer(loop_target.group(1)):
            absolute_start = loop_target.start(1) + match.start()
            write_positions.add((absolute_start, loop_target.start(1) + match.end()))

    reads: set[str] = set()
    writes: set[str] = set()
    for match in _LUA_IDENTIFIER.finditer(code):
        name = match.group(0)
        previous = code[match.start() - 1] if match.start() else ""
        if name not in bindings or name in _LUA_KEYWORDS or previous in {".", ":"}:
            continue
        if (match.start(), match.end()) in write_positions:
            writes.add(name)
        else:
            reads.add(name)
    return reads, writes


def _lua_metric_definition(
    lines: list[str], definition: dict[str, Any], all_definitions: list[dict[str, Any]]
) -> dict[str, Any]:
    direct_numbers = list(_lua_direct_line_numbers(definition, all_definitions))
    direct_lines = [(number, _strip_lua_comment(lines[number - 1])) for number in direct_numbers]
    points: list[dict[str, Any]] = []
    bindings = set(definition["parameters"])

    for number, code in direct_lines:
        if re.search(r"\bif\b.*\bthen\b", code):
            points.append({"kind": "if", "line": number})
        if re.search(r"\belseif\b.*\bthen\b", code):
            points.append({"kind": "elseif", "line": number})
        if re.search(r"\bfor\b.*\bdo\b", code):
            points.append({"kind": "for", "line": number})
        if re.search(r"\bwhile\b.*\bdo\b", code):
            points.append({"kind": "while", "line": number})
        if re.search(r"\brepeat\b", code):
            points.append({"kind": "repeat", "line": number})
        for token in re.finditer(r"\b(?:and|or)\b", code):
            points.append({"kind": "boolean_short_circuit", "line": number})

        bindings.update(_lua_declared_bindings(code))

    live: set[str] = set()
    peak_line: int | None = None
    peak_names: list[str] = []
    for number, code in reversed(direct_lines):
        reads, writes = _lua_line_accesses(code, bindings)
        live = reads | (live - writes)
        current = sorted(live)
        if len(current) > len(peak_names):
            peak_line = number
            peak_names = current

    return _definition(
        language="lua",
        name=definition["name"],
        qualified_name=definition["name"],
        kind="function",
        start_line=definition["start_line"],
        end_line=definition["end_line"],
        cyclomatic_complexity=1 + len(points),
        decision_points=points,
        peak_live_bindings=len(peak_names),
        peak_line=peak_line,
        peak_names=peak_names,
        live_method="backward_lexical_liveness_direct_body",
        live_limitations=[
            "does not model Lua branch or loop control flow",
            "excludes fields and globals",
            "excludes aliases and inter-procedural values",
            "only parses declarations, loop targets, and plain assignments",
        ],
    )


def _lua_structural_regions(lines: list[str], definition: dict[str, Any]) -> list[dict[str, Any]]:
    stack: list[dict[str, Any]] = []
    regions: list[dict[str, Any]] = []
    for number in range(definition["start_line"] + 1, definition["end_line"]):
        code = _strip_lua_comment(lines[number - 1])
        function_start = _lua_function_start(code)
        starts_function = function_start is not None
        stripped = code.strip()
        opens_block = bool(_lua_block_starts(code, starts_function))
        closes_block = bool(_LUA_END.search(code) or re.search(r"\b(?:else|elseif|until)\b", code))
        if stripped and not opens_block and not closes_block:
            regions.append({"kind": "statement", "start_line": number, "end_line": number})
        for kind in _lua_block_starts(code, starts_function):
            stack.append({"kind": kind, "start_line": number})
        if re.search(r"\buntil\b", code):
            for index in range(len(stack) - 1, -1, -1):
                if stack[index]["kind"] == "repeat":
                    region = stack.pop(index)
                    regions.append({**region, "end_line": number})
                    break
        for _ in _LUA_END.finditer(code):
            if not stack:
                break
            region = stack.pop()
            if region["kind"] != "function":
                regions.append({**region, "end_line": number})
    return regions


def _lua_region_metrics(
    lines: list[str], definition: dict[str, Any], start_line: int, end_line: int
) -> dict[str, Any]:
    parameter_match = _lua_function_start(_strip_lua_comment(lines[definition["start_line"] - 1]))
    parameters = set(parameter_match[1] if parameter_match else [])
    region_lines = [
        (number, _strip_lua_comment(lines[number - 1]))
        for number in range(start_line, end_line + 1)
    ]
    points: list[dict[str, Any]] = []
    bindings = set(parameters)
    for number, code in region_lines:
        if re.search(r"\bif\b.*\bthen\b", code):
            points.append({"kind": "if", "line": number})
        if re.search(r"\belseif\b.*\bthen\b", code):
            points.append({"kind": "elseif", "line": number})
        if re.search(r"\bfor\b.*\bdo\b", code):
            points.append({"kind": "for", "line": number})
        if re.search(r"\bwhile\b.*\bdo\b", code):
            points.append({"kind": "while", "line": number})
        if re.search(r"\brepeat\b", code):
            points.append({"kind": "repeat", "line": number})
        for _ in re.finditer(r"\b(?:and|or)\b", code):
            points.append({"kind": "boolean_short_circuit", "line": number})
        bindings.update(_lua_declared_bindings(code))

    live: set[str] = set()
    peak_line: int | None = None
    peak_names: list[str] = []
    for number, code in reversed(region_lines):
        reads, writes = _lua_line_accesses(code, bindings)
        live = reads | (live - writes)
        current = sorted(live)
        if len(current) > len(peak_names):
            peak_line = number
            peak_names = current
    return _metrics(
        cyclomatic_complexity=1 + len(points),
        decision_points=points,
        peak_live_bindings=len(peak_names),
        peak_line=peak_line,
        peak_names=peak_names,
        live_method="backward_lexical_liveness_direct_region",
        live_limitations=[
            "region analysis excludes values needed only after the selected range",
            "does not model Lua branch or loop control flow",
            "excludes fields, globals, aliases, and inter-procedural values",
            "only parses declarations, loop targets, and plain assignments",
        ],
    )


def _walk_tree_sitter(node: Any) -> Iterable[Any]:
    yield node
    for child in node.children:
        yield from _walk_tree_sitter(child)


def _tree_sitter_node_text(node: Any, source: bytes) -> str:
    return source[node.start_byte : node.end_byte].decode("utf-8", errors="replace")


def _tree_sitter_definition_name(node: Any, source: bytes) -> str:
    name_node = node.child_by_field_name("name")
    if name_node:
        return _tree_sitter_node_text(name_node, source)
    declarator = node.child_by_field_name("declarator")
    if declarator:
        for child in _walk_tree_sitter(declarator):
            if child.type in {"identifier", "field_identifier", "type_identifier"}:
                return _tree_sitter_node_text(child, source)
    for child in _walk_tree_sitter(node):
        if child is node:
            continue
        if child.type in {"identifier", "field_identifier"}:
            return _tree_sitter_node_text(child, source)
    return "<anonymous>"


def _tree_sitter_direct_nodes(node: Any, definition_types: set[str]) -> Iterable[Any]:
    for child in node.children:
        if child.type in definition_types:
            continue
        yield child
        yield from _tree_sitter_direct_nodes(child, definition_types)


def _tree_sitter_bindings(
    node: Any, source: bytes, binding_types: set[str], definition_types: set[str]
) -> set[str]:
    bindings: set[str] = set()
    for candidate in _tree_sitter_direct_nodes(node, definition_types):
        if candidate.type not in binding_types:
            continue
        for child in _walk_tree_sitter(candidate):
            if child.type == "identifier":
                bindings.add(_tree_sitter_node_text(child, source))
                break
    return bindings


def _tree_sitter_peak_liveness(
    node: Any, source: bytes, bindings: set[str]
) -> tuple[int, int | None, list[str]]:
    """Use backward local-token liveness when no language CFG adapter exists.

    The metric remains deterministic and excludes names that were not declared
    as local bindings by the language profile. It is deliberately labelled as
    a lower-bound approximation in the returned evidence.
    """
    if not bindings:
        return 0, None, []
    source_lines = _tree_sitter_node_text(node, source).splitlines()
    start_line = node.start_point[0] + 1
    live: set[str] = set()
    peak_line: int | None = None
    peak_names: list[str] = []
    identifier_re = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
    for offset in range(len(source_lines) - 1, -1, -1):
        line = source_lines[offset]
        names = {match.group(0) for match in identifier_re.finditer(line)} & bindings
        writes: set[str] = set()
        reads = set(names)
        for name in names:
            assignment = re.search(rf"\b{re.escape(name)}\b\s*([+\-*/%]?=)", line)
            if assignment:
                writes.add(name)
                if assignment.group(1) == "=":
                    reads.discard(name)
        live = reads | (live - writes)
        if len(live) > len(peak_names):
            peak_line = start_line + offset
            peak_names = sorted(live)
    return len(peak_names), peak_line, peak_names


def _tree_sitter_definitions(
    text: str, language: str, path: str, profile: dict[str, Any]
) -> tuple[list[dict[str, Any]], str | None]:
    try:
        from tree_sitter import Language, Parser

        grammar = importlib.import_module(profile["grammar_module"])
    except (ImportError, KeyError) as error:
        return [], f"pinned Tree-sitter dependency is unavailable: {error}"

    try:
        grammar_symbol = profile.get("grammar_symbol_by_extension", {}).get(
            Path(path).suffix.lower(), profile.get("grammar_symbol", "language")
        )
        parser_language = Language(getattr(grammar, grammar_symbol)())
        try:
            parser = Parser(parser_language)
        except TypeError:
            parser = Parser()
            parser.language = parser_language
        source = text.encode("utf-8")
        tree = parser.parse(source)
    except Exception as error:  # Tree-sitter bindings expose implementation-specific exceptions.
        return [], f"Tree-sitter parse failed: {error}"

    definition_types = set(profile["definition_nodes"])
    decision_types = set(profile["decision_nodes"])
    binding_types = set(profile["binding_nodes"])
    definitions: list[dict[str, Any]] = []
    for node in _walk_tree_sitter(tree.root_node):
        if node.type not in definition_types:
            continue
        decisions: list[dict[str, Any]] = []
        for candidate in _tree_sitter_direct_nodes(node, definition_types):
            if candidate.type not in decision_types:
                continue
            if candidate.type == "binary_expression":
                count = len(re.findall(r"&&|\|\|", _tree_sitter_node_text(candidate, source)))
                for _ in range(count):
                    decisions.append({"kind": "boolean_short_circuit", "line": candidate.start_point[0] + 1})
            else:
                decisions.append({"kind": candidate.type, "line": candidate.start_point[0] + 1})
        bindings = _tree_sitter_bindings(node, source, binding_types, definition_types)
        peak_count, peak_line, peak_names = _tree_sitter_peak_liveness(node, source, bindings)
        name = _tree_sitter_definition_name(node, source)
        definitions.append(
            _definition(
                language=language,
                name=name,
                qualified_name=name,
                kind=node.type,
                start_line=node.start_point[0] + 1,
                end_line=node.end_point[0] + 1,
                cyclomatic_complexity=1 + len(decisions),
                decision_points=decisions,
                peak_live_bindings=peak_count,
                peak_line=peak_line,
                peak_names=peak_names,
                live_method="backward_token_liveness_profiled_bindings",
                live_limitations=[
                    "path-insensitive token liveness can overapproximate concurrent values",
                    "binding extraction is grammar-profile based",
                    "excludes fields, globals, aliases, and inter-procedural values",
                ],
            )
        )
    return definitions, None


def _tree_sitter_region_metrics(
    text: str,
    language: str,
    path: str,
    profile: dict[str, Any],
    definition: dict[str, Any],
    start_line: int,
    end_line: int,
) -> dict[str, Any] | None:
    try:
        from tree_sitter import Language, Parser

        grammar = importlib.import_module(profile["grammar_module"])
        grammar_symbol = profile.get("grammar_symbol_by_extension", {}).get(
            Path(path).suffix.lower(), profile.get("grammar_symbol", "language")
        )
        parser_language = Language(getattr(grammar, grammar_symbol)())
        try:
            parser = Parser(parser_language)
        except TypeError:
            parser = Parser()
            parser.language = parser_language
        source = text.encode("utf-8")
        tree = parser.parse(source)
    except Exception:
        return None

    definition_types = set(profile["definition_nodes"])
    region_types = set(profile.get("region_nodes", []))
    owner = next(
        (
            node
            for node in _walk_tree_sitter(tree.root_node)
            if node.type == definition["kind"]
            and node.start_point[0] + 1 == definition["start_line"]
            and node.end_point[0] + 1 == definition["end_line"]
        ),
        None,
    )
    if owner is None:
        return None

    def walk_region_nodes(node: Any) -> Iterable[Any]:
        for child in node.children:
            if child.type in definition_types:
                continue
            yield child
            yield from walk_region_nodes(child)

    candidates = [
        node
        for node in walk_region_nodes(owner)
        if node.type in region_types
        and node.start_point[0] + 1 == start_line
        and node.end_point[0] + 1 == end_line
    ]
    if not candidates:
        return None
    region = min(candidates, key=lambda node: (node.end_byte - node.start_byte, node.start_byte))
    decision_types = set(profile["decision_nodes"])
    decisions: list[dict[str, Any]] = []
    for candidate in _tree_sitter_direct_nodes(region, definition_types):
        if candidate.type not in decision_types:
            continue
        if candidate.type == "binary_expression":
            count = len(re.findall(r"&&|\|\|", _tree_sitter_node_text(candidate, source)))
            for _ in range(count):
                decisions.append({"kind": "boolean_short_circuit", "line": candidate.start_point[0] + 1})
        else:
            decisions.append({"kind": candidate.type, "line": candidate.start_point[0] + 1})
    bindings = _tree_sitter_bindings(owner, source, set(profile["binding_nodes"]), definition_types)
    peak_count, peak_line, peak_names = _tree_sitter_peak_liveness(region, source, bindings)
    return _metrics(
        cyclomatic_complexity=1 + len(decisions),
        decision_points=decisions,
        peak_live_bindings=peak_count,
        peak_line=peak_line,
        peak_names=peak_names,
        live_method="backward_token_liveness_profiled_bindings_region",
        live_limitations=[
            "region analysis excludes values needed only after the selected range",
            "path-insensitive token liveness can overapproximate concurrent values",
            "binding extraction is grammar-profile based",
            "excludes fields, globals, aliases, and inter-procedural values",
        ],
    )


def analyze_text(text: str, language: str | None = None, path: str | Path = "<memory>") -> dict[str, Any]:
    """Analyze source text and return a ``code-reader-static-metrics/v1`` document.

    ``language`` may be a registered language, an alias such as ``py``, or
    ``auto``/``None`` to infer from ``path``.
    """
    path_text = str(path)
    normalized_language = _normalize_language(language, path_text)
    profiles = load_profiles()
    profile = profiles.get(normalized_language or "")
    if profile is None:
        return _result(
            path=path_text,
            language=normalized_language,
            status=NOT_AVAILABLE,
            backend="unavailable",
            reason="no static-analysis profile is registered for this language",
        )

    backend = profile["backend"]
    if backend == "unavailable":
        return _result(
            path=path_text,
            language=normalized_language,
            status=NOT_AVAILABLE,
            backend=backend,
            reason="the profile is registered but no pinned parser adapter is installed",
        )

    try:
        if normalized_language == "python":
            definitions = _python_definitions(text)
        elif normalized_language == "lua":
            definitions, lua_error = _lua_definitions(text)
            if lua_error:
                return _result(
                    path=path_text,
                    language=normalized_language,
                    status=PARSE_ERROR,
                    backend=backend,
                    reason=lua_error,
                )
        elif backend == "tree-sitter-v1":
            definitions, tree_sitter_error = _tree_sitter_definitions(
                text, normalized_language or "unknown", path_text, profile
            )
            if tree_sitter_error:
                return _result(
                    path=path_text,
                    language=normalized_language,
                    status=NOT_AVAILABLE,
                    backend=backend,
                    reason=tree_sitter_error,
                )
        else:  # Guard against an accidentally added available profile without an adapter.
            return _result(
                path=path_text,
                language=normalized_language,
                status=NOT_AVAILABLE,
                backend=backend,
                reason="the profile has no implementation in static_metrics.py",
            )
    except (SyntaxError, IndentationError) as error:
        return _result(
            path=path_text,
            language=normalized_language,
            status=PARSE_ERROR,
            backend=backend,
            reason=f"{error.__class__.__name__}: {error}",
        )

    return _result(
        path=path_text,
        language=normalized_language,
        status=SUPPORTED,
        backend=backend,
        definitions=definitions,
    )


def analyze_range_text(
    text: str,
    language: str | None,
    path: str | Path,
    start_line: int,
    end_line: int | None = None,
) -> dict[str, Any]:
    """Analyze a whole definition or a complete structural subregion.

    The function never substitutes an enclosing definition's metrics for a
    non-structural partial selection. Callers use ``fallback_required`` to
    request the semantic reviewer when static analysis cannot establish the
    region safely.
    """
    end_line = start_line if end_line is None else end_line
    analysis = analyze_text(text, language=language, path=path)
    if analysis.get("status") != SUPPORTED:
        reason_code = "PARSE_ERROR" if analysis.get("status") == PARSE_ERROR else "ANALYZER_UNAVAILABLE"
        return _range_result(
            analysis,
            start_line,
            end_line,
            status=analysis.get("status", NOT_AVAILABLE),
            reason_code=reason_code,
            reason=analysis.get("reason", "static analysis is unavailable"),
        )
    definition = select_definition_for_range(analysis, start_line, end_line)
    if not definition:
        return _range_result(
            analysis,
            start_line,
            end_line,
            status=NOT_AVAILABLE,
            reason_code="DEFINITION_NOT_FOUND",
            reason="source range is not fully contained in a single supported definition",
        )
    region_range = _trim_non_code_range(text, start_line, end_line)
    if region_range is None:
        return _range_result(
            analysis,
            start_line,
            end_line,
            status=NOT_AVAILABLE,
            definition=definition,
            reason_code="NON_SESE_RANGE",
            reason="source range has no executable structural region",
        )
    region_start, region_end = region_range
    if region_start == definition["start_line"] and region_end == definition["end_line"]:
        return _range_result(
            analysis,
            start_line,
            end_line,
            status=SUPPORTED,
            definition=definition,
            metrics=definition["metrics"],
            analysis_region={
                "kind": "definition",
                "name": definition["name"],
                "path": str(path),
                "start_line": definition["start_line"],
                "end_line": definition["end_line"],
                "definition": _definition_identity(definition),
            },
        )

    normalized_language = analysis.get("language")
    metrics: dict[str, Any] | None = None
    if normalized_language == "python":
        node = _python_function_nodes(text).get(definition["id"])
        statements = _python_region_statements(node, region_start, region_end) if node else None
        if statements and node:
            metrics = _python_region_metrics(node, statements)
    elif normalized_language == "lua":
        lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        owner = {
            "start_line": definition["start_line"],
            "end_line": definition["end_line"],
        }
        if any(
            region["start_line"] == region_start and region["end_line"] == region_end
            for region in _lua_structural_regions(lines, owner)
        ):
            metrics = _lua_region_metrics(lines, owner, region_start, region_end)
    else:
        profile = load_profiles().get(normalized_language or "")
        if profile and profile.get("backend") == "tree-sitter-v1":
            metrics = _tree_sitter_region_metrics(
                text, normalized_language or "unknown", str(path), profile, definition, region_start, region_end
            )
    if metrics is None:
        return _range_result(
            analysis,
            start_line,
            end_line,
            status=NOT_AVAILABLE,
            definition=definition,
            reason_code="NON_SESE_RANGE",
            reason="source range does not match a complete structural subregion",
        )
    return _range_result(
        analysis,
        start_line,
        end_line,
        status=SUPPORTED,
        definition=definition,
        metrics=metrics,
        analysis_region={
            "kind": "sese_region",
            "name": f"{definition['name']}:L{region_start}-L{region_end}",
            "path": str(path),
            "start_line": region_start,
            "end_line": region_end,
            "definition": _definition_identity(definition),
        },
    )


def analyze_path(path: str | Path, language: str | None = None) -> dict[str, Any]:
    """Read a UTF-8 source file and delegate to :func:`analyze_text`."""
    source_path = Path(path)
    try:
        text = source_path.read_text(encoding="utf-8")
    except OSError as error:
        return _result(
            path=str(source_path),
            language=_normalize_language(language, source_path),
            status=PARSE_ERROR,
            backend="unavailable",
            reason=f"cannot read source: {error}",
        )
    return analyze_text(text, language=language, path=source_path)


def select_definition_for_range(
    analysis: dict[str, Any], start_line: int, end_line: int | None = None
) -> dict[str, Any] | None:
    """Return the smallest definition fully containing the inclusive range.

    The function deliberately returns ``None`` for sibling or top-level ranges;
    callers can then enforce the one-definition-per-page policy themselves.
    """
    end_line = start_line if end_line is None else end_line
    if start_line < 1 or end_line < start_line or analysis.get("status") != SUPPORTED:
        return None
    candidates = [
        definition
        for definition in analysis.get("definitions", [])
        if definition["start_line"] <= start_line and end_line <= definition["end_line"]
    ]
    if not candidates:
        return None
    return min(candidates, key=lambda item: (item["end_line"] - item["start_line"], item["start_line"]))


def _parse_range(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"L?(\d+)(?:-L?(\d+))?", value)
    if not match:
        raise argparse.ArgumentTypeError("range must look like L12-L34")
    start = int(match.group(1))
    end = int(match.group(2) or match.group(1))
    if end < start:
        raise argparse.ArgumentTypeError("range end must not precede range start")
    return start, end


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Collect deterministic Code Reader static metrics.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--path", help="UTF-8 source file to analyze")
    source.add_argument("--text", help="source text to analyze directly")
    parser.add_argument("--language", default="auto", help="registered language or auto (default)")
    parser.add_argument("--virtual-path", default="<memory>", help="path used with --text for language detection")
    parser.add_argument("--range", dest="source_range", type=_parse_range, help="inclusive page range, for definition selection")
    arguments = parser.parse_args(argv)

    if arguments.path:
        result = analyze_path(arguments.path, language=arguments.language)
    else:
        result = analyze_text(arguments.text, language=arguments.language, path=arguments.virtual_path)
    if arguments.source_range:
        start, end = arguments.source_range
        source_text = Path(arguments.path).read_text(encoding="utf-8") if arguments.path else arguments.text
        range_analysis = analyze_range_text(
            source_text,
            arguments.language,
            arguments.path or arguments.virtual_path,
            start,
            end,
        )
        result["selection"] = {
            "start_line": start,
            "end_line": end,
            "definition": select_definition_for_range(result, start, end),
        }
        result["range_analysis"] = range_analysis
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
