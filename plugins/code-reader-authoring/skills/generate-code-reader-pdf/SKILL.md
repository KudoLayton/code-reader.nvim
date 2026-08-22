---
name: generate-code-reader-pdf
description: "Render a validated v2 Code Reader feature or diff walkthrough as a PDF with linked source, diff, Mermaid, and SVG sketch evidence. Use for export or print requests, not for rewriting an explanation."
---

# Generate Code Reader PDF

Render an existing walkthrough; do not rewrite its explanation or evidence unless the user asks separately.

1. Identify the Markdown input, project root, and output path. Confirm v2 frontmatter and run the shared validator before rendering.
2. For a diff document, confirm its `diff:` path. For every sketch, confirm that its SVG preview and editable `.excalidraw` source already exist. PDF export must not call Excalidraw MCP or regenerate assets.
3. Use `scripts/code-reader-pdf.mjs` from this plugin root. Pass `--root` explicitly; omit `--output` to write beside the Markdown input.
4. If plugin dependencies are absent, ask before running `npm install` in the plugin root. Do not install packages in the user's project.
5. Verify the output exists. Inspect the overview, one source/diff evidence page, and every standalone sketch page when a browser is available. For anchored stages, check that the derived execution-position minimap appears below the title before the mental model, emphasizes the selected node/edge, keeps direct handoffs secondary, and retains a readable text caption. Check that normal evidence follows its explanation, SVG text is readable, and the text equivalent is present.

```text
node <plugin-root>/scripts/code-reader-pdf.mjs <markdown-file> --root <project-root> [--output <pdf-file>] [--padding <n>] [--layout <print|screen>] [--browser <path>]
```

The CLI requires Node.js and Chrome or Edge. Preserve an existing PDF if rendering fails; report missing source, diff, SVG, browser, or malformed Mermaid errors rather than producing a partial result.
