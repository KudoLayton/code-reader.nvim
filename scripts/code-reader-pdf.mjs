#!/usr/bin/env node
import { main } from "../plugins/code-reader-authoring/scripts/pdf/cli.mjs";

main().catch((error) => {
  console.error(`Code Reader PDF: ${error.message}`);
  process.exitCode = 1;
});
