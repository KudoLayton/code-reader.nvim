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


class ValidateCodeReaderMarkdownTests(unittest.TestCase):
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
                    "    - owner: example.py", "      action: Return the changed values", "```", "---", "# 1. Change returns",
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


if __name__ == "__main__":
    unittest.main()
