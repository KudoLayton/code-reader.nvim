# Code Reader Markdown Format

Use this reference before writing any `code-reader.nvim` explanation markdown.

## Shared Rules

- Write explanation prose in the language the user primarily uses. If the user explicitly requests a language, use that language.
- Keep code identifiers, file paths, source ranges, diff refs, link targets, and protocol URLs exactly as they appear in the project.
- Use YAML frontmatter at the top:

```markdown
---
type: code-reader
version: 1
---
```

- Separate every page or step with a line containing only `---`.
- Put `<!-- code-reader: front-page -->` as the first non-empty line of the first section.
- The front page explains the overall subject. Prefer covering the feature purpose, scope, high-level structure, main module roles, and the reading flow.
- Use a Mermaid diagram on the front page when it clarifies feature structure or execution flow.
- Do not put `Source:` or `Diff:` references on the front page. Put references on concrete explanation steps.
- Use numeric heading ids for steps, such as `# 1. Request lifecycle` and `## 1.1. Parse request`.
- Use `[[step-id]]` or `[[step-id|label]]` only for links to existing steps in the same explanation.

## Code Explanation

- Use `type: code-reader`.
- Each non-front-page step should include at least one source reference.
- Write source references as `Source: path#Lx` or `Source: path#Lx-Ly`.
- Keep paths project-root relative and use `/` separators.
- Optional symbol links must include the source path:

```markdown
[handle](<treesitter://src/app.lua?query=(identifier) @code_reader.symbol>)
```

## Diff Explanation

- Use `type: code-reader-diff`.
- Add `diff: ./change.diff` in frontmatter. Resolve it relative to the markdown file.
- The front page should summarize the change set: purpose, behavioral impact, affected files or modules, and suggested review flow.
- Explain individual hunks in step sections, not on the front page.
- Each non-front-page step should include at least one diff reference.
- Write diff references as `Diff: path#Hn`, where `Hn` is the file-local hunk number from the unified diff.
- Prefer covering every hunk in the diff unless the user asks for a partial explanation.

## Validation

Run the shared validator after writing or editing a document:

```powershell
python plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root <repo-root> <markdown-file>
```

Use `--allow-partial-diff` only when the user explicitly wants a partial diff explanation.
