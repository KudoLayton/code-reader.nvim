---
name: write-code-explanation
description: "Create or revise code-reader.nvim feature walkthrough markdown files. Use when Codex needs to explain a feature, code path, module structure, request flow, or implementation using `type: code-reader` markdown with source line references, front pages, step navigation, and optional Tree-sitter symbol links."
---

# Write Code Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

## Workflow

1. Inspect the target files and identify the feature purpose, reader problem, expected outcome, representative example, entrypoints, major modules, and runtime reading order.
2. If the user provides references copied with `:CodeReaderCopyRef`, use those `path#Lx` or `path#Lx-Ly` ranges as direct source targets unless the user asks for a broader walkthrough.
3. Draft a `type: code-reader` markdown file with a front page and numbered steps.
4. Use heading depth for nested reading flow when helpful: `# 1`, `## 1.1`, and `### 1.1.1` create parent/child navigation and TOC nesting.
5. Keep each top-level or nested step as its own `---`-separated section. Do not make a nested step only as a secondary heading inside another step.
6. Put exactly one continuous `Source: path#Lx-Ly` reference in each concrete page's metadata preamble, immediately after its opening heading. Use `Cursor: path#Lx` only when the explanation begins inside that Source range.
7. Add internal links only when they help the reader move through the flow.
8. Add `treesitter://` symbol links only when a stable symbol highlight is useful.
9. Order steps by runtime execution flow, keep each page inside one definition, and split long routines or subroutines into nested `---` pages. A non-numeric child heading may organize the same scope, but it must not require a broader Source range.
10. Run the shared validator with `--emit-page-inventory`. This bootstraps only registered, lock-pinned static-analysis dependencies and collects deterministic metrics for a full definition or a complete structural partial range.
11. When the inventory reports an immediate split, narrow the source range and split the page before requesting any reviewer. A `fallback_required` result means the selected partial range is not structurally analyzable; do not replace it with the enclosing function's metric.
12. Ask one read-only subagent to perform the `Page Scope Review v1` defined in `../../references/code-reader-markdown-format.md` for the remaining pages. It must measure V(G), independent concepts, and variable--value pairs for every `fallback_required` page and apply the same split thresholds.
13. Fix every `SPLIT_REQUIRED` or `CHANGES_REQUIRED` result, then rerun static validation and a fresh Page Scope Review until the report has `overall_verdict: PASS`.

## Output Defaults

- Store new walkthroughs under `.code_reader/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep explanations concise and tied to the referenced lines.
- Do not invent source ranges. Read the files and choose exact line numbers.
