# Code Reader Demo

This directory is an inert demo project. It is shipped with the plugin repository, but it does not contain Neovim auto-load directories or local config files.

Open it as a project root:

```powershell
cd demo/basic
nvim .
```

Then open the walkthrough:

```vim
:CodeReaderOpen .code_reader/walkthrough.md
```

To review the diff explanation demo:

```vim
:CodeReaderOpen .code_reader/diffs/request-update.md
```

Manual review checklist:

- Confirm the feature overview opens with its execution map in the evidence pane.
- Confirm the layout opens with code, explanation, and TOC views for a source-only stage.
- Use `:CodeReaderNext` and `:CodeReaderPrev` to move through the explanation.
- Press `<CR>` on a TOC entry and confirm both code and explanation views update.
- Press `<CR>` on a numbered evidence link and confirm only the evidence pane changes.
- Press `<CR>` on the overview execution-map link and confirm either its SVG preview or text-model fallback appears.
- Move through the stages and confirm the explanation pane's `Execution position` minimap changes current scope while retaining immediate handoffs.
- Configure `sketch.editor_command`, run `:CodeReaderEditSketch` from the overview, and confirm it receives `assets/request-flow.excalidraw`.
- Run `:CodeReaderToggleFocus` and confirm unrelated source lines are dimmed.
- Press `q` in the explanation or TOC panel and confirm Code Reader closes.
- Edit a source file, reopen the walkthrough, and check the freshness status.
- Open the diff demo and confirm the source area becomes a before/after side-by-side view.
- Check that the diff overview and four behavior stages identify state and responsibility changes as labelled bullet cards.
- Confirm the diff demo gutter shows `~`, `+`, `-`, and `>` markers.
- Confirm modified lines have inline highlights on the changed span.
- Toggle focus in the diff demo and confirm unrelated diff rows dim on and off.
