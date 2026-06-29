---
name: write-diff-explanation
description: "Create or revise code-reader.nvim diff explanation markdown files. Use when Codex needs to explain a unified diff or patch using `type: code-reader-diff` markdown with a diff front page, `diff: ./change.diff`, file-local `Diff: path#Hn` hunk references, optional side-specific partial ranges such as `@new:L10-L20` or `@new:padding=2`, and hunk coverage validation."
---

# Write Diff Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

## Workflow

1. Inspect the unified diff before writing prose.
2. Identify files, file-local hunk ids, changed behavior, and review order.
3. Draft a `type: code-reader-diff` markdown file with a front page and numbered hunk explanation steps.
4. Put `Diff: path#Hn` or a side-specific range reference on every concrete step.
5. Split large hunks, whole-file additions, or dense rewrites into multiple focused range steps.
6. Cover every hunk unless the user explicitly asks for a partial explanation.
7. Run the shared validator and fix every reported issue before finishing.

## Output Defaults

- Store new diff explanations and their `.diff` file together under `.code_reader/diffs/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep each step focused on the referenced hunk's purpose and behavioral impact.
- Do not guess hunk ids. Parse the diff and use file-local `H1`, `H2`, and so on.
- Prefer `@old` and `@new` for side-specific ranges. Use `@a` and `@b` only when a shorter Git-style form is helpful.
- Use `padding=N` for symmetric hunk context and `L(-n)-L(+m)` or mixed bounds like `L(-1)-L22` when the context is asymmetric.
