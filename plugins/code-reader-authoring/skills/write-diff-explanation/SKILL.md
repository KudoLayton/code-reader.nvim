---
name: write-diff-explanation
description: "Create or revise code-reader.nvim diff explanation markdown files. Use when Codex needs to explain a unified diff or patch using `type: code-reader-diff` markdown with a diff front page, `diff: ./change.diff`, file-local `Diff: path#Hn` hunk references, optional side-specific partial ranges such as `@new:L10-L20` or `@new:padding=2`, and hunk coverage validation."
---

# Write Diff Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

## Workflow

1. Inspect the unified diff before writing prose.
2. If the user provides references copied with `:CodeReaderCopyRef`, use those `path#Hn` or `path#Hn@old/new:Lx-Ly` ranges as direct diff targets unless the user asks for a broader review.
3. Identify files, file-local hunk ids, changed behavior, and runtime execution order; do not use patch order as the reading order when it obscures behavior.
4. Draft a `type: code-reader-diff` markdown file with a front page and numbered hunk explanation steps.
5. Put `Diff: path#Hn` or a side-specific range reference on every concrete step.
6. Split large hunks, whole-file additions, dense rewrites, or subroutines into nested focused range steps. Each page's Diff scope must contain only the change its prose explains.
7. Cover every hunk unless the user explicitly asks for a partial explanation.
8. Run the shared validator and fix every reported issue.
9. Ask a read-only subagent to perform the Authoring Review defined in `../../references/code-reader-markdown-format.md`, including the hunk-to-page coverage table.
10. Fix every review issue, then rerun the validator and Authoring Review until the subagent returns `VERDICT: PASS`.

## Output Defaults

- Store new diff explanations and their `.diff` file together under `.code_reader/diffs/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep each step focused on the referenced hunk's purpose and behavioral impact.
- Do not guess hunk ids. Parse the diff and use file-local `H1`, `H2`, and so on.
- Prefer `@old` and `@new` for side-specific ranges. Use `@a` and `@b` only when a shorter Git-style form is helpful.
- Use `padding=N` for symmetric hunk context and `L(-n)-L(+m)` or mixed bounds like `L(-1)-L22` when the context is asymmetric.
