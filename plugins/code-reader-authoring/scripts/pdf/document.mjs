import path from "node:path";

function splitLines(text) {
  if (!text) {
    return [];
  }

  return text.replace(/\r\n?/g, "\n").split("\n");
}

function unquote(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseYamlScalar(value) {
  const scalar = unquote(value);
  if (scalar === "true") return true;
  if (scalar === "false") return false;
  if (/^-?\d+(?:\.\d+)?$/.test(scalar)) return Number(scalar);
  return scalar;
}

function tokenizeRestrictedYaml(lines) {
  return lines.filter((line) => line.text.trim() !== "").map((line) => {
    const whitespace = line.text.match(/^\s*/)[0].length;
    if (whitespace % 2 !== 0) {
      throw new Error(`YAML indentation must use two spaces (line ${line.line}).`);
    }
    return { indent: whitespace / 2, text: line.text.trim(), line: line.line };
  });
}

function parseYamlBlock(tokens, position, indent) {
  const list = tokens[position]?.text.startsWith("- ");
  const result = list ? [] : {};
  while (position < tokens.length) {
    const token = tokens[position];
    if (token.indent !== indent || token.text.startsWith("- ") !== list) break;
    if (list) {
      const text = token.text.slice(2).trim();
      position += 1;
      const pair = text.match(/^([\w-]+):\s*(.*?)\s*$/);
      if (!pair) {
        result.push(parseYamlScalar(text));
        continue;
      }
      const item = {};
      if (pair[2]) {
        item[pair[1]] = parseYamlScalar(pair[2]);
      } else if (tokens[position]?.indent > indent) {
        const child = parseYamlBlock(tokens, position, tokens[position].indent);
        item[pair[1]] = child.value;
        position = child.position;
      } else {
        item[pair[1]] = {};
      }
      if (tokens[position]?.indent > indent) {
        const child = parseYamlBlock(tokens, position, tokens[position].indent);
        if (Array.isArray(child.value)) throw new Error(`List item continuation must be a mapping (line ${token.line}).`);
        Object.assign(item, child.value);
        position = child.position;
      }
      result.push(item);
      continue;
    }
    const pair = token.text.match(/^([\w-]+):\s*(.*?)\s*$/);
    if (!pair) throw new Error(`Invalid YAML mapping (line ${token.line}).`);
    position += 1;
    if (pair[2]) {
      result[pair[1]] = parseYamlScalar(pair[2]);
    } else if (tokens[position]?.indent > indent) {
      const child = parseYamlBlock(tokens, position, tokens[position].indent);
      result[pair[1]] = child.value;
      position = child.position;
    } else {
      result[pair[1]] = {};
    }
  }
  return { value: result, position };
}

function extractV2Metadata(lines) {
  const start = lines.findIndex((line) => line.text.trim() === "```code-reader");
  if (start < 0) return { metadata: {}, lines };
  const end = lines.findIndex((line, index) => index > start && line.text.trim() === "```");
  if (end < 0) throw new Error(`Code Reader metadata fence is not closed (line ${lines[start].line}).`);
  const tokens = tokenizeRestrictedYaml(lines.slice(start + 1, end));
  const metadata = tokens.length ? parseYamlBlock(tokens, 0, tokens[0].indent).value : {};
  return { metadata, lines: lines.filter((_, index) => index < start || index > end) };
}

function parseFrontmatter(lines) {
  if (lines[0]?.trim() !== "---") {
    return { frontmatter: {}, startIndex: 0 };
  }

  const endIndex = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
  if (endIndex === -1) {
    throw new Error("Code Reader frontmatter is not closed.");
  }

  const frontmatter = {};
  for (const line of lines.slice(1, endIndex)) {
    const match = line.match(/^\s*([^:#]+):\s*(.*?)\s*$/);
    if (match) {
      frontmatter[match[1].trim()] = unquote(match[2]);
    }
  }

  return { frontmatter, startIndex: endIndex + 1 };
}

function splitSections(lines, startIndex) {
  const sections = [];
  let current = [];
  let sectionStart = startIndex + 1;

  for (let index = startIndex; index < lines.length; index += 1) {
    if (lines[index].trim() === "---") {
      if (current.length > 0) {
        sections.push({ lines: current, startLine: sectionStart });
      }
      current = [];
      sectionStart = index + 2;
      continue;
    }
    current.push({ text: lines[index], line: index + 1 });
  }

  if (current.length > 0) {
    sections.push({ lines: current, startLine: sectionStart });
  }

  return sections;
}

function parseSourceReferences(line) {
  const references = [];
  const pattern = /([\w.~/\\-]+)#L(\d+)(?:-L(\d+))?(?:@sha256:([a-fA-F0-9]+))?/g;

  for (const match of line.matchAll(pattern)) {
    const startLine = Number(match[2]);
    references.push({
      path: match[1].replaceAll("\\", "/"),
      startLine,
      endLine: Number(match[3] ?? startLine),
      expectedHash: match[4]?.toLowerCase(),
    });
  }

  return references;
}

function parseBound(value) {
  const normalized = value.replace(/^\(|\)$/g, "");
  const number = Number(normalized);
  if (!Number.isInteger(number)) {
    return undefined;
  }
  return {
    mode: /^[+-]/.test(normalized) ? "relative" : "absolute",
    value: number,
  };
}

function parseDiffModifier(value) {
  const padding = value.match(/^(?:padding|pad)=(\d+)$/);
  if (padding) {
    return { padding: Number(padding[1]) };
  }

  const range = value.match(/^L(\([^)]*\)|[+-]?\d+)-L(\([^)]*\)|[+-]?\d+)$/);
  if (!range) {
    return {};
  }

  return {
    startBound: parseBound(range[1]),
    endBound: parseBound(range[2]),
  };
}

function parseDiffReferences(line) {
  const references = [];
  const pattern = /([\w.~/\\-]+)#(H\d+)(?:@([\w]+):([^\s`\]]+))?/gi;

  for (const match of line.matchAll(pattern)) {
    const side = match[3]?.toLowerCase();
    const normalizedSide = side === "a" ? "old" : side === "b" ? "new" : side;
    references.push({
      path: match[1].replaceAll("\\", "/"),
      hunkId: match[2].toUpperCase(),
      side: normalizedSide === "old" || normalizedSide === "new" ? normalizedSide : undefined,
      ...parseDiffModifier(match[4] ?? ""),
    });
  }

  return references;
}

function parseTargetReference(line) {
  const match = line.match(/^Target:\s*(function|type)\s+(.+?)\s*$/i);
  if (!match) {
    return undefined;
  }
  return { kind: match[1].toLowerCase(), name: match[2] };
}

function normalizeEvidence(metadata) {
  const byId = new Map();
  const evidence = [];
  for (const item of metadata.evidence ?? []) {
    const id = Number(item.id);
    const kind = String(item.kind ?? "").toLowerCase();
    if (!Number.isInteger(id) || id < 1 || !["source", "diff", "sketch"].includes(kind) || !item.target) continue;
    const normalized = {
      id,
      kind,
      target: String(item.target),
      claim: String(item.claim ?? ""),
      purpose: item.purpose ? String(item.purpose) : undefined,
      coverage: item.coverage,
      textModel: item.text_model,
    };
    if (kind === "source") {
      normalized.source = parseSourceReferences(normalized.target)[0];
      const cursor = parseSourceReferences(String(item.cursor ?? ""))[0];
      if (normalized.source && cursor?.path === normalized.source.path) normalized.source.cursorLine = cursor.startLine;
    } else if (kind === "diff") {
      normalized.diffReference = parseDiffReferences(normalized.target)[0];
    } else {
      normalized.path = normalized.target.replaceAll("\\", "/");
      normalized.editableTarget = item.editable_target ? String(item.editable_target) : undefined;
      normalized.editablePath = normalized.editableTarget?.replaceAll("\\", "/");
    }
    evidence.push(normalized);
    byId.set(id, normalized);
  }
  return { evidence, evidenceById: byId };
}

function parseStep(section, index, version) {
  const { metadata, lines } = version === "2" ? extractV2Metadata(section.lines) : { metadata: {}, lines: section.lines };
  const headingIndex = lines.findIndex((line) => /^#{1,6}\s+/.test(line.text));
  const heading = headingIndex >= 0 ? lines[headingIndex] : undefined;
  const headingMatch = heading?.text.match(/^(#{1,6})\s+(.+?)\s*$/);
  const isFrontPage = metadata.kind === "overview" || (index === 0 && lines.some((line) => line.text.trim() === "<!-- code-reader: front-page -->"));
  const body = [];
  const sources = [];
  const diffReferences = [];
  let target;

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    const value = line.text.trim();
    if (lineIndex === headingIndex || value === "<!-- code-reader: front-page -->") {
      continue;
    }
    if (/^Source:\s*/i.test(value)) {
      sources.push(...parseSourceReferences(value));
      continue;
    }
    if (/^Diff:\s*/i.test(value)) {
      diffReferences.push(...parseDiffReferences(value));
      continue;
    }
    if (/^Cursor:\s*/i.test(value)) {
      continue;
    }
    if (/^Target:\s*/i.test(value)) {
      target = parseTargetReference(value);
      continue;
    }
    body.push(line.text);
  }

  const normalizedEvidence = normalizeEvidence(metadata);
  for (const item of normalizedEvidence.evidence) {
    if (item.source) sources.push(item.source);
    if (item.diffReference) diffReferences.push(item.diffReference);
  }

  return {
    kind: isFrontPage ? "front_page" : "step",
    id: isFrontPage ? "front" : String(metadata.id ?? index + 1),
    title: headingMatch?.[2] ?? `Step ${index + 1}`,
    depth: headingMatch ? headingMatch[1].length : 1,
    body: body.join("\n").trim(),
    sources,
    diffReferences,
    target,
    metadata,
    mapAnchor: metadata.map_anchor,
    evidence: normalizedEvidence.evidence,
    evidenceById: normalizedEvidence.evidenceById,
    startLine: section.startLine,
  };
}

export function parseCodeReaderDocument(text, options = {}) {
  const lines = splitLines(text);
  const { frontmatter, startIndex } = parseFrontmatter(lines);
  const type = frontmatter.type;
  if (type !== "code-reader" && type !== "code-reader-diff") {
    throw new Error("Expected frontmatter type `code-reader` or `code-reader-diff`.");
  }
  if (frontmatter.version !== "2") {
    throw new Error("Expected Code Reader format version `2`.");
  }

  return {
    type,
    frontmatter,
    markdownPath: options.markdownPath,
    markdownDirectory: options.markdownPath ? path.dirname(options.markdownPath) : undefined,
    steps: splitSections(lines, startIndex).map((section, index) => parseStep(section, index, frontmatter.version)),
  };
}

function parseDiffRange(startText, countText) {
  const start = Number(startText);
  const count = Number(countText || 1);
  return { start, count, end: count === 0 ? start : start + count - 1 };
}

function normalizePatchPath(value) {
  const source = value.trim().split(/\s+/)[0];
  if (source === "/dev/null") {
    return undefined;
  }
  return source.replace(/^[ab]\//, "");
}

export function parseUnifiedDiff(text) {
  const files = [];
  let file;
  let hunk;

  for (const line of splitLines(text)) {
    if (line.startsWith("--- ")) {
      file = { oldPath: normalizePatchPath(line.slice(4)), newPath: undefined, path: undefined, hunks: [] };
      files.push(file);
      hunk = undefined;
      continue;
    }
    if (line.startsWith("+++ ") && file) {
      file.newPath = normalizePatchPath(line.slice(4));
      file.path = file.newPath ?? file.oldPath;
      continue;
    }

    const header = line.match(/^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@/);
    if (header && file) {
      const oldRange = parseDiffRange(header[1], header[2]);
      const newRange = parseDiffRange(header[3], header[4]);
      hunk = {
        id: `H${file.hunks.length + 1}`,
        oldStart: oldRange.start,
        oldCount: oldRange.count,
        oldEnd: oldRange.end,
        newStart: newRange.start,
        newCount: newRange.count,
        newEnd: newRange.end,
        lines: [],
      };
      file.hunks.push(hunk);
      continue;
    }

    if (hunk && !line.startsWith("\\")) {
      const prefix = line[0];
      if (prefix === " " || prefix === "+" || prefix === "-") {
        hunk.lines.push({
          kind: prefix === " " ? "context" : prefix === "+" ? "add" : "delete",
          text: line.slice(1),
        });
      }
    }
  }

  for (const fileItem of files) {
    for (const hunkItem of fileItem.hunks) {
      let oldLine = hunkItem.oldStart;
      let newLine = hunkItem.newStart;
      for (const line of hunkItem.lines) {
        if (line.kind === "context") {
          line.oldLine = oldLine;
          line.newLine = newLine;
          oldLine += 1;
          newLine += 1;
        } else if (line.kind === "delete") {
          line.oldLine = oldLine;
          oldLine += 1;
        } else {
          line.newLine = newLine;
          newLine += 1;
        }
      }
    }
  }

  return { files };
}

export function buildSourceSnippet(sourceLines, reference, padding) {
  const startLine = Math.max(1, reference.startLine - padding);
  const endLine = Math.min(sourceLines.length, reference.endLine + padding);
  return {
    path: reference.path,
    lines: sourceLines.slice(startLine - 1, endLine).map((text, offset) => {
      const number = startLine + offset;
      return {
        number,
        text,
        focused: number >= reference.startLine && number <= reference.endLine,
      };
    }),
  };
}

function blankCell() {
  return { number: undefined, text: "", marker: "", kind: "blank", focused: false };
}

function codeCell(number, text, marker = "", kind = "context", focused = false) {
  return { number, text, marker, kind, focused };
}

function appendContext(rows, beforeLines, afterLines, oldLine, newLine, focused = false) {
  rows.push({
    before: codeCell(oldLine, beforeLines[oldLine - 1] ?? "", "", "context", focused),
    after: codeCell(newLine, afterLines[newLine - 1] ?? "", "", "context", focused),
  });
}

function appendChangeRows(rows, deletes, adds) {
  const pairs = Math.min(deletes.length, adds.length);
  for (let index = 0; index < pairs; index += 1) {
    rows.push({
      before: codeCell(deletes[index].oldLine, deletes[index].text, "~", "modified", true),
      after: codeCell(adds[index].newLine, adds[index].text, "~", "modified", true),
    });
  }
  for (const entry of deletes.slice(pairs)) {
    rows.push({ before: codeCell(entry.oldLine, entry.text, "-", "deleted", true), after: blankCell() });
  }
  for (const entry of adds.slice(pairs)) {
    rows.push({ before: blankCell(), after: codeCell(entry.newLine, entry.text, "+", "added", true) });
  }
}

export function resolveReferenceRange(hunk, reference, padding) {
  if (!reference?.side) {
    return undefined;
  }
  const side = reference.side === "old" ? "before" : "after";
  const sideStart = side === "before" ? hunk.oldStart : hunk.newStart;
  const sideEnd = side === "before" ? hunk.oldEnd : hunk.newEnd;
  const resolveBound = (bound, isStart) => {
    if (!bound) {
      return undefined;
    }
    if (bound.mode === "absolute") {
      return bound.value;
    }
    return (isStart ? sideStart : sideEnd) + bound.value;
  };
  const partial = reference.startBound !== undefined || reference.endBound !== undefined;
  const startLine = Math.max(
    1,
    reference.padding !== undefined
      ? sideStart - reference.padding
      : resolveBound(reference.startBound, true) ?? sideStart,
  );
  const endLine = Math.max(
    startLine,
    reference.padding !== undefined
      ? sideEnd + reference.padding
      : resolveBound(reference.endBound, false) ?? sideEnd,
  );
  return {
    side,
    startLine,
    endLine,
    outputStart: Math.max(1, startLine - padding),
    outputEnd: endLine + padding,
    partial,
  };
}

function isWithinRange(cell, startLine, endLine) {
  return cell.number !== undefined && cell.number >= startLine && cell.number <= endLine;
}

function cropDiffRows(rows, range) {
  if (!range.partial) {
    return rows;
  }
  return rows.filter((row) => isWithinRange(row[range.side], range.outputStart, range.outputEnd));
}

export function renderDiffSnippet(hunk, options = {}) {
  const padding = Math.max(0, Number(options.padding ?? 0));
  const beforeLines = options.beforeLines ?? [];
  const afterLines = options.afterLines ?? [];
  const rows = [];

  for (let offset = padding; offset >= 1; offset -= 1) {
    const oldLine = hunk.oldStart - offset;
    const newLine = hunk.newStart - offset;
    if (oldLine >= 1 && newLine >= 1) {
      appendContext(rows, beforeLines, afterLines, oldLine, newLine);
    }
  }

  for (let index = 0; index < hunk.lines.length; ) {
    const entry = hunk.lines[index];
    if (entry.kind === "context") {
      rows.push({
        before: codeCell(entry.oldLine, entry.text),
        after: codeCell(entry.newLine, entry.text),
      });
      index += 1;
      continue;
    }

    const deletes = [];
    const adds = [];
    while (index < hunk.lines.length && hunk.lines[index].kind !== "context") {
      const change = hunk.lines[index];
      if (change.kind === "delete") {
        deletes.push(change);
      } else {
        adds.push(change);
      }
      index += 1;
    }
    appendChangeRows(rows, deletes, adds);
  }

  for (let offset = 1; offset <= padding; offset += 1) {
    const oldLine = hunk.oldEnd + offset;
    const newLine = hunk.newEnd + offset;
    if (oldLine <= beforeLines.length && newLine <= afterLines.length) {
      appendContext(rows, beforeLines, afterLines, oldLine, newLine);
    }
  }

  const range = resolveReferenceRange(hunk, options.reference, padding);
  if (range) {
    for (const row of rows) {
      for (const [side, cell] of [["before", row.before], ["after", row.after]]) {
        cell.focused = side === range.side && isWithinRange(cell, range.startLine, range.endLine);
      }
    }
  }

  return { rows: range ? cropDiffRows(rows, range) : rows };
}

function hunkSideLines(hunk, side) {
  return hunk.lines
    .filter((line) => line.kind === "context" || (side === "before" ? line.kind === "delete" : line.kind === "add"))
    .map((line) => line.text);
}

function linesMatch(lines, startLine, expected) {
  if (startLine < 1 || startLine + expected.length - 1 > lines.length) {
    return false;
  }
  return expected.every((line, index) => lines[startLine + index - 1] === line);
}

function replaceLines(lines, startLine, removeCount, replacement) {
  return [
    ...lines.slice(0, startLine - 1),
    ...replacement,
    ...lines.slice(startLine - 1 + removeCount),
  ];
}

function applyAll(file, lines, direction) {
  let result = [...lines];
  let offset = 0;
  for (const hunk of file.hunks) {
    const before = hunkSideLines(hunk, "before");
    const after = hunkSideLines(hunk, "after");
    const expected = direction === "forward" ? before : after;
    const replacement = direction === "forward" ? after : before;
    const startLine = (direction === "forward" ? hunk.oldStart : hunk.newStart) + offset;
    if (!linesMatch(result, startLine, expected)) {
      return undefined;
    }
    result = replaceLines(result, startLine, expected.length, replacement);
    offset += replacement.length - expected.length;
  }
  return result;
}

export function analyzeDiffFile(file, currentLines) {
  const afterLines = applyAll(file, currentLines, "forward");
  if (afterLines) {
    return { status: "applies", beforeLines: currentLines, afterLines };
  }

  const beforeLines = applyAll(file, currentLines, "reverse");
  if (beforeLines) {
    return { status: "already-applied", beforeLines, afterLines: currentLines };
  }

  return { status: "stale", beforeLines: [], afterLines: [] };
}
