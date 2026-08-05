# Code Reader Markdown Format

Use this reference before writing any `code-reader.nvim` explanation markdown.

## Shared Rules

- Write explanation prose in the language the user primarily uses. If the user explicitly requests a language, use that language.
- Keep code identifiers, file paths, source ranges, diff refs, link targets, and protocol URLs exactly as they appear in the project.
- Users may provide references copied from code-reader.nvim with `:CodeReaderCopyRef`. Treat `path#Lx`, `path#Lx-Ly`, `path#Hn`, and `path#Hn@old/new:Lx-Ly` values as direct targets for the explanation unless the user asks to broaden or narrow the scope.
- Use YAML frontmatter at the top:

```markdown
---
type: code-reader
version: 1
---
```

- Separate every page or step with a line containing only `---`.
- Put `<!-- code-reader: front-page -->` as the first non-empty line of the first section.
- The front page must explain the problem, expected reader outcome, a concrete representative example, high-level structure, main module roles, and the reading flow before the detailed steps.
- Use Mermaid diagrams on the front page or individual steps when they clarify structure, control flow, data flow, or hunk impact.
- Prefer plain prose or lists instead of Mermaid when the user disabled Mermaid rendering or `:checkhealth code_reader` reports that Node, npm, or `beautiful-mermaid` is unavailable.
- Do not put `Source:` or `Diff:` references on the front page. Put references on concrete explanation steps.
- Use numeric heading ids for top-level and nested steps, such as `# 1. Request lifecycle`, `## 1.1. Parse request`, and `### 1.1.1. Validate method`.
- Heading depth on the first heading of each `---`-separated step drives TOC nesting. A nested step must still be its own section, not only a secondary heading inside another step.
- Use `[[step-id]]` or `[[step-id|label]]` only for links to existing steps in the same explanation.
- Order steps by runtime execution flow, not source-file or diff order. When a scope contains a long routine or subroutine, use nested steps instead of making one broad page.
- A page's `Source` or `Diff` scope must contain only the code or change needed by that page's explanation. Do not broaden a page scope merely to make coverage look higher.

## Code Explanation

- Use `type: code-reader`.
- Each non-front-page step should include at least one source reference.
- Write source references as `Source: path#Lx` or `Source: path#Lx-Ly`.
- Use optional `Cursor: path#Lx` when the explanation starts inside a broader first source range. The Cursor path must match that first Source path and its line must be within that Source range.
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
- For large hunks or whole-file additions, split the explanation with side-specific focus ranges:
  - `Diff: path#Hn@old:L10-L18`
  - `Diff: path#Hn@new:L20-L40`
  - `@a` means old/before and `@b` means new/after.
- To include hunk-adjacent lines, prefer explicit hunk-relative bounds:
  - `Diff: path#Hn@new:L(-1)-L(+2)` means from one line before the new-side hunk start through two lines after the new-side hunk end.
  - `Diff: path#Hn@old:L(-1)-L22` mixes a relative start with an absolute end line.
  - `L-1-L22` is accepted as shorthand, but write `L(-1)-L22` by default.
- Use `padding=N` or `pad=N` when the same number of lines should be focused before and after the hunk: `Diff: path#Hn@new:padding=2`.
- Prefer covering every hunk in the diff unless the user asks for a partial explanation. When only part of a hunk belongs on a page, use a side-specific range and cover the remaining meaningful change in another page; do not claim whole-hunk coverage with an unnecessarily broad page.

## Authoring Review

After the static validator passes, ask a read-only subagent to review the completed document before finishing. Give it the project root, Markdown path, document type, every page's references, and—when the document is a diff—the diff path and complete `path#Hn` list.

The subagent must inspect pages in document order and return `VERDICT: PASS` or `VERDICT: CHANGES_REQUIRED`. For every page, report its step id, Source or Diff refs, verdict, any unsupported or omitted explanation, and the required author action. It must verify that each page's own prose, diagrams, and links are supported by that page's scope; another page cannot justify an over-broad scope.

For diff documents, the report must also include a `hunk -> page` coverage table and list uncovered hunks. All hunks remain required unless the user explicitly requested a partial explanation. The subagent must not edit the document; the writing agent fixes every reported issue, reruns the static validator, and requests review again until it passes.

## Validation

Run the shared validator after writing or editing a document:

```powershell
python plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root <repo-root> <markdown-file>
```

Use `--allow-partial-diff` only when the user explicitly wants a partial diff explanation.
