---
name: generate-code-reader-pdf
description: "Render a `type: code-reader` or `type: code-reader-diff` Markdown walkthrough as a formatted PDF with Mermaid diagrams, syntax-highlighted source, focused ranges, and separate explanation/code pages. Use when Codex needs to export, print, or create a PDF from Code Reader walkthrough Markdown."
---

# Generate Code Reader PDF

Render an existing Code Reader Markdown file. Do not rewrite its explanation or source ranges unless the user asks for that separately.

## Workflow

1. Identify the Markdown input, project root, and optional output path. If no output path is requested, use the Markdown file's directory with the same basename and a `.pdf` extension.
2. Confirm that the Markdown frontmatter type is `code-reader` or `code-reader-diff`. For a diff walkthrough, confirm that its `diff:` file exists relative to the Markdown file.
3. Locate the plugin root two levels above this Skill and use its `scripts/code-reader-pdf.mjs` entrypoint. Pass the project root explicitly with `--root`.
4. Check for the plugin root's `node_modules`. If dependencies are missing, ask for approval before running `npm install` in the plugin root. Do not install packages in the user's project.
5. Run the CLI without `--output` when using the default beside the Markdown input; otherwise pass the requested output path. Use `--padding <n>` only when the user requests context other than the default five lines. Use `--layout screen` when the user wants a screen-only PDF, wider code or diff pages, or no automatic code-line wrapping. Use `--browser <path>` only when Chrome or Edge cannot be discovered automatically.
6. Verify that the PDF exists at the selected path. Render its pages to a temporary directory and inspect the overview, a source/code page, and a diff page when present. Check Mermaid, page orientation, line numbers, focused backgrounds, and readable wrapping; screen-layout code must not wrap automatically. Remove the temporary images after inspection.

## Command Shape

```text
node <plugin-root>/scripts/code-reader-pdf.mjs <markdown-file> --root <project-root> [--output <pdf-file>] [--padding <n>] [--layout <print|screen>] [--browser <path>]
```

The CLI needs Node.js and either Google Chrome or Microsoft Edge. By default it writes `<markdown-file-without-extension>.pdf` beside the Markdown input. It renders HTML and Mermaid SVG in memory and writes only the final PDF; temporary page images are solely for visual verification.

## Failures

- Report missing source files, invalid references, malformed Mermaid, or missing diff hunks before claiming success.
- If Chrome and Edge are unavailable, report the requirement and offer `--browser` for an explicit executable path.
- Preserve an existing output PDF when generation fails; do not replace it with a partial result.
