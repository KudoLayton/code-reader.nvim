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
import { resolveTargetDefinitions } from "../scripts/pdf/static-targets.mjs";

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

  await writeFile(markdownPath, ["---", "type: code-reader", "version: 2", "feature: overview", "---", "", "# Overview"].join("\n"), "utf8");
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
    startLine: 13,
    endLine: 23,
    expectedHash: undefined,
  });
});

test("parses v2 stage evidence and rejects v1 documents", () => {
  const markdown = [
    "---",
    "type: code-reader",
    "version: 2",
    "feature: request-flow",
    "---",
    "# Overview",
    "```code-reader",
    "kind: overview",
    "id: request-flow",
    "state:",
    "  status: not_applicable",
    "  reason: Overview has no runtime transition.",
    "responsibility:",
    "  status: applicable",
    "  items:",
    "    - owner: app.handle",
    "      action: Coordinate the lifecycle",
    "```",
    "---",
    "# 1. Validate",
    "```code-reader",
    "kind: stage",
    "id: validate",
    "evidence:",
    "  - id: 1",
    "    kind: source",
    "    target: src/request.lua#L15-L25",
    "    cursor: src/request.lua#L18",
    "    claim: Validation establishes the dispatch invariant.",
    "  - id: 2",
    "    kind: sketch",
    "    target: .code_reader/assets/validate.svg",
    "    editable_target: .code_reader/assets/validate.excalidraw",
    "    claim: Validation transfers ownership across the boundary.",
    "    text_model:",
    "      claim: Validated requests cross the boundary.",
    "      nodes:",
    "        - id: decoded",
    "          label: Decoded request",
    "          owner: app.handle",
    "          state: decoded",
    "        - id: validated",
    "          label: Validated request",
    "          owner: dispatcher",
    "          state: validated",
    "      edges:",
    "        - from: decoded",
    "          to: validated",
    "          label: validate",
    "```",
    "The invariant is established in [1](code-reader://evidence/1).",
    "The handoff is shown in [2](code-reader://evidence/2).",
  ].join("\n");

  const document = parseCodeReaderDocument(markdown);
  assert.equal(document.steps[0].kind, "front_page");
  assert.equal(document.steps[1].metadata.id, "validate");
  assert.equal(document.steps[1].evidence[0].source.cursorLine, 18);
  assert.equal(document.steps[1].evidenceById.get(2).textModel.nodes[1].owner, "dispatcher");
  assert.equal(document.steps[1].evidenceById.get(2).editablePath, ".code_reader/assets/validate.excalidraw");
  assert.throws(
    () => parseCodeReaderDocument(markdown.replace("version: 2", "version: 1")),
    /format version `2`/,
  );
});

test("renders v2 numbered source and sketch evidence after its explanation", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-v2-evidence-pdf-"));
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");
  await writeFile(path.join(temporaryDirectory, "example.lua"), "return true\n", "utf8");
  await writeFile(
    path.join(temporaryDirectory, "flow.svg"),
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><text x="5" y="25">flow</text></svg>',
    "utf8",
  );
  await writeFile(
    markdownPath,
    [
      "---", "type: code-reader", "version: 2", "feature: evidence-flow", "---",
      "# Overview", "```code-reader", "kind: overview", "id: evidence-flow",
      "question: What is the feature flow?", "state:", "  status: not_applicable", "  reason: Overview is descriptive.",
      "responsibility:", "  status: applicable", "  items:", "    - owner: example", "      action: Own the flow", "```",
      "---", "# 1. Explain flow", "```code-reader", "kind: stage", "id: explain-flow",
      "question: How does the result flow?", "trigger: Example runs", "state:", "  status: applicable", "  changes:",
      "    - subject: result", "      owner: example", "      before: pending", "      cause: return", "      after: complete", "      invariant: result exists",
      "responsibility:", "  status: applicable", "  items:", "    - owner: example", "      action: Return the result",
      "failure:", "  status: not_applicable", "  reason: Example has no failure path.", "evidence:",
      "  - id: 1", "    kind: source", "    target: example.lua#L1", "    claim: The return creates the result.",
    "  - id: 2", "    kind: sketch", "    target: flow.svg", "    editable_target: flow.excalidraw", "    claim: The sketch shows the responsibility handoff.",
    "    purpose: handoff-map",
      "    text_model:", "      claim: The result moves through the example.", "      nodes:", "        - id: input", "          label: Input", "          owner: caller", "          state: pending",
      "        - id: result", "          label: Result", "          owner: example", "          state: complete", "      edges:", "        - from: input", "          to: result", "          label: return",
      "```", "The implementation is [1](code-reader://evidence/1).", "The model is [2](code-reader://evidence/2).",
    ].join("\n"),
    "utf8",
  );
  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });
    assert.match(html, /href="#evidence-explain-flow-1"/);
    assert.match(html, /id="evidence-explain-flow-1"/);
    assert.match(html, /\[1\] Source/);
    assert.match(html, /id="evidence-explain-flow-2"/);
    assert.match(html, /handoff map/);
    assert.match(html, /<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg"/);
    assert.match(html, /State changes/);
    assert.doesNotMatch(html, /\| Subject \| Owner \| Before \|/);
    assert.ok(
      html.indexOf('id="evidence-explain-flow-2"') < html.indexOf("State changes"),
      "the relationship map appears before state bullets",
    );
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("renders conceptual position for model parents and their child stages", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-conceptual-position-"));
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");
  await writeFile(
    markdownPath,
    [
      "---", "type: code-reader", "version: 2", "feature: request-validation", "---",
      "# Overview", "```code-reader", "kind: overview", "id: request-validation",
      "question: What validates a request?", "state:", "  status: not_applicable", "  reason: The overview is descriptive.",
      "responsibility:", "  status: applicable", "  items:", "    - owner: app.handle", "      action: Coordinate validation", "```",
      "---", "# Validation model", "```code-reader", "kind: model", "id: validation-model",
      "question: How do validation parts establish the request contract?", "state:", "  status: not_applicable", "  reason: The model is descriptive.",
      "responsibility:", "  status: applicable", "  items:", "    - owner: validator", "      action: Establish the request contract",
      "hierarchy:", "  contract: A validated request is safe to dispatch.", "  decomposition: Syntax and policy have separate local rules.", "```",
      "---", "# Parse syntax", "```code-reader", "kind: stage", "id: parse-syntax", "parent: validation-model",
      "question: How is syntax accepted?", "trigger: Validation starts", "state:", "  status: not_applicable", "  reason: The example is conceptual.",
      "responsibility:", "  status: applicable", "  items:", "    - owner: parser", "      action: Check syntax", "failure:", "  status: not_applicable", "  reason: The example omits failures.", "```",
      "---", "# Check policy", "```code-reader", "kind: stage", "id: check-policy", "parent: validation-model",
      "question: How is policy accepted?", "trigger: Syntax succeeds", "state:", "  status: not_applicable", "  reason: The example is conceptual.",
      "responsibility:", "  status: applicable", "  items:", "    - owner: policy", "      action: Check policy", "failure:", "  status: not_applicable", "  reason: The example omits failures.", "```",
    ].join("\n"),
    "utf8",
  );
  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });
    assert.match(html, /Conceptual position/);
    assert.match(html, /Overview › Validation model › Parse syntax/);
    assert.match(html, /Shared contract: A validated request is safe to dispatch\./);
    assert.match(html, /Direct child scopes: Parse syntax · Check policy/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("renders automatic and manual target definitions on explanation and code pages", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-target-definitions-"));
  const sourcePath = path.join(temporaryDirectory, "request.py");
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");

  await writeFile(
    sourcePath,
    [
      "from typing import TypeAlias",
      "",
      "RequestOptions: TypeAlias = dict[str, str]",
      "",
      "def send(options: RequestOptions) -> str:",
      "    return options[\"url\"]",
    ].join("\n"),
    "utf8",
  );
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader",
      "version: 2",
      "---",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "---",
      "# 1. Request options",
      "Source: `request.py#L3`",
      "---",
      "# 2. Send request",
      "Target: function deliver",
      "Source: `request.py#L5-L6`",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });

    assert.equal((html.match(/Type: RequestOptions/g) ?? []).length, 2);
    assert.equal((html.match(/Function: deliver/g) ?? []).length, 2);
    assert.doesNotMatch(html, /<p>Target: function deliver<\/p>/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("lists every AST definition whose declaration is in a source target range", async () => {
  const targets = await resolveTargetDefinitions(
    [
      "class Request:",
      "    def parse(self) -> bool:",
      "        return True",
      "",
      "from typing import TypeAlias",
      "RequestId: TypeAlias = str",
    ],
    "request.py",
    1,
    6,
  );

  assert.deepEqual(targets.map(({ kind, name }) => ({ kind, name })), [
    { kind: "type", name: "Request" },
    { kind: "function", name: "parse" },
    { kind: "type", name: "RequestId" },
  ]);
});

test("omits the target label when the source AST cannot be parsed", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-target-parse-failure-"));
  const sourcePath = path.join(temporaryDirectory, "broken.py");
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");

  await writeFile(sourcePath, "def broken(:\n", "utf8");
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader",
      "version: 2",
      "---",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "---",
      "# 1. Broken source",
      "Source: `broken.py#L1`",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });

    assert.doesNotMatch(html, /<strong class="target-definition">/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("uses the primary Diff side to render its target definition", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-diff-target-definition-"));
  const sourcePath = path.join(temporaryDirectory, "request.py");
  const diffPath = path.join(temporaryDirectory, "request.diff");
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");

  await writeFile(sourcePath, ["def deliver_request():", "    return True"].join("\n"), "utf8");
  await writeFile(
    diffPath,
    [
      "diff --git a/request.py b/request.py",
      "--- a/request.py",
      "+++ b/request.py",
      "@@ -1,2 +1,2 @@",
      "-def send_request():",
      "+def deliver_request():",
      "     return True",
    ].join("\n"),
    "utf8",
  );
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader-diff",
      "version: 2",
      "diff: request.diff",
      "---",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "---",
      "# 1. New function",
      "Diff: `request.py#H1`",
      "---",
      "# 2. Old function",
      "Diff: `request.py#H1@old:L1-L2`",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });

    assert.equal((html.match(/Function: deliver_request/g) ?? []).length, 2);
    assert.equal((html.match(/Function: send_request/g) ?? []).length, 2);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("uses a focused Diff range instead of the whole hunk for its target definition", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-focused-diff-target-"));
  const sourcePath = path.join(temporaryDirectory, "request.py");
  const diffPath = path.join(temporaryDirectory, "request.diff");
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");

  await writeFile(
    sourcePath,
    [
      "def send_request():",
      "    return True",
      "",
      "def audit_request():",
      "    return False",
    ].join("\n"),
    "utf8",
  );
  await writeFile(
    diffPath,
    [
      "diff --git a/request.py b/request.py",
      "--- a/request.py",
      "+++ b/request.py",
      "@@ -1,5 +1,5 @@",
      " def send_request():",
      "-    return False",
      "+    return True",
      " ",
      " def audit_request():",
      "     return False",
    ].join("\n"),
    "utf8",
  );
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader-diff",
      "version: 2",
      "diff: request.diff",
      "---",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "---",
      "# 1. Audit function",
      "Diff: `request.py#H1@new:L4-L5`",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, { root: temporaryDirectory, padding: 0 });

    assert.equal((html.match(/Function: audit_request/g) ?? []).length, 2);
    assert.doesNotMatch(html, /Function: send_request/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
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

  const partial = renderDiffSnippet(file.hunks[0], {
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
      '  local path = path or "/"',
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
    reference: {
      side: "new",
      startBound: { mode: "absolute", value: 5 },
      endBound: { mode: "absolute", value: 5 },
    },
  });
  assert.equal(partial.rows.some((row) => row.after.number === 3), false);
  assert.equal(partial.rows.some((row) => row.after.number === 4), true);
  assert.equal(partial.rows.some((row) => row.after.number === 5), true);
  assert.equal(partial.rows.some((row) => row.after.number === 6), true);
  assert.equal(partial.rows.some((row) => row.after.number === 7), false);
  assert.equal(partial.rows.some((row) => row.after.number === 8), false);
  assert.deepEqual(
    partial.rows.filter((row) => row.after.focused).map((row) => row.after.number),
    [5],
  );
});

test("crops a large contiguous diff block to the selected rows", () => {
  const hunk = {
    oldStart: 1,
    oldEnd: 400,
    newStart: 1,
    newEnd: 400,
    lines: [
      ...Array.from({ length: 400 }, (_, index) => ({
        kind: "delete",
        oldLine: index + 1,
        text: `old-${index + 1}`,
      })),
      ...Array.from({ length: 400 }, (_, index) => ({
        kind: "add",
        newLine: index + 1,
        text: `new-${index + 1}`,
      })),
    ],
  };

  const snippet = renderDiffSnippet(hunk, {
    padding: 0,
    reference: {
      side: "new",
      startBound: { mode: "absolute", value: 200 },
      endBound: { mode: "absolute", value: 200 },
    },
  });

  assert.equal(snippet.rows.length, 1);
  assert.equal(snippet.rows[0].before.number, 200);
  assert.equal(snippet.rows[0].after.number, 200);
  assert.equal(snippet.rows[0].after.focused, true);
});

test("generates a map-first PDF with separate portrait and landscape pages", async () => {
  const markdownPath = path.join(demoRoot, ".code_reader", "walkthrough.md");
  const markdown = await readFile(markdownPath, "utf8");
  const document = parseCodeReaderDocument(markdown, { markdownPath });
  const html = await renderCodeReaderHtml(document, { root: demoRoot, padding: 5 });
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-pdf-"));
  const output = path.join(temporaryDirectory, "walkthrough.pdf");

  try {
    assert.match(html, /relationship-map--execution-map/);
    assert.match(html, /semantic-position-map/);
    assert.match(html, /Current explanation scope/);
    const parseExplanation = html.match(
      /<h1>2\. Normalize optional request data<\/h1>[\s\S]*?<\/article>\n<\/div>\n<\/section>/,
    )?.[0];
    assert.ok(parseExplanation);
    assert.match(parseExplanation, /semantic-position-map__node is-current"[^>]*>[\s\S]*?Parsed request/);
    assert.doesNotMatch(parseExplanation, /semantic-position-map__node is-current"[^>]*>[\s\S]*?Raw request/);
    assert.match(parseExplanation, /semantic-position-map__edge is-current/);
    assert.doesNotMatch(html, /class="mermaid"/);
    const result = await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));
    const dimensions = pdf.getPages().map((page) => page.getSize());

    assert.equal(result.mermaidCount, 0);
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
    assert.match(html, /<meta name="color-scheme" content="light">/);
    assert.match(html, /color-scheme: light/);
    assert.match(html, /<h2>Before<\/h2>/);
    assert.match(html, /<h2>After<\/h2>/);
    assert.match(html, /code-line--deleted/);
    assert.match(html, /code-line--added/);
    assert.match(html, /class="code-range-focus"/);
    assert.match(html, /\.code-block \{ background: #fff;/);
    assert.match(html, /\.code-range-focus \{ border: 1px solid #2563eb; border-left: 4px solid #2563eb;/);
    assert.doesNotMatch(html, /code-line--focused/);
    const fullHunkSection = html.match(
      /<header class="code-header">\n<span>Diff H1<\/span><strong>src\/app\.lua<\/strong>[\s\S]*?<\/section>\n<section class="pdf-section/,
    )?.[0];
    assert.ok(fullHunkSection);
    assert.doesNotMatch(fullHunkSection, /code-line--focused/);
    await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));

    assert.equal(pdf.getPageCount() > 1, true);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("marks screen explanations for A4-width content-sized pages", async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "code-reader-screen-explanation-"));
  const markdownPath = path.join(temporaryDirectory, "walkthrough.md");
  const sourcePath = path.join(temporaryDirectory, "example.lua");

  await writeFile(sourcePath, "return true\n", "utf8");
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader",
      "version: 2",
      "---",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "A short introduction.",
      "---",
      "# 1. Explain the result",
      "Source: `example.lua#L1`",
      "This short explanation should not fill an A4 page.",
    ].join("\n"),
    "utf8",
  );

  try {
    const document = parseCodeReaderDocument(await readFile(markdownPath, "utf8"), { markdownPath });
    const html = await renderCodeReaderHtml(document, {
      root: temporaryDirectory,
      padding: 0,
      layout: "screen",
    });

    assert.match(html, /data-screen-page-kind="explanation"/);
    assert.match(html, /class="explanation-content" data-screen-content/);
    assert.match(html, /\.pdf-layout--screen \.pdf-section--explanation\[data-screen-page\] \{ width: 174mm; \}/);
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
  const sourceLines = Array.from({ length: 12 }, (_, index) => `${longLine} -- ${index + 1}`);

  await writeFile(sourcePath, `${sourceLines.join("\n")}\n`, "utf8");
  await writeFile(nextSourcePath, "return true\n", "utf8");
  await writeFile(
    markdownPath,
    [
      "---",
      "type: code-reader",
      "version: 2",
      "---",
      "",
      "<!-- code-reader: front-page -->",
      "# Overview",
      "",
      "---",
      "# Wide source",
      "",
      "Source: `wide.lua#L1-L12`",
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
    assert.match(html, /data-screen-page-kind="explanation"/);
    assert.match(html, /white-space: pre;/);
    await writePdfFromHtml(html, output, await findBrowserExecutable());
    const pdf = await PDFDocument.load(await readFile(output));
    const dimensions = pdf.getPages().map((page) => page.getSize());

    assert.equal(pdf.getPageCount(), 5);
    assert.equal(dimensions[2].width > 842, true);
    assert.equal(dimensions[2].height > 595, true);
    assert.equal(dimensions[3].width > 590 && dimensions[3].width < 600, true);
    assert.equal(dimensions[3].height < 842, true);
    assert.equal(dimensions[4].width > dimensions[4].height, true);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
