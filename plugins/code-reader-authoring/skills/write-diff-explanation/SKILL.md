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
5. Put one or more `Diff: path#Hn` or side-specific range references in each concrete page's metadata preamble, immediately after its opening heading. Multiple references are valid only when their resolved old/new scopes belong to one logical definition.
6. Split large hunks, whole-file additions, dense rewrites, or subroutines into nested focused range pages. Each page's Diff scope must contain only the change its prose explains and must not cross a definition boundary.
7. Cover every hunk unless the user explicitly asks for a partial explanation.
8. Run the shared validator with `--emit-page-inventory`. It bootstraps only registered, lock-pinned static-analysis dependencies, resolves old/new source where possible, and records `hunk_fallback` rather than inventing a source range when resolution fails.
9. When the inventory reports an immediate split, narrow the focused ranges and split the page before requesting any reviewer. An unresolved source or unavailable static analysis is not a pass.
10. Ask one read-only subagent to perform `Page Scope Review v1` from `../../references/code-reader-markdown-format.md`, including the hunk-to-page coverage table and any `hunk_fallback` evidence.
11. Fix every `SPLIT_REQUIRED` or `CHANGES_REQUIRED` result, then rerun static validation and a fresh Page Scope Review until the report has `overall_verdict: PASS`.

## Output Defaults

- Store new diff explanations and their `.diff` file together under `.code_reader/diffs/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep each step focused on the referenced hunk's purpose and behavioral impact.
- Do not guess hunk ids. Parse the diff and use file-local `H1`, `H2`, and so on.
- Prefer `@old` and `@new` for side-specific ranges. Use `@a` and `@b` only when a shorter Git-style form is helpful.
- Use `padding=N` for symmetric hunk context and `L(-n)-L(+m)` or mixed bounds like `L(-1)-L22` when the context is asymmetric.
