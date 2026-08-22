# Code Reader

Code Reader is a Neovim reader for AI-authored, map-first code walkthroughs. It keeps the execution map, navigable explanation stages, and selected source, diff, or sketch evidence visible together.

![Code Reader diff walkthrough](assets/code_reader.png)

## What it provides

- v2 `code-reader` and `code-reader-diff` Markdown walkthroughs.
- A three-pane Neovim layout: stage outline, explanation/mental model, and selected evidence.
- Stage-local `[1]` evidence links for exact source ranges, diff hunks, and SVG sketches.
- A reader route of execution map → key step → labelled state/ownership bullets → source or diff proof.
- Explicit state transitions, responsibility/ownership, failures, and accessible sketch text models.
- PDF export that places relationship maps before a stage's semantic bullets and source/diff proof after them.
- Mermaid for compact, linear flows and editable Excalidraw assets for relationships that need spatial comparison.
- Diff rendering, Tree-sitter symbol links, source focus/dimming, and copied source/diff references.

## Install

Using lazy.nvim:

```lua
{
  url = "git@github.com:KudoLayton/code-reader.nvim.git",
  name = "code-reader.nvim",
  cmd = {
    "CodeReaderOpen",
    "CodeReaderRefresh",
    "CodeReaderNext",
    "CodeReaderPrev",
    "CodeReaderGoto",
    "CodeReaderToggleFocus",
    "CodeReaderToggleDimming",
    "CodeReaderEditSketch",
    "CodeReaderClose",
    "CodeReaderCopyRef",
  },
}
```

Mermaid rendering is optional. Run `:checkhealth code_reader` to inspect Mermaid, SVG image support, and the configured sketch editor.

## Read a walkthrough

Store walkthroughs under `.code_reader/` and open them from the project root:

```vim
:CodeReaderOpen .code_reader/walkthrough.md
```

Use `]r` and `[r` to change stages. When a stage or overview has a purpose-labelled relationship map, it is the initial evidence-pane view; press `<CR>` on a `code-reader://evidence/<id>` link to choose another proof. Source and diff evidence open their exact range; sketch evidence displays its SVG when image support is available and otherwise displays its text-model fallback.

For a v2 walkthrough with an overview execution map, each anchored stage also shows an **Execution position** minimap directly below its title. It emphasizes the stage's current semantic scope and keeps only immediate incoming or outgoing handoffs visible around it; it is orientation context, not reading-progress tracking.

`:CodeReaderEditSketch` passes the selected sketch's editable `.excalidraw` file—not its SVG preview—to the configured editor command.

```lua
require("code_reader").setup({
  sketch = {
    enabled = true,
    editor_command = {
      "npx", "--yes", "mcp-excalidraw-server@2.0.0", "import", "{file}",
    },
  },
})
```

The import command loads the local canvas; open `http://127.0.0.1:3000` in a browser to edit or inspect it.

## Author walkthroughs with Codex

The local marketplace at `.agents/plugins/marketplace.json` provides the `code-reader-authoring` plugin. Its skills create v2 feature and diff walkthroughs, validate them, and export PDFs. It also registers the local `excalidraw` MCP server through `npx -y mcp-excalidraw-server@2.0.0`.

For a sketch, retain both assets in the target project:

```text
.code_reader/assets/request-flow.excalidraw  # editable scene
.code_reader/assets/request-flow.svg         # Neovim/PDF preview
```

The MCP is an authoring dependency, not a reading or CI dependency. The authoring workflow creates and inspects the editable scene, exports a preview SVG, then records an equivalent `text_model` in Markdown. Use execution maps for the whole runtime space, handoff maps for ownership changes, state maps for lifecycles, and structure maps for static boundaries. Do not use a sketch where Mermaid or labelled bullet cards explain the relation more directly.

The complete v2 contract, sketch criteria, reviewer format, and validator command are in [the authoring reference](plugins/code-reader-authoring/references/code-reader-markdown-format.md).

## Export PDF

Install export dependencies once:

```powershell
cd plugins/code-reader-authoring
npm install
```

Validate first, then export:

```powershell
uv run --no-project plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root demo/basic demo/basic/.code_reader/walkthrough.md
node plugins/code-reader-authoring/scripts/code-reader-pdf.mjs demo/basic/.code_reader/walkthrough.md --root demo/basic
```

The PDF renderer uses only committed Markdown, source/diff files, Mermaid, and SVG previews. It renders an anchored stage's derived execution-position minimap below the title, preserves the original purpose-labelled relationship maps as evidence, then emits source/diff proof pages. It never starts Excalidraw or regenerates a sketch.

## Demo

`demo/basic` contains a valid map-first v2 feature walkthrough, a diff walkthrough, an editable Excalidraw scene, and an SVG preview.

```vim
:CodeReaderOpen demo/basic/.code_reader/walkthrough.md
:CodeReaderOpen demo/basic/.code_reader/diffs/request-update.md
```

## Tests

Run the Lua parser and Neovim integration specs:

```powershell
nvim --headless -u NONE -l tests/parser_spec.lua
nvim --headless -u NONE -l tests/evidence_spec.lua
nvim --headless -u NONE -l tests/authoring_validator_spec.lua
```

Run authoring and PDF tests:

```powershell
uv run --no-project python -m unittest plugins/code-reader-authoring/tests/test_validate_code_reader_markdown.py
npm --prefix plugins/code-reader-authoring run test:pdf
```
