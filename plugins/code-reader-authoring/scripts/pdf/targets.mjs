import path from "node:path";

const identifier = "[A-Za-z_$][\\w$]*";

function normalizedLines(lines) {
  return lines.map((line) => line.replace(/\/\/.*$/, "").replace(/--.*$/, ""));
}

function braceEnd(lines, startIndex) {
  let opened = false;
  let depth = 0;
  for (let index = startIndex; index < lines.length; index += 1) {
    const line = lines[index]
      .replace(/(['\"])(?:\\.|(?!\1).)*\1/g, "")
      .replace(/\/\/.*$/, "");
    for (const character of line) {
      if (character === "{") {
        opened = true;
        depth += 1;
      } else if (character === "}" && opened) {
        depth -= 1;
        if (depth === 0) {
          return index + 1;
        }
      }
    }
    if (!opened && line.includes(";")) {
      return undefined;
    }
  }
  return undefined;
}

function semicolonEnd(lines, startIndex) {
  for (let index = startIndex; index < lines.length; index += 1) {
    if (lines[index].includes(";")) {
      return index + 1;
    }
  }
  return startIndex + 1;
}

function indentationEnd(lines, startIndex) {
  const declaration = lines[startIndex];
  const indent = declaration.match(/^\s*/)?.[0].length ?? 0;
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.trim() || line.trimStart().startsWith("#")) {
      continue;
    }
    if ((line.match(/^\s*/)?.[0].length ?? 0) <= indent) {
      return index;
    }
  }
  return lines.length;
}

function luaFunctionEnd(lines, startIndex) {
  let depth = 0;
  for (let index = startIndex; index < lines.length; index += 1) {
    const line = lines[index].replace(/--.*$/, "");
    const starts = (line.match(/\bfunction\b|\b(?:if|for|while)\b[^\n]*\bdo\b|\brepeat\b|\bdo\b/g) ?? []).length;
    const ends = (line.match(/\bend\b|\buntil\b/g) ?? []).length;
    depth += starts - ends;
    if (depth <= 0 && index > startIndex) {
      return index + 1;
    }
  }
  return lines.length;
}

function declarationEnd(lines, startIndex, language, kind) {
  if (language === "python") {
    return indentationEnd(lines, startIndex);
  }
  if (language === "lua" && kind === "function") {
    return luaFunctionEnd(lines, startIndex);
  }
  const brace = braceEnd(lines, startIndex);
  if (brace) {
    return brace;
  }
  return semicolonEnd(lines, startIndex);
}

function declarationAt(line, language) {
  const patterns = [
    ["function", new RegExp(`^(?:export\\s+)?(?:default\\s+)?(?:async\\s+)?function\\s*\\*?\\s+(${identifier})\\b`)],
    ["function", new RegExp(`^(?:export\\s+)?(?:const|let|var)\\s+(${identifier})\\b.*=>`)],
    ["function", new RegExp(`^func\\s+(?:\\([^)]*\\)\\s*)?(${identifier})\\b`)],
    ["function", new RegExp(`^(?:pub\\s+)?(?:async\\s+)?fn\\s+(${identifier})\\b`)],
    ["function", new RegExp(`^(?:async\\s+)?def\\s+(${identifier})\\b`)],
    ["function", new RegExp(`^(?:local\\s+)?function\\s+([A-Za-z_][\\w_.:]*)\\b`)],
    ["type", new RegExp(`^(?:export\\s+)?(?:default\\s+)?(?:abstract\\s+)?class\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^(?:export\\s+)?(?:declare\\s+)?interface\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^(?:export\\s+)?type\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^(?:export\\s+)?(?:const\\s+)?enum\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^class\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^type\\s+(${identifier})\\s+(?:struct|interface)\\b`)],
    ["type", new RegExp(`^(?:pub\\s+)?(?:struct|enum|trait)\\s+(${identifier})\\b`)],
    ["type", new RegExp(`^(?:typedef\\s+)?(?:struct|enum|union)\\s+(${identifier})\\b`)],
  ];
  return patterns.map(([kind, pattern]) => {
    const match = line.match(pattern);
    return match ? { kind, name: match[1] } : undefined;
  }).find(Boolean);
}

function languageForPath(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  if (extension === ".py" || extension === ".pyi") {
    return "python";
  }
  if (extension === ".lua") {
    return "lua";
  }
  return "brace";
}

function leafDefinitions(definitions) {
  return definitions.filter(
    (definition) =>
      !definitions.some(
        (candidate) =>
          candidate !== definition &&
          definition.startLine <= candidate.startLine &&
          candidate.endLine <= definition.endLine &&
          (definition.startLine !== candidate.startLine || definition.endLine !== candidate.endLine),
      ),
  );
}

export function findTargetDefinitions(lines, filePath, startLine, endLine) {
  if (!Array.isArray(lines) || startLine < 1 || endLine < startLine) {
    return [];
  }
  const language = languageForPath(filePath);
  const source = normalizedLines(lines);
  const definitions = [];
  for (let index = 0; index < source.length; index += 1) {
    const declaration = declarationAt(source[index].trim(), language);
    if (!declaration) {
      continue;
    }
    definitions.push({
      ...declaration,
      startLine: index + 1,
      endLine: declarationEnd(source, index, language, declaration.kind),
    });
  }

  const startedInRange = definitions.filter(
    (definition) => definition.startLine >= startLine && definition.startLine <= endLine,
  );
  const containing = definitions.filter(
    (definition) => definition.startLine <= startLine && definition.endLine >= endLine,
  );
  const overlapping = definitions.filter(
    (definition) => definition.startLine <= endLine && definition.endLine >= startLine,
  );
  const selected = startedInRange.length > 0
    ? leafDefinitions(startedInRange)
    : containing.length > 0
      ? [containing.reduce((smallest, definition) => (
        definition.endLine - definition.startLine < smallest.endLine - smallest.startLine ? definition : smallest
      ))]
      : leafDefinitions(overlapping);
  return selected
    .sort((left, right) => left.startLine - right.startLine || left.endLine - right.endLine)
    .map(({ kind, name }) => ({ kind, name }));
}

export function formatTargetDefinition(target) {
  return `${target.kind === "function" ? "Function" : "Type"}: ${target.name}`;
}
