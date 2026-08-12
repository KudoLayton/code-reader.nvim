import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const resolverPath = fileURLToPath(new URL("../resolve_target_definitions.py", import.meta.url));
const pythonCommands = [...new Set([process.env.CODE_READER_PYTHON, "python", "python3"].filter(Boolean))];

function runResolver(command, text, filePath, startLine, endLine) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, [resolverPath, "--path", filePath, "--range", `L${startLine}-L${endLine}`], {
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `target-definition resolver exited with code ${code}`));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch {
        reject(new Error("target-definition resolver returned invalid JSON"));
      }
    });
    child.stdin.end(text);
  });
}

export async function resolveTargetDefinitions(lines, filePath, startLine, endLine) {
  if (!Array.isArray(lines) || startLine < 1 || endLine < startLine) {
    return [];
  }
  const text = lines.join("\n");
  for (const command of pythonCommands) {
    try {
      const result = await runResolver(command, text, filePath, startLine, endLine);
      return result.status === "SUPPORTED" && Array.isArray(result.definitions) ? result.definitions : [];
    } catch {
      // Try the next configured Python command; the PDF must still render without a label.
    }
  }
  return [];
}
