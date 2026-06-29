---
name: write-diff-explanation
description: "Create or revise code-reader.nvim diff explanation markdown files. Use when Codex needs to explain a unified diff or patch using `type: code-reader-diff` markdown with a diff front page, `diff: ./change.diff`, file-local `Diff: path#Hn` hunk references, and hunk coverage validation."
---

# Write Diff Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

## Workflow

1. Inspect the unified diff before writing prose.
2. Identify files, file-local hunk ids, changed behavior, and review order.
3. Draft a `type: code-reader-diff` markdown file with a front page and numbered hunk explanation steps.
4. Put `Diff: path#Hn` on every concrete step.
5. Cover every hunk unless the user explicitly asks for a partial explanation.
6. Run the shared validator and fix every reported issue before finishing.

## Output Defaults

- Store new diff explanations and their `.diff` file together under `.code_reader/diffs/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep each step focused on the referenced hunk's purpose and behavioral impact.
- Do not guess hunk ids. Parse the diff and use file-local `H1`, `H2`, and so on.
