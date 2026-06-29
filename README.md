# Code Reader

Code Reader is a Neovim plugin prototype for reading AI-generated code through a structured explanation file. It keeps the source code, the current explanation step, and the outline visible at the same time.

## Explanation Format

Explanation files are Markdown files, usually stored under `.code_reader/`.

```markdown
---
type: code-reader
version: 1
---

# 1. Request lifecycle

Source: `src/server.lua#L10-L30`

Explain the top-level flow here.

---
## 1.1. Parse request

Source: `src/parser.lua#L5-L12`

Explain the nested call-stack detail here.
```

- The first frontmatter block identifies the file as `type: code-reader`.
- Step blocks are separated by a line containing only `---`.
- The first Markdown heading in a step becomes the step title.
- Heading depth drives TOC nesting, so `## 1.1 ...` becomes a nested call-stack step.
- GitHub-style `path#Lx` and `path#Lx-Ly` references define the source range.
- Optional source hashes can be appended as `path#Lx-Ly@sha256:<hash>`.

## Usage

Install this repository as a Neovim plugin, then open an explanation file:

```vim
:CodeReaderOpen .code_reader/flow.md
```

Commands:

- `:CodeReaderOpen [file]` opens the source, explanation, and TOC layout.
- `:CodeReaderNext` and `:CodeReaderPrev` move between steps.
- `:CodeReaderGoto {index}` jumps to a step by list index.
- `:CodeReaderToggleFocus` toggles dimming for unrelated source lines.

Inside the explanation panel, `[r` and `]r` move between steps. Press `<CR>` on `Previous`, `Next`, or `Source` footer lines to activate them. In the TOC panel, press `<CR>` to jump to the selected step.

## Tests

```powershell
lua tests/parser_spec.lua
nvim --headless -u NONE -l tests/nvim_spec.lua
```
