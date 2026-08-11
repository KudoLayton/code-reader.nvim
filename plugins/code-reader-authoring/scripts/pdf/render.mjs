import { readFile } from "node:fs/promises";
import path from "node:path";

import { codeToTokens } from "shiki";
import { unified } from "unified";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import rehypeStringify from "rehype-stringify";

import {
  analyzeDiffFile,
  buildSourceSnippet,
  parseUnifiedDiff,
  renderDiffSnippet,
} from "./document.mjs";

const filetypeByExtension = {
  c: "c",
  cc: "cpp",
  cpp: "cpp",
  cs: "csharp",
  css: "css",
  go: "go",
  h: "c",
  hpp: "cpp",
  html: "html",
  java: "java",
  js: "javascript",
  json: "json",
  jsx: "jsx",
  lua: "lua",
  md: "markdown",
  py: "python",
  rs: "rust",
  sh: "shellscript",
  sql: "sql",
  ts: "typescript",
  tsx: "tsx",
  vue: "vue",
  xml: "xml",
  yaml: "yaml",
  yml: "yaml",
};

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function markdownMermaid() {
  return (tree) => {
    const visit = (node) => {
      if (node.type === "code" && node.lang?.toLowerCase() === "mermaid") {
        node.type = "paragraph";
        node.children = [{ type: "text", value: node.value }];
        node.data = { hName: "div", hProperties: { className: ["mermaid"] } };
      }
      for (const child of node.children ?? []) {
        visit(child);
      }
    };
    visit(tree);
  };
}

async function markdownToHtml(markdown) {
  if (!markdown) {
    return "";
  }
  const processor = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(markdownMermaid)
    .use(remarkRehype)
    .use(rehypeStringify);
  return String(await processor.process(markdown));
}

function languageForPath(filePath) {
  const extension = path.extname(filePath).slice(1).toLowerCase();
  return filetypeByExtension[extension];
}

function fontStyle(style) {
  const values = [];
  if (style & 1) {
    values.push("font-style:italic");
  }
  if (style & 2) {
    values.push("font-weight:700");
  }
  if (style & 4) {
    values.push("text-decoration:underline");
  }
  return values.join(";");
}

async function highlightRows(rows, filePath) {
  const text = rows.map((row) => row.text).join("\n");
  const language = languageForPath(filePath);
  if (!language || !text) {
    return rows.map((row) => escapeHtml(row.text));
  }

  try {
    const result = await codeToTokens(text, { lang: language, theme: "github-light" });
    return result.tokens.map((line) =>
      line
        .map((token) => {
          const style = [`color:${token.color}`, fontStyle(token.fontStyle)].filter(Boolean).join(";");
          return `<span style="${style}">${escapeHtml(token.content)}</span>`;
        })
        .join(""),
    );
  } catch {
    return rows.map((row) => escapeHtml(row.text));
  }
}

async function renderCodeRows(rows, filePath) {
  const highlighted = await highlightRows(rows, filePath);
  return rows
    .map((row, index) => {
      const focusClass = row.focused ? " code-line--focused" : "";
      return [
        `<div class="code-line${focusClass}">`,
        `<span class="line-number">${row.number ?? ""}</span>`,
        '<span class="diff-marker"></span>',
        `<code>${highlighted[index] || "&nbsp;"}</code>`,
        "</div>",
      ].join("");
    })
    .join("\n");
}

function screenPageAttributes(screenPageName) {
  if (!screenPageName) {
    return "";
  }
  return ` data-screen-page="${screenPageName}" style="page: ${screenPageName}"`;
}

function screenContentAttributes(screenPageName) {
  return screenPageName ? " data-screen-content" : "";
}

async function renderSourceSection(reference, sourceLines, padding, screenPageName) {
  const snippet = buildSourceSnippet(sourceLines, reference, padding);
  const rows = await renderCodeRows(snippet.lines, reference.path);
  return [
    `<section class="pdf-section pdf-section--code"${screenPageAttributes(screenPageName)}>`,
    '<header class="code-header">',
    `<span>Source</span><strong>${escapeHtml(reference.path)}</strong>`,
    `<span>L${reference.startLine}-L${reference.endLine}</span>`,
    "</header>",
    `<div class="code-block"${screenContentAttributes(screenPageName)}>${rows}</div>`,
    "</section>",
  ].join("\n");
}

async function renderDiffSection(reference, hunk, analysis, padding, screenPageName) {
  const snippet = renderDiffSnippet(hunk, {
    beforeLines: analysis.beforeLines,
    afterLines: analysis.afterLines,
    padding: reference.padding ?? padding,
    reference,
  });
  const beforeRows = snippet.rows.map((row) => row.before);
  const afterRows = snippet.rows.map((row) => row.after);
  const [before, after] = await Promise.all([
    renderDiffRows(beforeRows, reference.path, Boolean(reference.side)),
    renderDiffRows(afterRows, reference.path, Boolean(reference.side)),
  ]);
  return [
    `<section class="pdf-section pdf-section--code"${screenPageAttributes(screenPageName)}>`,
    '<header class="code-header">',
    `<span>Diff ${escapeHtml(reference.hunkId)}</span><strong>${escapeHtml(reference.path)}</strong>`,
    `<span>${escapeHtml(analysis.status)}</span>`,
    "</header>",
    `<div class="diff-grid"${screenContentAttributes(screenPageName)}>`,
    `<section><h2>Before</h2><div class="code-block">${before}</div></section>`,
    `<section><h2>After</h2><div class="code-block">${after}</div></section>`,
    "</div>",
    "</section>",
  ].join("\n");
}

async function renderDiffRows(rows, filePath, showFocusedRange) {
  const highlighted = await highlightRows(rows, filePath);
  return rows
    .map((row, index) => {
      const classes = ["code-line", `code-line--${row.kind}`];
      if (showFocusedRange && row.focused) {
        classes.push("code-line--focused");
      }
      return [
        `<div class="${classes.join(" ")}">`,
        `<span class="line-number">${row.number ?? ""}</span>`,
        `<span class="diff-marker">${escapeHtml(row.marker)}</span>`,
        `<code>${highlighted[index] || "&nbsp;"}</code>`,
        "</div>",
      ].join("");
    })
    .join("\n");
}

function renderExplanationSection(step, index, total) {
  return [
    '<section class="pdf-section pdf-section--explanation">',
    '<header class="explanation-header">',
    `<span>Code Reader · ${step.kind === "front_page" ? "Overview" : `Step ${index}/${total}`}</span>`,
    "</header>",
    `<h1>${escapeHtml(step.title)}</h1>`,
    '<article class="markdown-body">',
    step.html,
    "</article>",
    "</section>",
  ].join("\n");
}

async function loadSourceLines(root, reference) {
  const sourcePath = path.resolve(root, reference.path);
  let contents;
  try {
    contents = await readFile(sourcePath, "utf8");
  } catch (error) {
    throw new Error(`Cannot read Source file ${reference.path}: ${error.message}`);
  }
  const lines = contents.replace(/\r\n?/g, "\n").split("\n");
  if (reference.startLine < 1 || reference.endLine < reference.startLine || reference.endLine > lines.length) {
    throw new Error(`Source range is outside ${reference.path}: L${reference.startLine}-L${reference.endLine}.`);
  }
  return lines;
}

async function loadDiffModel(document) {
  const diffReference = document.frontmatter.diff;
  if (!diffReference) {
    throw new Error("Diff walkthrough frontmatter must include `diff`.");
  }
  const diffPath = path.resolve(document.markdownDirectory, diffReference);
  try {
    return parseUnifiedDiff(await readFile(diffPath, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read diff file ${diffReference}: ${error.message}`);
  }
}

async function analyzeFile(root, file) {
  if (!file?.path) {
    return { status: "missing", beforeLines: [], afterLines: [] };
  }
  try {
    const contents = await readFile(path.resolve(root, file.path), "utf8");
    return analyzeDiffFile(file, contents.replace(/\r\n?/g, "\n").split("\n"));
  } catch {
    return { status: "missing", beforeLines: [], afterLines: [] };
  }
}

export async function renderCodeReaderHtml(document, options) {
  const root = path.resolve(options.root);
  const padding = options.padding;
  const layout = options.layout ?? "print";
  if (!["print", "screen"].includes(layout)) {
    throw new Error(`Unknown PDF layout: ${layout}`);
  }
  const sections = [];
  let screenPageCount = 0;
  const diffModel = document.type === "code-reader-diff" ? await loadDiffModel(document) : undefined;
  const nextScreenPageName = () => (layout === "screen" ? `code-screen-${++screenPageCount}` : undefined);

  for (let index = 0; index < document.steps.length; index += 1) {
    const step = document.steps[index];
    step.html = await markdownToHtml(step.body);
    sections.push(renderExplanationSection(step, index + 1, document.steps.length));

    if (step.kind === "front_page") {
      continue;
    }

    if (document.type === "code-reader") {
      for (const reference of step.sources) {
        sections.push(await renderSourceSection(reference, await loadSourceLines(root, reference), padding, nextScreenPageName()));
      }
      continue;
    }

    for (const reference of step.diffReferences) {
      const file = diffModel.files.find((item) => item.path === reference.path);
      const hunk = file?.hunks.find((item) => item.id === reference.hunkId);
      if (!hunk) {
        throw new Error(`Cannot find ${reference.path}#${reference.hunkId} in the referenced diff.`);
      }
      sections.push(await renderDiffSection(reference, hunk, await analyzeFile(root, file), padding, nextScreenPageName()));
    }
  }

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="light">
<base href="file://${root.replaceAll("\\", "/")}/">
<style>
@page explanation { size: A4 portrait; margin: 16mm 18mm; }
@page code { size: A4 landscape; margin: 12mm; }
* { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
:root { color-scheme: light; background: #fff; }
html, body { margin: 0; color: #1f2937; background: #fff; font-family: "Malgun Gothic", "Segoe UI", sans-serif; }
.pdf-section { break-before: page; background: #fff; }
.pdf-section:first-child { break-before: auto; }
.pdf-section--explanation { page: explanation; font-size: 10.5pt; line-height: 1.7; }
.pdf-section--code { page: code; break-after: page; color: #1f2937; font-family: "Cascadia Mono", Consolas, monospace; }
.explanation-header { color: #64748b; font-size: 9pt; letter-spacing: .04em; text-transform: uppercase; border-bottom: 1px solid #cbd5e1; padding-bottom: 4mm; }
h1 { color: #0f172a; font-size: 24pt; line-height: 1.25; margin: 8mm 0 7mm; }
.markdown-body h2 { color: #1e293b; font-size: 15pt; margin-top: 7mm; }
.markdown-body h3 { color: #334155; font-size: 12pt; margin-top: 5mm; }
.markdown-body pre { padding: 4mm; background: #f1f5f9; border-radius: 2mm; overflow-wrap: anywhere; white-space: pre-wrap; }
.markdown-body code { font-family: "Cascadia Mono", Consolas, monospace; font-size: .9em; }
.markdown-body :not(pre) > code { color: #9f1239; background: #fff1f2; padding: .1em .25em; border-radius: .2em; }
.markdown-body table { border-collapse: collapse; width: 100%; }
.markdown-body th, .markdown-body td { border: 1px solid #cbd5e1; padding: 2mm; text-align: left; }
.mermaid { break-inside: avoid; margin: 6mm 0; text-align: center; }
.mermaid svg { max-width: 100%; height: auto; }
.code-header { display: flex; gap: 4mm; align-items: baseline; color: #1e3a8a; background: #eff6ff; border: 1px solid #bfdbfe; border-bottom: 0; border-radius: 2mm 2mm 0 0; padding: 3.5mm 4mm; font-size: 9pt; }
.code-header strong { color: #0f172a; font-size: 10pt; }
.code-header span:last-child { margin-left: auto; color: #475569; }
.code-block { background: #fff; border: 1px solid #cbd5e1; border-top: 0; padding: 2mm 0; }
.code-line { display: grid; grid-template-columns: 14mm 5mm minmax(0, 1fr); align-items: start; min-height: 1.55em; background: #fff; font-size: 8.5pt; line-height: 1.55; break-inside: avoid; }
.code-line--focused { box-shadow: inset 4px 0 #2563eb, inset 0 0 0 1px #2563eb; }
.line-number { color: #6b7280; padding-right: 2mm; text-align: right; user-select: none; }
.code-line--focused .line-number, .code-line--focused .diff-marker { color: #1d4ed8; font-weight: 700; }
.code-line code { color: #1f2937; font-family: inherit; white-space: pre-wrap; overflow-wrap: anywhere; min-width: 0; padding-right: 3mm; }
.diff-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 5mm; }
.diff-grid h2 { color: #334155; font: 700 10pt "Malgun Gothic", "Segoe UI", sans-serif; margin: 3mm 0 2mm; }
.diff-marker { color: #64748b; text-align: center; }
.code-line--deleted { background: #fee2e2; }
.code-line--added { background: #dcfce7; }
.code-line--modified { background: #fef3c7; }
.pdf-layout--screen .pdf-section--code { break-after: page; break-inside: avoid-page; }
.pdf-layout--screen .code-block { display: inline-block; min-width: 100%; width: max-content; }
.pdf-layout--screen .code-line { grid-template-columns: 14mm 5mm max-content; width: max-content; }
.pdf-layout--screen .code-line code { min-width: max-content; overflow-wrap: normal; white-space: pre; }
.pdf-layout--screen .diff-grid { display: inline-grid; grid-template-columns: max-content max-content; width: max-content; }
.pdf-layout--screen .diff-grid > section { width: max-content; }
</style>
</head>
<body class="pdf-layout--${layout}">
${sections.join("\n")}
</body>
</html>`;
}
