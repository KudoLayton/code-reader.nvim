from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

import validate_code_reader_markdown


class ValidateCodeReaderMarkdownTests(unittest.TestCase):
    def test_source_page_with_one_range_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path = root / "src" / "example.py"
            source_path.parent.mkdir()
            source_path.write_text("def parse_request():\n    return True\n", encoding="utf-8")
            markdown_path = root / "walkthrough.md"
            markdown_path.write_text(
                "\n".join(
                    [
                        "---",
                        "type: code-reader",
                        "version: 1",
                        "---",
                        "<!-- code-reader: front-page -->",
                        "# Overview",
                        "---",
                        "# 1. Parse request",
                        "Source: src/example.py#L1-L2",
                    ]
                ),
                encoding="utf-8",
            )

            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)

            self.assertEqual(errors, [])

    def test_diff_page_with_multiple_ranges_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            markdown_path = root / "walkthrough.md"
            diff_path = root / "change.diff"
            diff_path.write_text(
                "\n".join(
                    [
                        "diff --git a/src/example.py b/src/example.py",
                        "index 1111111..2222222 100644",
                        "--- a/src/example.py",
                        "+++ b/src/example.py",
                        "@@ -1 +1 @@",
                        "-return 1",
                        "+return 2",
                        "@@ -3 +3 @@",
                        "-return 3",
                        "+return 4",
                    ]
                ),
                encoding="utf-8",
            )
            markdown_path.write_text(
                "\n".join(
                    [
                        "---",
                        "type: code-reader-diff",
                        "version: 1",
                        "diff: ./change.diff",
                        "---",
                        "<!-- code-reader: front-page -->",
                        "# Overview",
                        "---",
                        "# 1. Explain both changes",
                        "Diff: src/example.py#H1",
                        "Diff: src/example.py#H2",
                    ]
                ),
                encoding="utf-8",
            )

            errors = validate_code_reader_markdown.validate_doc(root, markdown_path, False)

            self.assertIn("section starting at line 9 must contain exactly one Diff directive", errors)


if __name__ == "__main__":
    unittest.main()
