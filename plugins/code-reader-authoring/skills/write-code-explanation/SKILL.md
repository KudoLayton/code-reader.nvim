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
6. Put `Source: path#Lx-Ly` on every concrete step, including nested steps. Use `Cursor: path#Lx` only when the explanation begins inside a broader first source range.
7. Add internal links only when they help the reader move through the flow.
8. Add `treesitter://` symbol links only when a stable symbol highlight is useful.
9. Order steps by runtime execution flow, keep each page scope limited to what its prose explains, and split long routines or subroutines into nested steps.
10. Run the shared validator and fix every reported issue.
11. Ask a read-only subagent to perform the Authoring Review defined in `../../references/code-reader-markdown-format.md`.
12. Fix every review issue, then rerun the validator and Authoring Review until the subagent returns `VERDICT: PASS`.

## Output Defaults

- Store new walkthroughs under `.code_reader/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep explanations concise and tied to the referenced lines.
- Do not invent source ranges. Read the files and choose exact line numbers.
