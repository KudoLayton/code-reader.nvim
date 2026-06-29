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
- Use Mermaid diagrams on the front page or individual steps when they clarify structure, control flow, data flow, or hunk impact.
- Prefer plain prose or lists instead of Mermaid when the user disabled Mermaid rendering or `:checkhealth code_reader` reports that Node, npm, or `beautiful-mermaid` is unavailable.
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
- Use step-level Mermaid diagrams only when they make a specific hunk or cross-file relationship easier to review.
- Each non-front-page step should include at least one diff reference.
- Write diff references as `Diff: path#Hn`, where `Hn` is the file-local hunk number from the unified diff.
- For large hunks or whole-file additions, split the explanation with side-specific ranges:
  - `Diff: path#Hn@old:L10-L18`
  - `Diff: path#Hn@new:L20-L40`
  - `@a` means old/before and `@b` means new/after.
- To include hunk-adjacent lines, prefer explicit hunk-relative bounds:
  - `Diff: path#Hn@new:L(-1)-L(+2)` means from one line before the new-side hunk start through two lines after the new-side hunk end.
  - `Diff: path#Hn@old:L(-1)-L22` mixes a relative start with an absolute end line.
  - `L-1-L22` is accepted as shorthand, but write `L(-1)-L22` by default.
- Use `padding=N` or `pad=N` when the same number of lines should be shown before and after the hunk: `Diff: path#Hn@new:padding=2`.
- Prefer covering every hunk in the diff unless the user asks for a partial explanation.

## Validation

Run the shared validator after writing or editing a document:

```powershell
python plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root <repo-root> <markdown-file>
```

Use `--allow-partial-diff` only when the user explicitly wants a partial diff explanation.
