vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.code_reader/assets", "p")
vim.fn.mkdir(tmp .. "/src", "p")
vim.fn.writefile({ "local M = {}", "function M.parse()", "  return true", "end", "return M" }, tmp .. "/src/request.lua")
vim.fn.writefile({ '<svg xmlns="http://www.w3.org/2000/svg"><metadata>excalidraw</metadata></svg>' }, tmp .. "/.code_reader/assets/request.svg")
vim.fn.writefile({ '{"type":"excalidraw","version":2,"elements":[],"appState":{},"files":{}}' }, tmp .. "/.code_reader/assets/request.excalidraw")
local walkthrough = tmp .. "/.code_reader/walkthrough.md"
vim.fn.writefile({
  "---",
  "type: code-reader",
  "version: 2",
  "feature: request-flow",
  "---",
  "# Overview",
  "```code-reader",
  "kind: overview",
  "id: request-flow",
  "question: What happens to a request?",
  "state:",
  "  status: not_applicable",
  "  reason: Overview is descriptive.",
  "responsibility:",
  "  status: applicable",
  "  items:",
  "    - owner: app.handle",
  "      action: Coordinate the flow",
  "evidence:",
  "  - id: 1",
  "    kind: sketch",
  "    purpose: execution-map",
  "    target: .code_reader/assets/request.svg",
  "    editable_target: .code_reader/assets/request.excalidraw",
  "    claim: The map shows the request lifecycle.",
  "    coverage:",
  "      - parse-request",
  "    text_model:",
  "      claim: The request moves through the lifecycle.",
  "      nodes:",
  "        - id: raw",
  "          label: Raw request",
  "          owner: app.handle",
  "          state: raw",
  "        - id: decoded",
  "          label: Decoded request",
  "          owner: request.parse",
  "          state: decoded",
  "      edges:",
  "        - id: parse",
  "          from: raw",
  "          to: decoded",
  "          label: parse",
  "```",
  "The execution map is [1](code-reader://evidence/1).",
  "---",
  "# Request parsing model",
  "```code-reader",
  "kind: model",
  "id: request-parsing-model",
  "question: How do the parsing responsibilities establish a decoded request?",
  "state:",
  "  status: not_applicable",
  "  reason: The model summarizes its children.",
  "responsibility:",
  "  status: applicable",
  "  items:",
  "    - owner: request.parse",
  "      action: Establish the decoded request contract",
  "hierarchy:",
  "  contract: Decoded requests have canonical fields.",
  "  decomposition: Parsing and ownership are easier to inspect separately.",
  "```",
  "The model gives the shared contract.",
  "---",
  "# 1. Parse request",
  "```code-reader",
  "kind: stage",
  "id: parse-request",
  "parent: request-parsing-model",
  "map_anchor:",
  "  map: 1",
  "  nodes:",
  "    - decoded",
  "  edges:",
  "    - parse",
  "question: How does raw input become decoded data?",
  "trigger: app.handle receives raw input",
  "state:",
  "  status: applicable",
  "  changes:",
  "    - subject: request",
  "      owner: request.parse",
  "      before: raw",
  "      cause: parser runs",
  "      after: decoded",
  "      invariant: decoded request has defaults",
  "    - subject: parser_cache",
  "      owner: cache.store",
  "      before: empty",
  "      cause: parser result is cached",
  "      after: populated",
  "      invariant: cache entry belongs to the decoded request",
  "responsibility:",
  "  status: applicable",
  "  items:",
  "    - owner: request.parse",
  "      action: Normalize fields",
  "failure:",
  "  status: not_applicable",
  "  reason: Parser supplies defaults.",
  "evidence:",
  "  - id: 1",
  "    kind: source",
  "    target: src/request.lua#L1-L4",
  "    claim: Parser creates the decoded request.",
  "  - id: 2",
  "    kind: sketch",
  "    purpose: handoff-map",
  "    target: .code_reader/assets/request.svg",
  "    editable_target: .code_reader/assets/request.excalidraw",
  "    claim: Ownership moves from handler to parser.",
  "    text_model:",
  "      claim: Parser owns the decoded request.",
  "      nodes:",
  "        - id: raw",
  "          label: Raw request",
  "          owner: app.handle",
  "          state: raw",
  "        - id: decoded",
  "          label: Decoded request",
  "          owner: request.parse",
  "          state: decoded",
  "      edges:",
  "        - from: raw",
  "          to: decoded",
  "          label: parse",
  "```",
  "The parser creates the request [1](code-reader://evidence/1).",
  "The ownership handoff is shown in [2](code-reader://evidence/2).",
}, walkthrough)

vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/src/request.lua"))
local code_reader = require("code_reader")
code_reader.setup({ sketch = { enabled = true } })
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(walkthrough))
local overview_state = code_reader.state()
eq(vim.api.nvim_win_get_buf(overview_state.windows.code) == overview_state.buffers.sketch, true, "overview execution map opens by default")
code_reader.next()
local model_state = code_reader.state()
local model_text = table.concat(vim.api.nvim_buf_get_lines(model_state.buffers.explanation, 0, -1, false), "\n")
eq(model_text:find("## Conceptual position", 1, true) ~= nil, true, "model conceptual position heading")
eq(model_text:find("Shared contract", 1, true) ~= nil, true, "model shared contract")
eq(model_text:find("Direct child scopes", 1, true) ~= nil, true, "model child scopes")
code_reader.next()
local state = code_reader.state()
eq(vim.api.nvim_win_get_buf(state.windows.code) == state.buffers.sketch, true, "handoff map opens by default")
local explanation_text = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
eq(explanation_text:find("## Mental model", 1, true) ~= nil, true, "stage mental model heading")
eq(explanation_text:find("## Conceptual position", 1, true) ~= nil, true, "stage conceptual position heading")
eq(explanation_text:find("Request parsing model", 1, true) ~= nil, true, "stage conceptual parent")
eq(explanation_text:find("## Execution position", 1, true) ~= nil, true, "stage execution position heading")
eq(explanation_text:find("Current explanation scope", 1, true) ~= nil, true, "stage execution position scope")
eq(explanation_text:find("### State changes", 1, true) ~= nil, true, "stage state changes heading")
eq(explanation_text:find("#### request", 1, true) ~= nil, true, "state change is a bullet card")
eq(explanation_text:find("#### parser_cache", 1, true) ~= nil, true, "independent state change has its own bullet card")
eq(explanation_text:find("| Subject |", 1, true) == nil, true, "state transition table is removed")
eq(explanation_text:find("### Responsibilities", 1, true) ~= nil, true, "stage responsibilities heading")
eq(explanation_text:find("| Owner |", 1, true) == nil, true, "responsibility table is removed")
local sketch_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
eq(sketch_text:find("# Sketch fallback", 1, true) ~= nil, true, "sketch fallback title")
eq(sketch_text:find("Parser owns the decoded request.", 1, true) ~= nil, true, "sketch fallback claim")
eq(sketch_text:find("request.parse", 1, true) ~= nil, true, "sketch fallback ownership")
eq(code_reader.select_evidence(1), true, "source evidence selection")
eq(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(state.windows.code)):match("request%.lua$") ~= nil, true, "source evidence opens source")
eq(code_reader.select_evidence(2), true, "sketch evidence selection")
eq(code_reader.edit_sketch(), false, "missing editor command is rejected")
local edited_path
code_reader.setup({ sketch = { enabled = true, editor_command = function(path) edited_path = path end } })
eq(code_reader.edit_sketch(), true, "editable sketch command is called")
eq(edited_path:match("request%.excalidraw$") ~= nil, true, "editable sketch path is selected")
vim.cmd("CodeReaderClose")

print("evidence_spec: ok")
