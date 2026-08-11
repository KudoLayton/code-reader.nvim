import { readFile } from "node:fs/promises";
import path from "node:path";

import { findBrowserExecutable, writePdfFromHtml } from "./browser.mjs";
import { parseCodeReaderDocument } from "./document.mjs";
import { renderCodeReaderHtml } from "./render.mjs";

function usage() {
  return [
    "Usage: node scripts/code-reader-pdf.mjs <markdown-file> [options]",
    "",
    "Options:",
    "  --output <pdf-file>   Write here instead of beside the Markdown input.",
    "  --root <project-root>  Resolve Source paths from this directory (default: current directory).",
    "  --padding <n>          Context lines before and after each source range (default: 5).",
    "  --layout <mode>        Use print (A4) or screen (auto-width code pages; default: print).",
    "  --browser <path>       Use this Chrome or Edge executable.",
  ].join("\n");
}

export function defaultOutputPath(inputPath) {
  const extension = path.extname(inputPath);
  return path.join(path.dirname(inputPath), `${path.basename(inputPath, extension)}.pdf`);
}

export function parseCliArguments(argv) {
  const options = { root: process.cwd(), padding: 5, layout: "print" };
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) {
      positional.push(value);
      continue;
    }
    if (value === "--help") {
      options.help = true;
      continue;
    }
    const key = value.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--") || !["output", "root", "padding", "layout", "browser"].includes(key)) {
      throw new Error(`Invalid option: ${value}`);
    }
    options[key] = next;
    index += 1;
  }

  if (options.help) {
    return options;
  }
  if (positional.length !== 1) {
    throw new Error(usage());
  }
  options.input = positional[0];
  options.padding = Number(options.padding);
  if (!Number.isInteger(options.padding) || options.padding < 0) {
    throw new Error("--padding must be a non-negative integer.");
  }
  if (!["print", "screen"].includes(options.layout)) {
    throw new Error("--layout must be either print or screen.");
  }
  return options;
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseCliArguments(argv);
  if (options.help) {
    console.log(usage());
    return;
  }

  const inputPath = path.resolve(options.input);
  const outputPath = path.resolve(options.output ?? defaultOutputPath(inputPath));
  const markdown = await readFile(inputPath, "utf8");
  const document = parseCodeReaderDocument(markdown, { markdownPath: inputPath });
  const html = await renderCodeReaderHtml(document, {
    root: options.root,
    padding: options.padding,
    layout: options.layout,
  });
  const browserPath = await findBrowserExecutable(options.browser);
  await writePdfFromHtml(html, outputPath, browserPath);
  console.log(`Created ${outputPath}`);
}
