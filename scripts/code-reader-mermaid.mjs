#!/usr/bin/env node

import { renderMermaidASCII } from "beautiful-mermaid";

const chunks = [];

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  chunks.push(chunk);
});

process.stdin.on("end", () => {
  const input = chunks.join("");
  const useAscii = process.argv.includes("--ascii");

  try {
    const rendered = renderMermaidASCII(input, {
      useAscii,
      colorMode: "none",
    });
    process.stdout.write(rendered.endsWith("\n") ? rendered : `${rendered}\n`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  }
});
