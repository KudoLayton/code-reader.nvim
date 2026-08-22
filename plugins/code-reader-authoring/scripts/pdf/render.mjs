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
  resolveReferenceRange,
} from "./document.mjs";
import { resolveTargetDefinitions } from "./static-targets.mjs";

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
  const lines = rows
    .map((row, index) => {
      return [
        '<div class="code-line">',
        `<span class="line-number">${row.number ?? ""}</span>`,
        '<span class="diff-marker"></span>',
        `<code>${highlighted[index] || "&nbsp;"}</code>`,
        "</div>",
      ].join("");
    });
  return wrapFocusedRange(rows, lines, true);
}

function wrapFocusedRange(rows, lines, showFocusedRange) {
  if (!showFocusedRange) {
    return lines.join("\n");
  }
  const firstFocusedIndex = rows.findIndex((row) => row.focused);
  if (firstFocusedIndex < 0) {
    return lines.join("\n");
  }
  let lastFocusedIndex = firstFocusedIndex;
  for (let index = firstFocusedIndex + 1; index < rows.length; index += 1) {
    if (rows[index].focused) {
      lastFocusedIndex = index;
    }
  }
  const output = [];
  for (let index = 0; index < lines.length; index += 1) {
    if (index === firstFocusedIndex) {
      output.push('<div class="code-range-focus">');
    }
    output.push(lines[index]);
    if (index === lastFocusedIndex) {
      output.push("</div>");
    }
  }
  return output.join("\n");
}

function screenPageAttributes(screenPageName, kind) {
  if (!screenPageName) {
    return "";
  }
  return ` data-screen-page="${screenPageName}" data-screen-page-kind="${kind}" style="page: ${screenPageName}"`;
}

function screenContentAttributes(screenPageName) {
  return screenPageName ? " data-screen-content" : "";
}

function renderTargetDefinition(targets) {
  if (!targets?.length) {
    return "";
  }
  const labels = targets.map((target) => `${target.kind === "function" ? "Function" : "Type"}: ${target.name}`);
  return `<strong class="target-definition">${escapeHtml(labels.join(" · "))}</strong>`;
}

async function renderSourceSection(reference, sourceLines, padding, screenPageName, targets, evidence, anchor) {
  const snippet = buildSourceSnippet(sourceLines, reference, padding);
  const rows = await renderCodeRows(snippet.lines, reference.path);
  return [
    `<section id="${escapeHtml(anchor || "")}" class="pdf-section pdf-section--code"${screenPageAttributes(screenPageName, "code")}>`,
    '<header class="code-header">',
    `<span>${evidence ? `[${evidence.id}] Source` : "Source"}</span><strong>${escapeHtml(reference.path)}</strong>`,
    renderTargetDefinition(targets),
    `<span>L${reference.startLine}-L${reference.endLine}</span>`,
    "</header>",
    evidence ? `<p class="evidence-claim">${escapeHtml(evidence.claim)}</p>` : "",
    `<div class="code-block"${screenContentAttributes(screenPageName)}>${rows}</div>`,
    "</section>",
  ].join("\n");
}

async function renderDiffSection(reference, hunk, analysis, padding, screenPageName, targets, evidence, anchor) {
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
    `<section id="${escapeHtml(anchor || "")}" class="pdf-section pdf-section--code"${screenPageAttributes(screenPageName, "code")}>`,
    '<header class="code-header">',
    `<span>${evidence ? `[${evidence.id}] ` : ""}Diff ${escapeHtml(reference.hunkId)}</span><strong>${escapeHtml(reference.path)}</strong>`,
    renderTargetDefinition(targets),
    `<span>${escapeHtml(analysis.status)}</span>`,
    "</header>",
    evidence ? `<p class="evidence-claim">${escapeHtml(evidence.claim)}</p>` : "",
    `<div class="diff-grid"${screenContentAttributes(screenPageName)}>`,
    `<section><h2>Before</h2><div class="code-block">${before}</div></section>`,
    `<section><h2>After</h2><div class="code-block">${after}</div></section>`,
    "</div>",
    "</section>",
  ].join("\n");
}

async function readSketchSvg(root, evidence) {
  const sketchPath = path.resolve(root, evidence.path);
  let svg;
  try {
    svg = await readFile(sketchPath, "utf8");
  } catch (error) {
    throw new Error(`Cannot read sketch SVG ${evidence.path}: ${error.message}`);
  }
  if (!/<svg\b/i.test(svg)) {
    throw new Error(`Sketch asset is not an SVG: ${evidence.path}`);
  }
  return svg;
}

function isRelationshipMap(evidence) {
  return evidence.kind === "sketch" && /(?:^|-)(?:execution|handoff|state|structure)-map$/.test(evidence.purpose ?? "");
}

function renderInlineRelationshipMap(evidence, svg, anchor) {
  return [
    `<figure id="${escapeHtml(anchor)}" class="relationship-map relationship-map--${escapeHtml(evidence.purpose)}">`,
    `<figcaption><strong>${escapeHtml(evidence.purpose.replaceAll("-", " "))}</strong> — ${escapeHtml(evidence.claim)}</figcaption>`,
    `<div class="relationship-map-svg">${svg}</div>`,
    "</figure>",
  ].join("\n");
}

async function renderSketchSection(root, evidence, screenPageName, anchor) {
  const svg = await readSketchSvg(root, evidence);
  return [
    `<section id="${escapeHtml(anchor)}" class="pdf-section pdf-section--sketch"${screenPageAttributes(screenPageName, "sketch")}>`,
    '<header class="code-header">',
    `<span>[${evidence.id}] Sketch</span><strong>${escapeHtml(evidence.path)}</strong>`,
    "</header>",
    `<p class="evidence-claim">${escapeHtml(evidence.claim)}</p>`,
    `<div class="sketch-svg"${screenContentAttributes(screenPageName)}>${svg}</div>`,
    "</section>",
  ].join("\n");
}

async function renderDiffRows(rows, filePath, showFocusedRange) {
  const highlighted = await highlightRows(rows, filePath);
  const lines = rows
    .map((row, index) => {
      const classes = ["code-line", `code-line--${row.kind}`];
      return [
        `<div class="${classes.join(" ")}">`,
        `<span class="line-number">${row.number ?? ""}</span>`,
        `<span class="diff-marker">${escapeHtml(row.marker)}</span>`,
        `<code>${highlighted[index] || "&nbsp;"}</code>`,
        "</div>",
      ].join("");
    });
  return wrapFocusedRange(rows, lines, showFocusedRange);
}

function executionMaps(document) {
  const maps = [];
  for (const step of document.steps) {
    for (const evidence of step.evidence ?? []) {
      if (evidence.kind !== "sketch" || evidence.purpose !== "execution-map" || !evidence.textModel) continue;
      const nodes = new Map((evidence.textModel.nodes ?? []).filter((node) => node?.id).map((node) => [node.id, node]));
      const edges = new Map((evidence.textModel.edges ?? []).filter((edge) => edge?.id).map((edge) => [edge.id, edge]));
      maps.push({ id: evidence.id, nodes, edges, edgeList: [...edges.values()] });
    }
  }
  return maps;
}

function anchorIds(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === "string" && item) : [];
}

function resolveSemanticPosition(document, step) {
  if (step.metadata?.kind !== "stage") return undefined;
  const maps = executionMaps(document);
  if (maps.length === 0) return undefined;
  const anchor = step.mapAnchor;
  let map;
  let nodeIds;
  let edgeIds;
  if (anchor && typeof anchor === "object") {
    map = maps.find((candidate) => candidate.id === Number(anchor.map));
    nodeIds = anchorIds(anchor.nodes);
    edgeIds = anchorIds(anchor.edges);
  } else if (maps.length === 1 && maps[0].nodes.has(step.id)) {
    map = maps[0];
    nodeIds = [step.id];
    edgeIds = [];
  }
  if (!map) return undefined;
  const selectedNodeIds = new Set(nodeIds.filter((id) => map.nodes.has(id)));
  const focusNodes = new Set(selectedNodeIds);
  const selectedEdges = new Set(edgeIds.filter((id) => map.edges.has(id)));
  for (const edgeId of selectedEdges) {
    const edge = map.edges.get(edgeId);
    focusNodes.add(edge.from);
    focusNodes.add(edge.to);
  }
  if (focusNodes.size === 0 && selectedEdges.size === 0) return undefined;
  const incoming = map.edgeList.filter((edge) => !selectedEdges.has(edge.id) && focusNodes.has(edge.to) && !focusNodes.has(edge.from));
  const outgoing = map.edgeList.filter((edge) => !selectedEdges.has(edge.id) && focusNodes.has(edge.from) && !focusNodes.has(edge.to));
  return { map, nodeIds, edgeIds, selectedNodeIds, focusNodes, selectedEdges, incoming, outgoing };
}

function positionLabel(position) {
  const labels = [
    ...position.nodeIds.map((id) => position.map.nodes.get(id)?.label ?? id),
    ...position.edgeIds.map((id) => position.map.edges.get(id)?.label ?? id),
  ];
  return labels.filter(Boolean).join(" · ");
}

function mapNodePositions(map) {
  const nodes = [...map.nodes.values()];
  const rank = new Map(nodes.map((node) => [node.id, 0]));
  for (let pass = 0; pass < nodes.length; pass += 1) {
    let changed = false;
    for (const edge of map.edgeList) {
      if (!rank.has(edge.from) || !rank.has(edge.to)) continue;
      const nextRank = Math.min(nodes.length - 1, rank.get(edge.from) + 1);
      if (nextRank > rank.get(edge.to)) {
        rank.set(edge.to, nextRank);
        changed = true;
      }
    }
    if (!changed) break;
  }
  const columns = new Map();
  for (const node of nodes) {
    const nodeRank = rank.get(node.id) ?? 0;
    if (!columns.has(nodeRank)) columns.set(nodeRank, []);
    columns.get(nodeRank).push(node);
  }
  const maxRank = Math.max(0, ...columns.keys());
  const tallestColumn = Math.max(1, ...[...columns.values()].map((column) => column.length));
  const positions = new Map();
  for (const [nodeRank, column] of columns) {
    column.forEach((node, index) => positions.set(node.id, { x: 26 + nodeRank * 230, y: 42 + index * 62 }));
  }
  return {
    positions,
    width: Math.max(520, 52 + (maxRank + 1) * 230),
    height: Math.max(118, 34 + tallestColumn * 62 + 38),
  };
}

function renderSemanticPositionMap(document, step) {
  const position = resolveSemanticPosition(document, step);
  if (!position) return "";
  const { map, selectedNodeIds, focusNodes, selectedEdges, incoming, outgoing } = position;
  const adjacentNodes = new Set([
    ...[...focusNodes].filter((id) => !selectedNodeIds.has(id)),
    ...incoming.flatMap((edge) => [edge.from, edge.to]),
    ...outgoing.flatMap((edge) => [edge.from, edge.to]),
  ]);
  const adjacentEdges = new Set([...incoming, ...outgoing].map((edge) => edge.id));
  const { positions, width, height } = mapNodePositions(map);
  const titleId = `semantic-position-${String(step.id).replace(/[^\w-]/g, "-")}`;
  const scope = positionLabel(position);
  const edgeMarkup = map.edgeList.map((edge) => {
    const from = positions.get(edge.from);
    const to = positions.get(edge.to);
    if (!from || !to) return "";
    const current = selectedEdges.has(edge.id);
    const adjacent = adjacentEdges.has(edge.id);
    const className = current ? " is-current" : adjacent ? " is-adjacent" : " is-muted";
    const startX = from.x + 126;
    const startY = from.y + 17;
    const endX = to.x;
    const endY = to.y + 17;
    const middleX = (startX + endX) / 2;
    const middleY = Math.min(startY, endY) - 8;
    return [
      `<g class="semantic-position-map__edge${className}">`,
      `<path d="M ${startX} ${startY} C ${middleX} ${startY}, ${middleX} ${endY}, ${endX} ${endY}" marker-end="url(#semantic-position-arrow)"/>`,
      edge.label ? `<text x="${middleX}" y="${middleY}" text-anchor="middle">${escapeHtml(String(edge.label))}</text>` : "",
      "</g>",
    ].join("");
  }).join("\n");
  const nodeMarkup = [...map.nodes.values()].map((node) => {
    const nodePosition = positions.get(node.id);
    if (!nodePosition) return "";
    const className = selectedNodeIds.has(node.id) ? " is-current" : adjacentNodes.has(node.id) ? " is-adjacent" : " is-muted";
    return [
      `<g class="semantic-position-map__node${className}" transform="translate(${nodePosition.x} ${nodePosition.y})">`,
      '<rect width="126" height="34" rx="7"/>',
      `<text x="63" y="21" text-anchor="middle">${escapeHtml(String(node.label ?? node.id))}</text>`,
      "</g>",
    ].join("");
  }).join("\n");
  return [
    `<figure class="semantic-position-map" aria-labelledby="${titleId}">`,
    `<figcaption id="${titleId}"><strong>Execution position</strong><span>Current explanation scope: ${escapeHtml(scope)}</span></figcaption>`,
    `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Current explanation scope: ${escapeHtml(scope)}. Current nodes are emphasized; direct handoffs are secondary.">`,
    '<defs><marker id="semantic-position-arrow" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto"><path d="M 0 0 L 7 3.5 L 0 7 z"/></marker></defs>',
    edgeMarkup,
    nodeMarkup,
    "</svg>",
    "</figure>",
  ].join("\n");
}

function parentStep(document, step) {
  const parentId = step.metadata?.parent;
  if (typeof parentId !== "string" || !parentId) return undefined;
  return document.steps.find((candidate) => candidate.metadata?.id === parentId);
}

function childSteps(document, step) {
  const stepId = step.metadata?.id;
  if (typeof stepId !== "string" || !stepId) return [];
  return document.steps.filter((candidate) => candidate.metadata?.parent === stepId);
}

function renderConceptualPosition(document, step) {
  const isModel = step.metadata?.kind === "model";
  const path = [];
  const seen = new Set();
  let current = step;
  while (current && !seen.has(current)) {
    seen.add(current);
    path.unshift(current);
    current = parentStep(document, current);
  }
  if (!isModel && path.length === 1) return "";
  const overview = document.steps.find((candidate) => candidate.kind === "front_page");
  const labels = [overview?.title, ...path.map((item) => item.title)].filter(Boolean);
  const model = step.metadata?.hierarchy ?? {};
  const children = isModel ? childSteps(document, step) : [];
  return [
    '<aside class="conceptual-position">',
    '<strong>Conceptual position</strong>',
    `<span>Path: ${escapeHtml(labels.join(" › "))}</span>`,
    isModel && model.contract ? `<span>Shared contract: ${escapeHtml(String(model.contract))}</span>` : "",
    isModel && model.decomposition ? `<span>Why these pages are separate: ${escapeHtml(String(model.decomposition))}</span>` : "",
    isModel && children.length ? `<span>Direct child scopes: ${escapeHtml(children.map((child) => child.title).join(" · "))}</span>` : "",
    "</aside>",
  ].filter(Boolean).join("\n");
}

function renderExplanationSection(step, index, total, screenPageName, targets, inlineMaps = [], conceptualPosition = "", positionMap = "") {
  return [
    `<section class="pdf-section pdf-section--explanation"${screenPageAttributes(screenPageName, "explanation")}>`,
    `<div class="explanation-content"${screenContentAttributes(screenPageName)}>`,
    '<header class="explanation-header">',
    `<span>Code Reader · ${step.kind === "front_page" ? "Overview" : `Step ${index}/${total}`}</span>`,
    renderTargetDefinition(targets),
    "</header>",
    `<h1>${escapeHtml(step.title)}</h1>`,
    conceptualPosition,
    positionMap,
    ...inlineMaps,
    '<article class="markdown-body">',
    step.html,
    "</article>",
    "</div>",
    "</section>",
  ].join("\n");
}

function semanticModelMarkdown(metadata = {}) {
  const lines = [];
  if (!metadata || Object.keys(metadata).length === 0) return "";
  lines.push("## Mental model", "");
  if (metadata.question) lines.push(`- Question: ${metadata.question}`);
  if (metadata.trigger) lines.push(`- Trigger: ${metadata.trigger}`);
  const state = metadata.state ?? {};
  if (state.status === "applicable") {
    lines.push("", "### State changes", "");
    for (const change of state.changes ?? []) {
      lines.push(
        `#### ${change.subject ?? "State"}`,
        "",
        `- **Owner:** ${change.owner ?? ""}`,
        `- **Before:** ${change.before ?? ""}`,
        `- **Change:** ${change.cause ?? ""}`,
        `- **After:** ${change.after ?? ""}`,
        `- **Must remain true:** ${change.invariant ?? ""}`,
        "",
      );
    }
  } else if (state.status === "not_applicable") {
    lines.push(`- State: N/A — ${state.reason ?? ""}`);
  }
  const responsibility = metadata.responsibility ?? {};
  if (responsibility.status === "applicable") {
    lines.push("", "### Responsibilities", "");
    for (const item of responsibility.items ?? []) {
      const owns = Array.isArray(item.owns) ? item.owns.join(", ") : item.owns ?? "";
      lines.push(`#### ${item.owner ?? "Owner"}`, "", `- **Does:** ${item.action ?? ""}`);
      if (owns) lines.push(`- **Owns:** ${owns}`);
      lines.push("");
    }
  } else if (responsibility.status === "not_applicable") {
    lines.push(`- Responsibility: N/A — ${responsibility.reason ?? ""}`);
  }
  const failure = metadata.failure ?? {};
  if (failure.status === "applicable") {
    lines.push("", "### Failure and alternate outcomes", "");
    for (const outcome of failure.outcomes ?? []) lines.push(`- ${outcome.cause ?? ""} → ${outcome.result ?? ""}`);
  } else if (failure.status === "not_applicable") {
    lines.push(`- Failure: N/A — ${failure.reason ?? ""}`);
  }
  return lines.join("\n");
}

function evidenceAnchor(step, evidence) {
  return `evidence-${String(step.id).replace(/[^\w-]/g, "-")}-${evidence.id}`;
}

function evidenceLinks(html, step) {
  return html.replace(/href="code-reader:\/\/evidence\/(\d+)"/g, (_match, id) => `href="#${evidenceAnchor(step, { id })}"`);
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

async function sourceTargetDefinitions(step, reference, sourceLines) {
  return step.target
    ? [step.target]
    : resolveTargetDefinitions(sourceLines, reference.path, reference.startLine, reference.endLine);
}

async function diffTargetDefinitions(step, reference, hunk, analysis) {
  if (step.target) {
    return [step.target];
  }
  const sides = reference.side ? [reference.side] : ["new", "old"];
  for (const side of sides) {
    const lines = side === "old" ? analysis.beforeLines : analysis.afterLines;
    const focusedRange = reference.side === side && (reference.startBound || reference.endBound)
      ? resolveReferenceRange(hunk, reference, 0)
      : undefined;
    const startLine = focusedRange?.startLine ?? (side === "old" ? hunk.oldStart : hunk.newStart);
    const endLine = focusedRange?.endLine ?? (side === "old" ? hunk.oldEnd : hunk.newEnd);
    const targets = await resolveTargetDefinitions(lines, reference.path, startLine, endLine);
    if (targets.length > 0) {
      return targets;
    }
  }
  return [];
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
  const nextScreenPageName = (kind) => (layout === "screen" ? `${kind}-screen-${++screenPageCount}` : undefined);

  for (let index = 0; index < document.steps.length; index += 1) {
    const step = document.steps[index];
    const legacyEvidence = document.type === "code-reader"
      ? step.sources.map((source, evidenceIndex) => ({ id: evidenceIndex + 1, kind: "source", source, claim: "" }))
      : step.diffReferences.map((diffReference, evidenceIndex) => ({ id: evidenceIndex + 1, kind: "diff", diffReference, claim: "" }));
    const evidence = step.evidence?.length ? step.evidence : legacyEvidence;
    const pages = [];
    const inlineMaps = [];
    for (const item of evidence) {
      if (item.kind === "source" && item.source) {
        const sourceLines = await loadSourceLines(root, item.source);
        pages.push({ item, kind: "source", reference: item.source, sourceLines, targets: await sourceTargetDefinitions(step, item.source, sourceLines) });
      } else if (item.kind === "diff" && item.diffReference) {
        const reference = item.diffReference;
        const file = diffModel?.files.find((candidate) => candidate.path === reference.path);
        const hunk = file?.hunks.find((candidate) => candidate.id === reference.hunkId);
        if (!hunk) throw new Error(`Cannot find ${reference.path}#${reference.hunkId} in the referenced diff.`);
        const analysis = await analyzeFile(root, file);
        pages.push({ item, kind: "diff", reference, hunk, analysis, targets: await diffTargetDefinitions(step, reference, hunk, analysis) });
      } else if (item.kind === "sketch") {
        if (isRelationshipMap(item)) {
          const anchor = evidenceAnchor(step, item);
          inlineMaps.push(renderInlineRelationshipMap(item, await readSketchSvg(root, item), anchor));
        } else {
          pages.push({ item, kind: "sketch", targets: [] });
        }
      }
    }
    step.html = evidenceLinks(await markdownToHtml([step.body, semanticModelMarkdown(step.metadata)].filter(Boolean).join("\n\n")), step);
    const conceptualPosition = renderConceptualPosition(document, step);
    const positionMap = renderSemanticPositionMap(document, step);
    sections.push(
      renderExplanationSection(
        step,
        index + 1,
        document.steps.length,
        nextScreenPageName("explanation"),
        pages.find((page) => page.targets?.length)?.targets,
        inlineMaps,
        conceptualPosition,
        positionMap,
      ),
    );
    for (const page of pages) {
      const anchor = evidenceAnchor(step, page.item);
      if (page.kind === "source") {
        sections.push(await renderSourceSection(page.reference, page.sourceLines, padding, nextScreenPageName("code"), page.targets, page.item, anchor));
      } else if (page.kind === "diff") {
        sections.push(await renderDiffSection(page.reference, page.hunk, page.analysis, padding, nextScreenPageName("code"), page.targets, page.item, anchor));
      } else {
        sections.push(await renderSketchSection(root, page.item, nextScreenPageName("sketch"), anchor));
      }
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
.pdf-section--code, .pdf-section--sketch { page: code; break-after: page; color: #1f2937; font-family: "Cascadia Mono", Consolas, monospace; }
.explanation-header { display: flex; gap: 4mm; align-items: baseline; color: #64748b; font-size: 9pt; letter-spacing: .04em; text-transform: uppercase; border-bottom: 1px solid #cbd5e1; padding-bottom: 4mm; }
.target-definition { color: #0f172a; font-family: "Cascadia Mono", Consolas, monospace; font-size: 8.5pt; font-weight: 600; letter-spacing: normal; text-transform: none; }
.explanation-header .target-definition { margin-left: auto; }
.code-header .target-definition { font-size: 8.5pt; }
.evidence-claim { margin: 0; padding: 3mm 4mm; color: #334155; background: #f8fafc; border: 1px solid #bfdbfe; border-top: 0; font: 10pt "Malgun Gothic", "Segoe UI", sans-serif; }
.sketch-svg { padding: 6mm; border: 1px solid #cbd5e1; border-top: 0; min-height: 120mm; display: grid; place-items: center; }
.sketch-svg svg { max-width: 100%; max-height: 165mm; width: auto; height: auto; }
.relationship-map { margin: 0 0 6mm; padding: 4mm; border: 1px solid #bfdbfe; background: #f8fbff; break-inside: avoid; }
.relationship-map figcaption { margin-bottom: 3mm; color: #334155; font-size: 9.5pt; }
.relationship-map-svg { display: grid; place-items: center; min-height: 58mm; }
.relationship-map-svg svg { max-width: 100%; max-height: 88mm; width: auto; height: auto; }
.conceptual-position { display: grid; gap: 1.5mm; margin: 0 0 6mm; padding: 3.5mm 4mm; border-left: 3px solid #4f46e5; background: #f5f3ff; color: #312e81; break-inside: avoid; font-size: 9.5pt; }
.conceptual-position strong { color: #312e81; }
.semantic-position-map { margin: 0 0 6mm; padding: 3.5mm 4mm; border: 1px solid #bfdbfe; background: #f8fbff; break-inside: avoid; }
.semantic-position-map figcaption { display: flex; gap: 3mm; align-items: baseline; margin-bottom: 2.5mm; color: #334155; font-size: 9.5pt; }
.semantic-position-map figcaption strong { color: #1e3a8a; }
.semantic-position-map svg { display: block; width: 100%; max-height: 72mm; }
.semantic-position-map__edge path { fill: none; stroke-width: 1.6; }
.semantic-position-map__edge text { fill: #475569; font: 10px "Malgun Gothic", "Segoe UI", sans-serif; }
.semantic-position-map__edge.is-muted path { stroke: #cbd5e1; }
.semantic-position-map__edge.is-muted text { fill: #94a3b8; }
.semantic-position-map__edge.is-adjacent path { stroke: #64748b; stroke-width: 2.2; }
.semantic-position-map__edge.is-current path { stroke: #2563eb; stroke-width: 3.4; }
.semantic-position-map__edge.is-current text { fill: #1d4ed8; font-weight: 700; }
.semantic-position-map__node rect { stroke-width: 1.2; }
.semantic-position-map__node text { font: 10px "Malgun Gothic", "Segoe UI", sans-serif; }
.semantic-position-map__node.is-muted rect { fill: #f8fafc; stroke: #cbd5e1; }
.semantic-position-map__node.is-muted text { fill: #94a3b8; }
.semantic-position-map__node.is-adjacent rect { fill: #e2e8f0; stroke: #64748b; stroke-width: 1.8; }
.semantic-position-map__node.is-adjacent text { fill: #334155; }
.semantic-position-map__node.is-current rect { fill: #dbeafe; stroke: #2563eb; stroke-width: 3; }
.semantic-position-map__node.is-current text { fill: #1e3a8a; font-weight: 700; }
.semantic-position-map marker path { fill: context-stroke; }
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
.code-range-focus { border: 1px solid #2563eb; border-left: 4px solid #2563eb; border-radius: 2px; overflow: hidden; }
.line-number { color: #6b7280; padding-right: 2mm; text-align: right; user-select: none; }
.code-range-focus .line-number, .code-range-focus .diff-marker { color: #1d4ed8; font-weight: 700; }
.code-line code { color: #1f2937; font-family: inherit; white-space: pre-wrap; overflow-wrap: anywhere; min-width: 0; padding-right: 3mm; }
.diff-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 5mm; }
.diff-grid h2 { color: #334155; font: 700 10pt "Malgun Gothic", "Segoe UI", sans-serif; margin: 3mm 0 2mm; }
.diff-marker { color: #64748b; text-align: center; }
.code-line--deleted { background: #fee2e2; }
.code-line--added { background: #dcfce7; }
.code-line--modified { background: #fef3c7; }
.pdf-layout--screen .pdf-section--code { break-after: page; break-inside: avoid-page; }
.pdf-layout--screen .pdf-section--explanation[data-screen-page] { width: 174mm; }
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
