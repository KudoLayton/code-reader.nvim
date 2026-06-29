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

Manual review checklist:

- Confirm the layout opens with code, explanation, and TOC views.
- Use `:CodeReaderNext` and `:CodeReaderPrev` to move through the explanation.
- Press `<CR>` on a TOC entry to jump to a step.
- Press `<CR>` on `[[step-id|label]]` links in the explanation panel.
- Press `<CR>` on `treesitter://` symbol links and confirm the named source file opens.
- Run `:CodeReaderToggleFocus` and confirm unrelated source lines are dimmed.
- Edit a source file, reopen the walkthrough, and check the freshness status.
