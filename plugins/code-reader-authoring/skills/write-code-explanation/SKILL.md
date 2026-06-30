---
name: write-code-explanation
description: "Create or revise code-reader.nvim feature walkthrough markdown files. Use when Codex needs to explain a feature, code path, module structure, request flow, or implementation using `type: code-reader` markdown with source line references, front pages, step navigation, and optional Tree-sitter symbol links."
---

# Write Code Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

## Workflow

1. Inspect the target files and identify the feature purpose, entrypoints, major modules, and reading order.
2. Draft a `type: code-reader` markdown file with a front page and numbered steps.
3. Use heading depth for nested reading flow when helpful: `# 1`, `## 1.1`, and `### 1.1.1` create parent/child navigation and TOC nesting.
4. Keep each top-level or nested step as its own `---`-separated section. Do not make a nested step only as a secondary heading inside another step.
5. Put `Source: path#Lx-Ly` on every concrete step, including nested steps.
6. Add internal links only when they help the reader move through the flow.
7. Add `treesitter://` symbol links only when a stable symbol highlight is useful.
8. Run the shared validator and fix every reported issue before finishing.

## Output Defaults

- Store new walkthroughs under `.code_reader/` unless the user gives another path.
- Use the user's primary language for explanatory prose.
- Keep explanations concise and tied to the referenced lines.
- Do not invent source ranges. Read the files and choose exact line numbers.
