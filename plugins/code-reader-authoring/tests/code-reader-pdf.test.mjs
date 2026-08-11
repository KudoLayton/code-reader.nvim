import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { PDFDocument } from "pdf-lib";

import { findBrowserExecutable, writePdfFromHtml } from "../scripts/pdf/browser.mjs";
import { defaultOutputPath, main, parseCliArguments } from "../scripts/pdf/cli.mjs";
import {
  buildSourceSnippet,
  parseCodeReaderDocument,
  parseUnifiedDiff,
  renderDiffSnippet,
} from "../scripts/pdf/document.mjs";
import { renderCodeReaderHtml } from "../scripts/pdf/render.mjs";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testDirectory, "../../..");
const demoRoot = path.join(repositoryRoot, "demo", "basic");

test("defaults PDF output beside its Markdown input and validates layout", () => {
  const input = path.join("docs", ".code_reader", "walkthrough.md");

  assert.equal(defaultOutputPath(input), path.join("docs", ".code_reader", "walkthrough.pdf"));
  assert.deepEqual(parseCliArguments([input]), {
    root: process.cwd(),
    padding: 5,
    layout: "print",
    input,
  });
  assert.equal(parseCliArguments([input, "--layout", "screen"]).layout, "screen");
  assert.throws(() => parseCliArguments([input, "--layout", "wide"]), /--layout must be either print or screen/);
});

test("writes the default PDF output beside its Markdown input", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-default-output-"));
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");
  const output = defaultOutputPath(markdownPath);

  await writeFile(markdownPath, ["---", "type: code-reader", "version: 1", "---", "", "# Overview"].join("\n"), "utf8");
  try {
    await main([markdownPath, "--root", temporaryDirectory]);
    await access(output);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("parses source walkthrough steps and Source ranges", async () => {
  const markdown = await readFile(path.join(demoRoot, ".code_reader", "walkthrough.md"), "utf8");
  const document = parseCodeReaderDocument(markdown, {
    markdownPath: path.join(demoRoot, ".code_reader", "walkthrough.md"),
  });

  assert.equal(document.type, "code-reader");
  assert.equal(document.steps.length, 6);
  assert.equal(document.steps[0].kind, "front_page");
  assert.deepEqual(document.steps[1].sources[0], {
    path: "src/app.lua",
    startLine: 12,
    endLine: 21,
    expectedHash: undefined,
  });
});

test("keeps the requested Source range highlighted while padding surrounding lines", () => {
  const snippet = buildSourceSnippet(
    ["one", "two", "three", "four", "five", "six", "seven"],
    { path: "example.lua", startLine: 3, endLine: 5 },
    2,
  );

  assert.deepEqual(
    snippet.lines.map((line) => line.number), [1, 2, 3, 4, 5, 6, 7]);
  assert.deepEqual(
    snippet.lines.filter((line) => line.focused).map((line) => line.number), [3, 4, 5]);
});

test("parses a unified diff and renders a padded side-by-side hunk", async () => {
  const patch = await readFile(
    path.join(demoRoot, ".code_reader", "diffs", "request-update.diff"),
    "utf8",
  );
  const document = parseUnifiedDiff(patch);
  const file = document.files.find((item) => item.path === "src/request.lua");

  assert.ok(file);
  assert.equal(file.hunks.length, 2);
  assert.equal(file.hunks[0].id, "H1");

  const rendered = renderDiffSnippet(file.hunks[0], {
    padding: 1,
    beforeLines: [
      "local request = {}",
      "",
      "function request.parse_request(raw_request)",
      '  local method = raw_request.method or "GET"',
      '  local path = raw_request.path or "/"',
      '  local user = raw_request.user or "anonymous"',
      "",
      "  return {",
      "    method = method,",
      "    path = path,",
      "    user = user,",
      "  }",
      "end",
    ],
    afterLines: [
      "local request = {}",
      "",
      "function request.parse_request(raw_request)",
      '  local method = raw_request.method or "GET"',
      '  local user = raw_request.user or "anonymous"',
      '  local path = raw_request.path or "/"',
      '  local request_id = raw_request.request_id or "demo-request"',
      "",
      "  return {",
      "    method = method,",
      "    path = path,",
      "    user = user,",
      "    request_id = request_id,",
      "  }",
      "end",
    ],
  });

  assert.equal(rendered.rows.some((row) => row.before.marker === "-"), true);
  assert.equal(rendered.rows.some((row) => row.after.marker === "+"), true);
  assert.equal(rendered.rows.some((row) => row.before.focused || row.after.focused), true);
  assert.equal(rendered.rows[0].before.number, 2);

  const sideFocused = renderDiffSnippet(file.hunks[0], {
    padding: 1,
    beforeLines: ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen"],
    afterLines: ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen"],
    reference: { side: "new", padding: 1 },
  });
  assert.equal(sideFocused.rows[0].before.focused, false);
  assert.equal(sideFocused.rows[0].after.focused, true);
});

test("generates a PDF with Mermaid and separate portrait and landscape pages", async () => {
  const markdownPath = path.join(demoRoot, ".code_reader", "walkthrough.md");
  const markdown = await readFile(markdownPath, "utf8");
  const document = parseCodeReaderDocument(markdown, { markdownPath });
  const html = await renderCodeReaderHtml(document, { root: demoRoot, padding: 5 });
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-pdf-"));
  const output = path.join(temporaryDirectory, "walkthrough.pdf");

  try {
    assert.match(html, /class="mermaid"/);
    const result = await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));
    const dimensions = pdf.getPages().map((page) => page.getSize());

    assert.equal(result.mermaidCount > 0, true);
    assert.equal(dimensions.some((size) => size.height > size.width), true);
    assert.equal(dimensions.some((size) => size.width > size.height), true);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("generates a side-by-side Diff PDF", async () => {
  const markdownPath = path.join(demoRoot, ".code_reader", "diffs", "request-update.md");
  const markdown = await readFile(markdownPath, "utf8");
  const document = parseCodeReaderDocument(markdown, { markdownPath });
  const html = await renderCodeReaderHtml(document, { root: demoRoot, padding: 5 });
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-diff-pdf-"));
  const output = path.join(temporaryDirectory, "request-update.pdf");

  try {
    assert.match(html, /<h2>Before<\/h2>/);
    assert.match(html, /<h2>After<\/h2>/);
    assert.match(html, /code-line--deleted/);
    assert.match(html, /code-line--added/);
    await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));

    assert.equal(pdf.getPageCount() > 1, true);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("generates a screen-layout code page without wrapping a long source line", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-screen-pdf-"));
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");
  const sourcePath = path.join(temporaryDirectory, "wide.lua");
  const nextSourcePath = path.join(temporaryDirectory, "next.lua");
  const output = path.join(temporaryDirectory, "walkthrough.pdf");
  const longLine = `local request_path = \"/${"segment/".repeat(120)}resource\"`;
  const sourceLines = Array.from({ length: 80 }, (_, index) => `${longLine} -- ${index + 1}`);

  await writeFile(sourcePath, `${sourceLines.join("\n")}\n`, "utf8");
  await writeFile(nextSourcePath, "return true\n", "utf8");
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader",
      "version: 1",
      "---",
      "",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "",
      "---",
      "# Wide source",
      "",
      "Source: `wide.lua#L1-L80`",
      "",
      "---",
      "# Next explanation",
      "",
      "Source: `next.lua#L1`",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, {
      root: temporaryDirectory,
      padding: 5,
      layout: "screen",
    });

    assert.match(html, /pdf-layout--screen/);
    assert.match(html, /data-screen-page=/);
    assert.match(html, /white-space: pre;/);
    await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));
    const dimensions = pdf.getPages().map((page) => page.getSize());

    assert.equal(pdf.getPageCount(), 5);
    assert.equal(dimensions[2].width > 842, true);
    assert.equal(dimensions[2].height > 595, true);
    assert.equal(dimensions[3].height > dimensions[3].width, true);
    assert.equal(dimensions[4].width > dimensions[4].height, true);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
