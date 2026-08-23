from __future__ import annotations

import sys
import tempfile
import unittest
import json
from pathlib import Path
from unittest.mock import patch


SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

import bootstrap_static_analysis
import validate_code_reader_markdown


def source_walkthrough(source_target: str = "src/example.py#L1-L2") -> str:
    return "\n".join(
        [
            "---", "type: code-reader", "version: 2", "feature: request-flow", "---",
            "# Overview", "```code-reader", "kind: overview", "id: request-flow",
            "question: What completes the request flow?", "state:", "  status: not_applicable",
            "  reason: Overview is descriptive.", "responsibility:", "  status: applicable",
            "  items:", "    - owner: app.handle", "      action: Coordinate the lifecycle", "```",
            "---", "# 1. Parse request", "```code-reader", "kind: stage", "id: parse-request",
            "question: How does raw input become a request?", "trigger: app.handle receives raw input",
            "state:", "  status: applicable", "  changes:", "    - subject: request",
            "      owner: request.parse_request", "      before: raw", "      cause: parsing succeeds",
            "      after: decoded", "      invariant: decoded request has defaults", "responsibility:",
            "  status: applicable", "  items:", "    - owner: request.parse_request",
            "      action: Normalize optional fields", "failure:", "  status: not_applicable",
            "  reason: Parsing always supplies defaults.", "evidence:", "  - id: 1", "    kind: source",
            f"    target: {source_target}", "    claim: The parser creates the decoded request.", "```",
            "The parser performs the transition [1](code-reader://evidence/1).",
        ]
    )


def execution_map_walkthrough() -> str:
    return "\n".join(
        [
            "---", "type: code-reader", "version: 2", "feature: request-flow", "---",
            "# Overview", "```code-reader", "kind: overview", "id: request-flow",
            "question: What completes the request flow?", "state:", "  status: not_applicable",
            "  reason: Overview is descriptive.", "responsibility:", "  status: applicable",
            "  items:", "    - owner: app.handle", "      action: Coordinate the lifecycle", "evidence:",
            "  - id: 1", "    kind: sketch", "    purpose: execution-map", "    target: .code_reader/assets/flow.svg",
            "    editable_target: .code_reader/assets/flow.excalidraw", "    claim: The map covers the feature lifecycle.",
            "    coverage:", "      - parse-request", "    text_model:", "      claim: The request crosses the lifecycle.",
            "      nodes:", "        - id: raw", "          owner: app.handle", "          state: raw",
            "        - id: parsed", "          owner: request.parse_request", "          state: parsed",
            "      edges:", "        - id: parse", "          from: raw", "          to: parsed", "          label: parse", "```",
            "The execution map is [1](code-reader://evidence/1).", "---", "# 1. Parse request", "```code-reader",
            "kind: stage", "id: parse-request", "map_anchor:", "  map: 1", "  nodes:", "    - parsed", "  edges:", "    - parse",
            "question: How does raw input become a request?",
            "trigger: app.handle receives raw input", "state:", "  status: applicable", "  changes:",
            "    - subject: request", "      owner: request.parse_request", "      before: raw", "      cause: parsing succeeds",
            "      after: decoded", "      invariant: decoded request has defaults", "responsibility:",
            "  status: applicable", "  items:", "    - owner: request.parse_request", "      action: Normalize optional fields",
            "failure:", "  status: not_applicable", "  reason: Parsing always supplies defaults.", "evidence:",
            "  - id: 1", "    kind: source", "    target: src/example.py#L1-L2", "    claim: The parser creates the decoded request.",
            "```", "The parser performs the transition [1](code-reader://evidence/1).",
        ]
    )


def scope_review_walkthrough(
    diagnoses: list[str] | None = None,
    page_decision: str = "retain",
    hierarchy: str = "none",
    include_model: bool = False,
    child_parent: str | None = None,
) -> str:
    diagnoses = diagnoses or ["implementation_complexity"]
    second_stage = "normalize-default" if page_decision == "split" else "normalize-request"
    second_evidence = 1 if page_decision == "split" else 2
    review_lines = [
        "scope_reviews:",
        "  - id: request-normalization",
        "    signal: multiple_scopes",
        "    members:",
        "      - stage: normalize-request",
        "        evidence: 1",
        f"      - stage: {second_stage}",
        f"        evidence: {second_evidence}",
        "    diagnoses:",
    ]
    review_lines.extend(f"      - {diagnosis}" for diagnosis in diagnoses)
    review_lines.extend(
        [
            f"    page_decision: {page_decision}",
            f"    hierarchy: {hierarchy}",
            "    rationale: The two ranges implement one normalization responsibility.",
        ]
    )
    model_lines = []
    if include_model:
        model_lines = [
            "---", "# Request normalization model", "```code-reader", "kind: model", "id: request-normalization-model",
            "question: How do the normalization steps jointly establish a request?", "state:", "  status: not_applicable",
            "  reason: The model summarizes its children.", "responsibility:", "  status: applicable", "  items:",
            "    - owner: request.normalize", "      action: Establish a normalized request contract", "hierarchy:",
            "  contract: The request has canonical fields before dispatch.",
            "  decomposition: Parsing and defaults are explained separately because each has a local rule.", "```",
            "The child stages establish the shared contract.",
        ]
    parent_lines = [f"parent: {child_parent}"] if child_parent else []
    stage_evidence = [
        "  - id: 1", "    kind: source", "    target: src/example.py#L1-L2", "    claim: The first range parses the required field.",
    ]
    followup_stage = []
    if page_decision == "split":
        followup_stage = [
            "---", "# 2. Supply defaults", "```code-reader", "kind: stage", "id: normalize-default", *parent_lines,
            "question: How are optional fields defaulted?", "trigger: Parsing leaves an optional field absent", "state:",
            "  status: applicable", "  changes:", "    - subject: request", "      owner: request.normalize",
            "      before: parsed", "      cause: defaulting runs", "      after: normalized",
            "      invariant: optional fields have canonical values", "responsibility:", "  status: applicable", "  items:",
            "    - owner: request.normalize", "      action: Supply the optional default", "failure:",
            "  status: not_applicable", "  reason: The example default always applies.", "evidence:",
            "  - id: 1", "    kind: source", "    target: src/example.py#L4-L5", "    claim: The range supplies the optional default.", "```",
            "The defaulting operation is [1](code-reader://evidence/1).",
        ]
    else:
        stage_evidence.extend(
            ["  - id: 2", "    kind: source", "    target: src/example.py#L4-L5", "    claim: The second range supplies the optional default."]
        )
    return "\n".join(
        [
            "---", "type: code-reader", "version: 2", "feature: request-normalization", "---",
            "# Overview", "```code-reader", "kind: overview", "id: request-normalization",
            "question: How is the request normalized?", "state:", "  status: not_applicable",
            "  reason: The overview is descriptive.", "responsibility:", "  status: applicable", "  items:",
            "    - owner: app.handle", "      action: Coordinate request normalization", *review_lines, "```",
            "The overview records why its source scopes share one explanation page.", *model_lines,
            "---", "# 1. Normalize request", "```code-reader", "kind: stage", "id: normalize-request", *parent_lines,
            "question: How are request fields normalized?", "trigger: app.handle receives a request", "state:",
            "  status: applicable", "  changes:", "    - subject: request", "      owner: request.normalize",
            "      before: raw", "      cause: normalization runs", "      after: normalized",
            "      invariant: required fields have canonical values", "responsibility:", "  status: applicable", "  items:",
            "    - owner: request.normalize", "      action: Parse the required field", "failure:",
            "  status: not_applicable", "  reason: The example always supplies valid input.", "evidence:", *stage_evidence, "```",
            "The first operation is [1](code-reader://evidence/1).",
            *( ["The default operation is [2](code-reader://evidence/2)."] if page_decision == "retain" else [] ),
            *followup_stage,
        ]
    )


class ValidateCodeReaderMarkdownTests(unittest.TestCase):
    def test_state_changes_require_atomic_complete_cards(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            valid = source_walkthrough()
            change_block = "\n".join(
                [
                    "  changes:",
                    "    - subject: request",
                    "      owner: request.parse_request",
                    "      before: raw",
                    "      cause: parsing succeeds",
                    "      after: decoded",
                    "      invariant: decoded request has defaults",
                ]
            )

            multiple_cards = valid.replace(
                change_block,
                "\n".join(
                    [
                        change_block,
                        "    - subject: validation_cache",
                        "      owner: cache.store",
                        "      before: empty",
                        "      cause: validation result is stored",
                        "      after: populated",
                        "      invariant: entries belong to the current request",
                    ]
                ),
            )
            markdown_path.write_text(multiple_cards, encoding="utf-8")
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])

            for replacement, expected in (
                ("  changes: []", "state.changes must be a non-empty list"),
                ("  changes: request", "state.changes must be a non-empty list"),
                ("  status: applicable", "state.changes must be a non-empty list"),
            ):
                markdown_path.write_text(valid.replace(change_block, replacement), encoding="utf-8")
                errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
                self.assertTrue(any(expected in error for error in errors), replacement)

            for field, value in (
                ("subject", "request"),
                ("owner", "request.parse_request"),
                ("before", "raw"),
                ("cause", "parsing succeeds"),
                ("after", "decoded"),
                ("invariant", "decoded request has defaults"),
            ):
                field_line = (
                    f"    - {field}: {value}\n"
                    if field == "subject"
                    else f"      {field}: {value}\n"
                )
                replacement = "    - ignored: ignored\n" if field == "subject" else ""
                markdown_path.write_text(
                    valid.replace(field_line, replacement), encoding="utf-8"
                )
                errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
                self.assertTrue(
                    any(f"state change 1 must set {field}" in error for error in errors),
                    f"{field}: {errors}",
                )

            for field, value in (
                ("subject", "request and validation_cache"),
                ("subject", "요청과 캐시"),
                ("subject", "request와validation_cache"),
                ("owner", "request.parse_request and cache.store"),
            ):
                field_prefix = "    - subject: request" if field == "subject" else "      owner: request.parse_request"
                replacement = f"    - subject: {value}" if field == "subject" else f"      owner: {value}"
                markdown_path.write_text(
                    valid.replace(field_prefix, replacement),
                    encoding="utf-8",
                )
                errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
                self.assertTrue(any(f"state change 1 {field} must name one" in error for error in errors), value)

            aggregate_state = valid.replace("      before: raw", "      before: raw fields, mode unset").replace(
                "      after: decoded", "      after: decoded and normalized"
            )
            markdown_path.write_text(aggregate_state, encoding="utf-8")
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])

    def test_unregistered_language_preserves_provision_required_status(self) -> None:
        with patch.object(
            bootstrap_static_analysis,
            "ensure",
            return_value={"status": "PROVISION_REQUIRED", "reason": "profile approval is required"},
        ):
            result = validate_code_reader_markdown.analyze_source_scope(
                "src/example.kt", "fun main() = Unit\n", 1, 1
            )
        self.assertEqual(result["status"], "PROVISION_REQUIRED")

    def test_v2_stage_validates_evidence_links_and_models(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(source_walkthrough(), encoding="utf-8")
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])

    def test_v2_rejects_unreferenced_or_nonconsecutive_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(source_walkthrough().replace("  - id: 1", "  - id: 2"), encoding="utf-8")
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("consecutive" in error for error in errors))
            self.assertTrue(any("unknown evidence" in error for error in errors))

    def test_v2_sketch_requires_svg_and_editable_excalidraw_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                source_walkthrough().replace(
                    "    claim: The parser creates the decoded request.",
                    "    claim: The parser creates the decoded request.\n"
                    "  - id: 2\n"
                    "    kind: sketch\n"
                    "    target: .code_reader/assets/flow.svg\n"
                    "    editable_target: .code_reader/assets/flow.excalidraw\n"
                    "    claim: The sketch shows the ownership handoff.\n"
                    "    text_model:\n"
                    "      claim: The parser owns the decoded request.\n"
                    "      nodes:\n"
                    "        - id: raw\n"
                    "          owner: app.handle\n"
                    "          state: raw\n"
                    "        - id: decoded\n"
                    "          owner: request.parse_request\n"
                    "          state: decoded\n"
                    "      edges:\n"
                    "        - from: raw\n"
                    "          to: decoded\n"
                    "          label: parse"
                ).replace(
                    "The parser performs the transition [1](code-reader://evidence/1).",
                    "The parser performs the transition [1](code-reader://evidence/1).\n"
                    "The ownership handoff is [2](code-reader://evidence/2).",
                ),
                encoding="utf-8",
            )
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])
            (asset_directory / "flow.excalidraw").write_text("{}", encoding="utf-8")
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("editable sketch asset" in error for error in errors))

    def test_execution_map_requires_complete_stage_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(execution_map_walkthrough(), encoding="utf-8")
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])
            markdown_path.write_text(execution_map_walkthrough().replace("- parse-request", "- missing-stage", 1), encoding="utf-8")
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("coverage has unknown" in error for error in errors))
            self.assertTrue(any("coverage misses" in error for error in errors))

    def test_execution_map_inventory_is_json_serializable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(execution_map_walkthrough(), encoding="utf-8")

            errors, inventory = validate_code_reader_markdown.build_inventory(root, markdown_path, False)

            self.assertEqual(errors, [])
            json.dumps(inventory)

    def test_execution_map_requires_a_resolvable_stage_anchor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                execution_map_walkthrough().replace(
                    "id: parse-request\nmap_anchor:\n  map: 1\n  nodes:\n    - parsed\n  edges:\n    - parse\n",
                    "id: parse-request\n",
                ),
                encoding="utf-8",
            )
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("needs map_anchor" in error for error in errors))

    def test_execution_map_infers_an_exact_stage_node_anchor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                execution_map_walkthrough()
                .replace("parse-request", "parsed")
                .replace(
                    "map_anchor:\n  map: 1\n  nodes:\n    - parsed\n  edges:\n    - parse\n",
                    "",
                ),
                encoding="utf-8",
            )
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])

    def test_execution_map_rejects_unknown_anchor_members(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                execution_map_walkthrough().replace(
                    "map_anchor:\n  map: 1\n  nodes:\n    - parsed\n  edges:",
                    "map_anchor:\n  map: 1\n  nodes:\n    - missing-node\n  edges:",
                ),
                encoding="utf-8",
            )
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("unknown node ids" in error for error in errors))

    def test_execution_map_rejects_unknown_anchor_edges(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            asset_directory = root / ".code_reader" / "assets"
            asset_directory.mkdir(parents=True)
            (asset_directory / "flow.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
            (asset_directory / "flow.excalidraw").write_text(
                '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}', encoding="utf-8"
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                execution_map_walkthrough().replace(
                    "  edges:\n    - parse\nquestion:",
                    "  edges:\n    - missing-edge\nquestion:",
                ),
                encoding="utf-8",
            )
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertTrue(any("unknown edge ids" in error for error in errors))

    def test_v1_document_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text("\n".join(["---", "type: code-reader", "version: 1", "---", "# Legacy"]), encoding="utf-8")
            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
            self.assertIn("frontmatter field `version` must be `2`", errors)

    def test_diff_stage_can_cover_multiple_hunks_with_numbered_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            diff_path = root / "change.diff"
            diff_path.write_text(
                "\n".join([
                    "diff --git a/src/example.py b/src/example.py", "--- a/src/example.py", "+++ b/src/example.py",
                    "@@ -1 +1 @@", "-return 1", "+return 2", "@@ -3 +3 @@", "-return 3", "+return 4",
                ]),
                encoding="utf-8",
            )
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                "\n".join([
                    "---", "type: code-reader-diff", "version: 2", "feature: changed-return-values", "diff: ./change.diff", "---",
                    "# Overview", "```code-reader", "kind: overview", "id: changed-return-values",
                    "question: How does the patch change returned values?", "state:", "  status: not_applicable",
                    "  reason: Overview is descriptive.", "responsibility:", "  status: applicable", "  items:",
                    "    - owner: example.py", "      action: Return the changed values", "scope_reviews:",
                    "  - id: changed-returns", "    signal: multiple_scopes", "    members:",
                    "      - stage: change-returns", "        evidence: 1", "      - stage: change-returns", "        evidence: 2",
                    "    diagnoses:", "      - implementation_complexity", "    page_decision: retain", "    hierarchy: none",
                    "    rationale: Both hunks apply the same return-value rule.", "```", "---", "# 1. Change returns",
                    "```code-reader", "kind: stage", "id: change-returns", "question: Which returns change?",
                    "trigger: The revised code path executes", "state:", "  status: applicable", "  changes:",
                    "    - subject: return value", "      owner: example.py", "      before: old value", "      cause: patch applies",
                    "      after: new value", "      invariant: both changed returns are covered", "responsibility:",
                    "  status: applicable", "  items:", "    - owner: example.py", "      action: Return updated values",
                    "failure:", "  status: not_applicable", "  reason: The diff only changes values.", "evidence:",
                    "  - id: 1", "    kind: diff", "    target: src/example.py#H1", "    claim: The first return changes.",
                    "  - id: 2", "    kind: diff", "    target: src/example.py#H2", "    claim: The second return changes.", "```",
                    "The first hunk is [1](code-reader://evidence/1).", "The second hunk is [2](code-reader://evidence/2).",
                ]),
                encoding="utf-8",
            )
            self.assertEqual(validate_code_reader_markdown.validate_doc(root, markdown_path, False), [])

    def test_scope_review_allows_implementation_complexity_to_remain_on_one_page(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse():\n    return 'parsed'\n\ndef defaults():\n    return 'default'\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(scope_review_walkthrough(), encoding="utf-8")

            errors, inventory = validate_code_reader_markdown.build_inventory(root, markdown_path, False)

            self.assertEqual(errors, [])
            self.assertEqual(inventory["scope_reviews"][0]["page_decision"], "retain")
            self.assertEqual(inventory["pages"][1]["scope_review_ids"], ["request-normalization"])

    def test_scope_review_requires_a_page_split_for_model_gap_or_explanation_overload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse():\n    return 'parsed'\n\ndef defaults():\n    return 'default'\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            for diagnosis in ("model_gap", "explanation_overload"):
                markdown_path.write_text(scope_review_walkthrough([diagnosis]), encoding="utf-8")
                errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)
                self.assertTrue(any(f"{diagnosis} requires page_decision: split" in error for error in errors))

    def test_hierarchical_scope_review_requires_an_explicit_model_parent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse():\n    return 'parsed'\n\ndef defaults():\n    return 'default'\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                scope_review_walkthrough(
                    diagnoses=["model_gap"],
                    page_decision="split",
                    hierarchy="request-normalization-model",
                    include_model=True,
                    child_parent="request-normalization-model",
                ),
                encoding="utf-8",
            )

            errors, inventory = validate_code_reader_markdown.build_inventory(root, markdown_path, False)

            self.assertEqual(errors, [])
            self.assertEqual(inventory["pages"][1]["children"], ["normalize-request", "normalize-default"])
            self.assertEqual(inventory["pages"][2]["parent"], "request-normalization-model")

    def test_hierarchical_model_requires_contract_decomposition_and_multiple_children(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse():\n    return 'parsed'\n\ndef defaults():\n    return 'default'\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                scope_review_walkthrough(
                    diagnoses=["model_gap"],
                    page_decision="split",
                    hierarchy="request-normalization-model",
                    include_model=True,
                    child_parent="request-normalization-model",
                )
                .replace("  contract: The request has canonical fields before dispatch.\n", "")
                .replace("  decomposition: Parsing and defaults are explained separately because each has a local rule.\n", "")
                .replace("id: normalize-default\nparent: request-normalization-model\n", "id: normalize-default\n"),
                encoding="utf-8",
            )

            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)

            self.assertTrue(any("hierarchy.contract" in error for error in errors))
            self.assertTrue(any("hierarchy.decomposition" in error for error in errors))
            self.assertTrue(any("at least two children" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
