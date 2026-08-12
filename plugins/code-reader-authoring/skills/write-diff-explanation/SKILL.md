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
5. Put exactly one `Diff: path#Hn` or side-specific range reference in each concrete page's metadata preamble, immediately after its opening heading. Use a separate `---` page for every additional hunk or focused range. Add `Target: function <name>` or `Target: type <name>` only to override unavailable or incorrect automatic PDF target detection.
6. Use `@new` only when the page's primary walkthrough is the post-change code or behavior, and `@old` only when it is removed or replaced pre-change code or behavior. For a balanced old/new comparison, use an unmodified `Diff: path#Hn`; never choose a side only to narrow the visible range.
7. Split large hunks, whole-file additions, dense rewrites, or subroutines into nested focused range pages. Each page's Diff scope must contain only the change its prose explains and must not cross a definition boundary.
8. Cover every hunk unless the user explicitly asks for a partial explanation.
9. Run the shared validator with `--emit-page-inventory`. It bootstraps only registered, lock-pinned static-analysis dependencies, resolves old/new source where possible, analyzes a full definition or complete structural focused range, and records `hunk_fallback` rather than inventing a source range when resolution fails.
10. When the inventory reports an immediate split, narrow the focused ranges and split the page before requesting any reviewer. An unresolved source, non-structural focused range, or unavailable static analysis is not a pass; preserve its `fallback_required` evidence for review.
11. Follow the `Page Scope Reviewer Configuration` in `../../references/code-reader-markdown-format.md` before asking one read-only `code_reader_page_scope_reviewer` subagent to perform `Page Scope Review v1`, including the hunk-to-page coverage table, any `hunk_fallback` evidence, and a `focus_alignment` record for every Diff page. If the dedicated reviewer is not configured, recommend its setup and ask whether to use one explicit `gpt-5.6-luna` / `medium` review or skip the review; never silently inherit the writing agent's model and effort. For every `fallback_required` page, it must measure V(G), independent concepts, and variable--value pairs with the same split thresholds. Treat `MISMATCH` or `INSUFFICIENT_EVIDENCE` as `CHANGES_REQUIRED`.
12. Fix every `SPLIT_REQUIRED` or `CHANGES_REQUIRED` result, then rerun static validation and a fresh Page Scope Review until the report has `overall_verdict: PASS`.
13. Perform `Walkthrough Flow Review v1` from `../../references/code-reader-markdown-format.md` yourself after Page Scope Review passes. Do not delegate this whole-document ordering and hierarchy check to a subagent.
14. Fix every Flow Review `CHANGES_REQUIRED` result. If a fix changes a range, prose scope, or page count, restart from static validation; otherwise rerun Flow Review until it has `overall_verdict: PASS`.

## Output Defaults

- Store new diff explanations and their `.diff` file together under `.code_reader/diffs/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep each step focused on the referenced hunk's purpose and behavioral impact.
- Do not guess hunk ids. Parse the diff and use file-local `H1`, `H2`, and so on.
- Prefer `@old` and `@new` for side-specific ranges. Use `@a` and `@b` only when a shorter Git-style form is helpful.
- A side-specific range is an assertion about what the page explains: `@new` is post-change, `@old` is pre-change, and no modifier is for a balanced comparison.
- Use `padding=N` for symmetric hunk context and `L(-n)-L(+m)` or mixed bounds like `L(-1)-L22` when the context is asymmetric.
